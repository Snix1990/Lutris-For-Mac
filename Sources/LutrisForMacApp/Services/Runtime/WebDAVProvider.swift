import Foundation

// MARK: - WebDAV Errors

enum WebDAVError: LocalizedError {
    case notConfigured
    case invalidURL
    case authenticationFailed
    case httpError(Int, String)
    case unexpectedResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "WebDAV not configured"
        case .invalidURL: return "Invalid server URL"
        case .authenticationFailed: return "Authentication failed"
        case .httpError(let code, let msg): return "HTTP \(code): \(msg)"
        case .unexpectedResponse: return "Unexpected server response"
        }
    }
}

// MARK: - WebDAV Provider

@MainActor
final class WebDAVProvider: CloudSaveProvider {
    let name = "WebDAV"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    var isAvailable: Bool {
        CloudSyncSettingsManager.shared.settings.isValid
    }

    private var baseURL: URL? {
        let s = CloudSyncSettingsManager.shared.settings
        guard let url = URL(string: s.serverURL) else { return nil }
        let path = s.remotePath.hasPrefix("/") ? s.remotePath : "/\(s.remotePath)"
        return url.appendingPathComponent(path)
    }

    private var authHeader: String? {
        let mgr = CloudSyncSettingsManager.shared
        guard let password = mgr.savedPassword, !password.isEmpty else { return nil }
        let credentials = "\(mgr.settings.username):\(password)"
        guard let data = credentials.data(using: .utf8) else { return nil }
        return "Basic \(data.base64EncodedString())"
    }

    // MARK: - CloudSaveProvider

    func upload(snapshot: SaveSnapshot, files: [URL]) async throws {
        guard let base = baseURL else { throw WebDAVError.notConfigured }
        let headers = authHeaders()
        let gameDir = base.appendingPathComponent(snapshot.gameID.uuidString)
        let snapDir = gameDir.appendingPathComponent(snapshotLabelDir(snapshot))

        try await mkcol(url: snapDir, headers: headers)

        // Upload manifest
        let manifestData = try encoder.encode(snapshot)
        let manifestURL = snapDir.appendingPathComponent("saves.json")
        try await put(url: manifestURL, data: manifestData, headers: headers)

        // Upload files
        for fileURL in files {
            guard fileURL.startAccessingSecurityScopedResource() else { continue }
            defer { fileURL.stopAccessingSecurityScopedResource() }
            let data = try Data(contentsOf: fileURL)
            let remoteFile = snapDir.appendingPathComponent(fileURL.lastPathComponent)
            try await put(url: remoteFile, data: data, headers: headers)
        }
    }

    func download(snapshot: SaveSnapshot, to destination: URL) async throws {
        guard let base = baseURL else { throw WebDAVError.notConfigured }
        let headers = authHeaders()
        let gameDir = base.appendingPathComponent(snapshot.gameID.uuidString)
        let snapDir = gameDir.appendingPathComponent(snapshotLabelDir(snapshot))

        // Download manifest first
        let manifestURL = snapDir.appendingPathComponent("saves.json")
        let manifestData = try await get(url: manifestURL, headers: headers)
        let remoteSnapshot = try decoder.decode(SaveSnapshot.self, from: manifestData)
        guard remoteSnapshot.id == snapshot.id else { throw CloudSaveError.downloadFailed("Snapshot ID mismatch") }

        // Download files
        let fileManager = FileManager.default
        for file in snapshot.files {
            let remoteFile = snapDir.appendingPathComponent(file.relativePath)
            let localFile = destination.appendingPathComponent(file.relativePath)

            if file.isDirectory {
                try? fileManager.removeItem(at: localFile)
                try fileManager.createDirectory(at: localFile, withIntermediateDirectories: true)
            } else {
                let data = try await get(url: remoteFile, headers: headers)
                try? fileManager.removeItem(at: localFile)
                try fileManager.createDirectory(at: localFile.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: localFile)
            }
        }
    }

    func listSnapshots(gameID: UUID) async throws -> [SaveSnapshot] {
        guard let base = baseURL else { throw WebDAVError.notConfigured }
        let headers = authHeaders()
        let gameDir = base.appendingPathComponent(gameID.uuidString)

        // PROPFIND to list snapshot directories
        let entries = try await propfind(url: gameDir, headers: headers)

        var snapshots: [SaveSnapshot] = []
        for entry in entries where entry.hasSuffix("/") {
            let snapDir = gameDir.appendingPathComponent(entry)
            let manifestURL = snapDir.appendingPathComponent("saves.json")
            guard let data = try? await get(url: manifestURL, headers: headers),
                  let snapshot = try? decoder.decode(SaveSnapshot.self, from: data) else { continue }
            snapshots.append(snapshot)
        }
        return snapshots
    }

    func delete(snapshot: SaveSnapshot) async throws {
        guard let base = baseURL else { throw WebDAVError.notConfigured }
        let headers = authHeaders()
        let gameDir = base.appendingPathComponent(snapshot.gameID.uuidString)
        let snapDir = gameDir.appendingPathComponent(snapshotLabelDir(snapshot))
        try await delete(url: snapDir, headers: headers)
    }

    // MARK: - WebDAV Operations

    private func authHeaders() -> [String: String] {
        var headers = ["User-Agent": "LutrisForMac/1.0"]
        if let auth = authHeader {
            headers["Authorization"] = auth
        }
        return headers
    }

    /// PROPFIND – list collection
    private func propfind(url: URL, headers: [String: String]) async throws -> [String] {
        var req = URLRequest(url: url)
        req.httpMethod = "PROPFIND"
        req.setValue("application/xml", forHTTPHeaderField: "Content-Type")
        req.setValue("1", forHTTPHeaderField: "Depth")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        req.httpBody = """
        <?xml version="1.0"?>
        <d:propfind xmlns:d="DAV:">
            <d:prop><d:displayname/><d:resourcetype/></d:prop>
        </d:propfind>
        """.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw WebDAVError.unexpectedResponse }

        if http.statusCode == 404 { return [] }
        if http.statusCode == 401 { throw WebDAVError.authenticationFailed }
        guard (200...299).contains(http.statusCode) else {
            throw WebDAVError.httpError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        // Parse XML for hrefs
        return parseHREFs(data)
    }

    /// MKCOL – create collection
    private func mkcol(url: URL, headers: [String: String]) async throws {
        // Check if exists first
        if (try? await propfind(url: url, headers: headers)) != nil { return }

        var req = URLRequest(url: url)
        req.httpMethod = "MKCOL"
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw WebDAVError.unexpectedResponse }
        if http.statusCode == 405 { return } // Already exists
        if http.statusCode == 201 { return } // Created
        if http.statusCode == 409 {
            // Parent doesn't exist – create parent first
            let parent = url.deletingLastPathComponent()
            try await mkcol(url: parent, headers: headers)
            try await mkcol(url: url, headers: headers)
            return
        }
        if http.statusCode == 401 { throw WebDAVError.authenticationFailed }
        guard (200...299).contains(http.statusCode) else {
            throw WebDAVError.httpError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }

    /// PUT – upload
    private func put(url: URL, data: Data, headers: [String: String]) async throws {
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.httpBody = data
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw WebDAVError.unexpectedResponse }
        if http.statusCode == 401 { throw WebDAVError.authenticationFailed }
        guard (200...299).contains(http.statusCode) || http.statusCode == 204 else {
            throw WebDAVError.httpError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }

    /// GET – download
    private func get(url: URL, headers: [String: String]) async throws -> Data {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw WebDAVError.unexpectedResponse }
        if http.statusCode == 404 { throw CloudSaveError.downloadFailed("Resource not found") }
        if http.statusCode == 401 { throw WebDAVError.authenticationFailed }
        guard (200...299).contains(http.statusCode) else {
            throw WebDAVError.httpError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    /// DELETE – remove
    private func delete(url: URL, headers: [String: String]) async throws {
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw WebDAVError.unexpectedResponse }
        if http.statusCode == 404 { return } // Already gone
        if http.statusCode == 401 { throw WebDAVError.authenticationFailed }
        guard (200...299).contains(http.statusCode) || http.statusCode == 204 else {
            throw WebDAVError.httpError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }

    // MARK: - XML Parsing

    private func parseHREFs(_ data: Data) -> [String] {
        guard let xml = String(data: data, encoding: .utf8) else { return [] }
        var hrefs: [String] = []
        var idx = xml.startIndex
        let pattern = "<d:href>"
        let close = "</d:href>"
        while let start = xml[idx...].range(of: pattern) {
            let contentStart = start.upperBound
            guard let end = xml[contentStart...].range(of: close) else { break }
            let href = String(xml[contentStart..<end.lowerBound])
            // Decode percent-encoding + trim parent
            let decoded = href.removingPercentEncoding ?? href
            // Only return the last path component (collection name)
            if let last = decoded.split(separator: "/").last {
                hrefs.append(String(last) + (decoded.hasSuffix("/") ? "/" : ""))
            }
            idx = end.upperBound
        }
        return hrefs
    }

    private func snapshotLabelDir(_ snapshot: SaveSnapshot) -> String {
        "backup_\(ISO8601DateFormatter().string(from: snapshot.timestamp))"
    }
}
