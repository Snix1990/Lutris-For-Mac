import Foundation

final class UpdaterService: @unchecked Sendable {
    static let shared = UpdaterService()
    let repoOwner = "Snix1990"
    let repoName = "Lutris-For-Mac"

    struct ReleaseInfo {
        let version: String
        let downloadURL: URL?
        let releaseNotes: String?
    }

    func checkForUpdate() async -> ReleaseInfo? {
        guard let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        else { return nil }

        let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tagName = json["tag_name"] as? String
        else { return nil }

        let latestVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName

        guard latestVersion.compare(currentVersion, options: .numeric) == .orderedDescending
        else { return nil }

        let assets = json["assets"] as? [[String: Any]] ?? []
        let packageAsset = assets.first { asset in
            guard let name = asset["name"] as? String else { return false }
            return name.hasSuffix(".dmg") || name.hasSuffix(".zip")
        }
        let downloadURL = packageAsset.flatMap {
            ($0["browser_download_url"] as? String).flatMap { URL(string: $0) }
        }
        let body = json["body"] as? String

        return ReleaseInfo(version: tagName, downloadURL: downloadURL, releaseNotes: body)
    }

    @discardableResult
    func downloadAndInstall(at url: URL) async throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let destination = tempDir.appendingPathComponent(url.lastPathComponent)

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        let (tempURL, _) = try await URLSession.shared.download(from: url)
        try FileManager.default.moveItem(at: tempURL, to: destination)

        return destination
    }
}
