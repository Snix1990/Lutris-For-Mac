import Foundation

final class SteamAPI {
    static let shared = SteamAPI()

    private init() {}

    // MARK: - SteamID Detection

    /// Liest die erste Steam64-ID aus `loginusers.vdf`
    func detectSteamID() -> String? {
        let vdfPath = NSHomeDirectory() + "/Library/Application Support/Steam/config/loginusers.vdf"
        guard let content = try? String(contentsOfFile: vdfPath, encoding: .utf8) else { return nil }

        let lines = content.components(separatedBy: .newlines)
        var inUsers = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed == "\"users\"" {
                inUsers = true
                continue
            }

            if inUsers && trimmed == "{" { continue }

            if inUsers && trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"") && !trimmed.contains("=") {
                let id = trimmed
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                if id.allSatisfy(\.isNumber), id.count == 17 {
                    return id
                }
            }

            if inUsers && trimmed == "}" {
                break
            }
        }

        return nil
    }

    /// Extrahiert den AccountName für einen gegebenen Steam64-ID aus loginusers.vdf
    func detectAccountName(steamID: String) -> String? {
        let vdfPath = NSHomeDirectory() + "/Library/Application Support/Steam/config/loginusers.vdf"
        guard let content = try? String(contentsOfFile: vdfPath, encoding: .utf8) else { return nil }

        let lines = content.components(separatedBy: .newlines)
        var inTargetUser = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed == "\"\(steamID)\"" {
                inTargetUser = true
                continue
            }

            if inTargetUser {
                if trimmed == "{" { continue }
                if trimmed == "}" { break }
                if trimmed.hasPrefix("\"AccountName\"") {
                    let parts = trimmed.components(separatedBy: "\"")
                    if parts.count >= 5 {
                        return parts[3]
                    }
                }
            }
        }

        return nil
    }

    // MARK: - API Calls

    private let baseURL = "https://api.steampowered.com"

    func fetchOwnedGames(apiKey: String, steamID: String) async throws -> [SteamGameInfo] {
        var components = URLComponents(string: "\(baseURL)/IPlayerService/GetOwnedGames/v1/")!
        components.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "steamid", value: steamID),
            URLQueryItem(name: "include_appinfo", value: "true"),
            URLQueryItem(name: "include_played_free_games", value: "true"),
        ]

        guard let url = components.url else { throw SteamError.invalidURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SteamError.requestFailed("No response")
        }

        if httpResponse.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? "<no body>"
            throw SteamError.requestFailed("HTTP \(httpResponse.statusCode): \(body)")
        }

        let decoded = try JSONDecoder().decode(SteamGetOwnedGamesResponse.self, from: data)
        return decoded.response?.games ?? []
    }

    func fetchPlayerSummaries(apiKey: String, steamID: String) async throws -> SteamPlayerSummary? {
        var components = URLComponents(string: "\(baseURL)/ISteamUser/GetPlayerSummaries/v2/")!
        components.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "steamids", value: steamID),
        ]

        guard let url = components.url else { throw SteamError.invalidURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SteamError.requestFailed("No response")
        }

        if httpResponse.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? "<no body>"
            throw SteamError.requestFailed("HTTP \(httpResponse.statusCode): \(body)")
        }

        let decoded = try JSONDecoder().decode(SteamPlayerSummariesResponse.self, from: data)
        return decoded.response?.players?.first
    }

    // MARK: - Cover URL

    func coverURL(for appID: Int) -> URL {
        URL(string: "https://steamcdn-a.akamaihd.net/steam/apps/\(appID)/library_600x900.jpg")!
    }

    func headerURL(for appID: Int) -> URL {
        URL(string: "https://steamcdn-a.akamaihd.net/steam/apps/\(appID)/header.jpg")!
    }

    func iconURL(for appID: Int, hash: String) -> URL? {
        URL(string: "https://steamcdn-a.akamaihd.net/steamcommunity/public/images/apps/\(appID)/\(hash).jpg")
    }
}

enum SteamError: LocalizedError {
    case invalidURL
    case requestFailed(String)
    case noSteamID
    case noAPIKey

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Ungültige URL"
        case .requestFailed(let msg): return "API-Fehler: \(msg)"
        case .noSteamID: return "Keine Steam-ID gefunden. Stelle sicher, dass Steam installiert ist und du eingeloggt bist."
        case .noAPIKey: return "Kein Steam Web API Key hinterlegt."
        }
    }
}
