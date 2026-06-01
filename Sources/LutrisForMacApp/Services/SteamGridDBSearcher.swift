import Foundation

struct SGDBGame: Codable, Identifiable {
    let id: Int
    let name: String
}

struct SGDBCover: Codable, Identifiable {
    let id: Int
    let url: String
}

struct SGDBResponse<T: Codable>: Codable {
    let data: [T]?
    let success: Bool
}

@MainActor
final class SteamGridDBSearcher: ObservableObject {
    @Published var results: [SGDBCover] = []
    @Published var isSearching = false
    @Published var error: String?

    private let apiKey: String

    init() {
        self.apiKey = UserDefaults.standard.string(forKey: "steamGridDBApiKey") ?? "91e6b8297bb68f99548e95d4028be9fe"
    }

    func searchGame(_ query: String) async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSearching = true
        error = nil
        results = []

        do {
            let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
            guard let url = URL(string: "https://www.steamgriddb.com/api/v2/search/autocomplete/\(encoded)") else { return }

            var request = URLRequest(url: url)
            request.setValue(apiKey, forHTTPHeaderField: "Authorization")

            let (data, _) = try await URLSession.shared.data(for: request)
            let decoded = try JSONDecoder().decode(SGDBResponse<SGDBGame>.self, from: data)
            let games = decoded.data ?? []

            var allCovers: [SGDBCover] = []
            for game in games.prefix(5) {
                let coverURL = URL(string: "https://www.steamgriddb.com/api/v2/grids/game/\(game.id)?dimensions=600x900")!
                var coverReq = URLRequest(url: coverURL)
                coverReq.setValue(apiKey, forHTTPHeaderField: "Authorization")
                if let (cd, _) = try? await URLSession.shared.data(for: coverReq),
                   let coverDecoded = try? JSONDecoder().decode(SGDBResponse<SGDBCover>.self, from: cd) {
                    allCovers.append(contentsOf: coverDecoded.data?.prefix(4) ?? [])
                }
            }
            results = allCovers
        } catch {
            self.error = error.localizedDescription
        }
        isSearching = false
    }
}
