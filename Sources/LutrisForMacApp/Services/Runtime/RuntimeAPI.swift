import Foundation
import Network
import AppKit

// MARK: - RuntimeAPI

@MainActor
final class RuntimeAPI: ObservableObject {
    static let shared = RuntimeAPI()

    @Published var isRunning = false
    @Published var port: UInt16 = 9876

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.lutris.runtime-api", qos: .background)

    private var webhookURL: URL? {
        get {
            UserDefaults.standard.url(forKey: "webhookURL")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "webhookURL")
        }
    }

    private init() {}

    // MARK: - Server

    func start() {
        guard !isRunning else { return }
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            listener = try NWListener(using: params, on: NWEndpoint.Port(integerLiteral: port))
            listener?.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready:
                        self?.isRunning = true
                    case .failed(let err):
                        print("API server error: \(err)")
                        self?.isRunning = false
                    default:
                        break
                    }
                }
            }
            listener?.newConnectionHandler = { conn in
                Task { @MainActor in
                    RuntimeAPI.shared.handleConnection(conn)
                }
            }
            listener?.start(queue: queue)
        } catch {
            print("API server failed to start: \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    // MARK: - Connection Handling

    private func handleConnection(_ conn: NWConnection) {
            conn.stateUpdateHandler = { state in
                if state == .ready {
                    conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, error in
                        guard let data, !data.isEmpty else { conn.cancel(); return }
                        Task { @MainActor [conn] in
                            let response = self.handleRequest(data)
                            conn.send(content: response, completion: .contentProcessed { _ in conn.cancel() })
                        }
                    }
                }
            }
        conn.start(queue: queue)
    }

    private func handleRequest(_ data: Data) -> Data {
        guard let request = String(data: data, encoding: .utf8) else {
            return httpResponse(status: 400, body: "{\"error\":\"invalid request\"}")
        }

        let lines = request.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            return httpResponse(status: 400, body: "{\"error\":\"bad request line\"}")
        }

        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else {
            return httpResponse(status: 400, body: "{\"error\":\"bad request line\"}")
        }

        let method = parts[0]
        let path = parts[1]

        // Read body if present
        var body = ""
        if let bodyStart = lines.firstIndex(of: ""), bodyStart + 1 < lines.count {
            body = lines[bodyStart + 1..<lines.count].joined(separator: "\n")
        }

        return route(method: method, path: path, body: body)
    }

    private func route(method: String, path: String, body: String) -> Data {
        switch (method, path) {
        case ("GET", "/health"):
            return jsonResponse(["status": "ok", "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""])

        case ("GET", "/games"):
            let games = GameLibraryViewModel.shared.games.map { game in
                [
                    "id": game.id.uuidString,
                    "name": game.name,
                    "runner": game.runner,
                    "platform": game.platform,
                    "installPath": game.installPath,
                ]
            }
            return jsonResponse(["games": games])

        case ("POST", "/launch") where !body.isEmpty:
            guard let gameID = parseID(from: body) else {
                return httpResponse(status: 400, body: "{\"error\":\"missing gameID\"}")
            }
            Task { @MainActor in
                let games = GameLibraryViewModel.shared.games
                if let game = games.first(where: { $0.id == gameID }) {
                    _ = try? await WineManager.shared.launchGame(game: game)
                }
            }
            return jsonResponse(["status": "launching"])

        case ("POST", "/webhook"):
            if let data = body.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let urlStr = json["url"] as? String,
               let url = URL(string: urlStr) {
                webhookURL = url
                return jsonResponse(["status": "webhook set", "url": urlStr])
            }
            return httpResponse(status: 400, body: "{\"error\":\"missing url\"}")

        default:
            return httpResponse(status: 404, body: "{\"error\":\"not found\"}")
        }
    }

    // MARK: - Webhook

    func fireWebhook(gameName: String, playTime: TimeInterval, exitCode: Int32) {
        guard let url = webhookURL else { return }

        let payload: [String: Any] = [
            "event": "game_exit",
            "game": gameName,
            "playTime": Int(playTime),
            "playTimeFormatted": formatDuration(playTime),
            "exitCode": exitCode,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "source": "LutrisForMac",
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = jsonData

        URLSession.shared.dataTask(with: req).resume()
    }

    // MARK: - Scripting

    func runPreLaunchScript(_ script: String, gameName: String) {
        guard !script.isEmpty else { return }
        Task {
            let cmd = script.hasPrefix("#!") ? script : "/bin/bash -c '\(script.replacingOccurrences(of: "'", with: "'\\''"))'"
            _ = try? await ProcessRunner.run(command: cmd, currentDirectory: nil, environment: [
                "LUTRIS_GAME": gameName,
            ])
        }
    }

    func runPostExitScript(_ script: String, gameName: String, playTime: TimeInterval) {
        guard !script.isEmpty else { return }
        Task {
            let cmd = script.hasPrefix("#!") ? script : "/bin/bash -c '\(script.replacingOccurrences(of: "'", with: "'\\''"))'"
            _ = try? await ProcessRunner.run(command: cmd, currentDirectory: nil, environment: [
                "LUTRIS_GAME": gameName,
                "LUTRIS_PLAYTIME": "\(Int(playTime))",
            ])
        }
    }

    // MARK: - Helpers

    private func httpResponse(status: Int, body: String) -> Data {
        let statusText: String
        switch status {
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
        case 404: statusText = "Not Found"
        default: statusText = "Unknown"
        }
        let response = "HTTP/1.1 \(status) \(statusText)\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        return Data(response.utf8)
    }

    private func jsonResponse(_ dict: [String: Any]) -> Data {
        let body = (try? JSONSerialization.data(withJSONObject: dict)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return httpResponse(status: 200, body: body)
    }

    private func parseID(from body: String) -> UUID? {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let idStr = json["gameID"] as? String else { return nil }
        return UUID(uuidString: idStr)
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let h = Int(interval) / 3600
        let m = (Int(interval) % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}
