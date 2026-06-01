import Foundation

@MainActor
final class CommunityInstallerService: ObservableObject {
    static let shared = CommunityInstallerService()

    @Published var scripts: [CommunityScript] = []
    @Published var isFetching = false
    @Published var lastError: String?
    @Published var searchText: String = ""

    var filteredScripts: [CommunityScript] {
        guard !searchText.isEmpty else { return scripts }
        return scripts.filter {
            $0.gameName.localizedCaseInsensitiveContains(searchText)
            || $0.runner.localizedCaseInsensitiveContains(searchText)
            || $0.description.localizedCaseInsensitiveContains(searchText)
        }
    }

    /// URL for the community script index.
    /// Default targets a placeholder; users can change to their own index URL.
    var indexURL: String {
        get { UserDefaults.standard.string(forKey: "communityIndexURL") ?? "https://raw.githubusercontent.com/user/repo/main/scripts/index.json" }
        set { UserDefaults.standard.set(newValue, forKey: "communityIndexURL") }
    }

    private let cacheDir: URL

    private init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = folder.appendingPathComponent("LutrisForMac", isDirectory: true)
        cacheDir = appFolder.appendingPathComponent("community", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        loadCached()
    }

    // MARK: - Index

    func fetchIndex() async {
        guard let url = URL(string: indexURL) else {
            lastError = "Ungültige Index-URL"
            return
        }
        isFetching = true
        lastError = nil
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode([CommunityScript].self, from: data)
            scripts = decoded
            saveCached(decoded)
        } catch {
            lastError = error.localizedDescription
        }
        isFetching = false
    }

    // MARK: - Download Script

    func downloadScript(_ meta: CommunityScript) async -> InstallerScript? {
        guard let url = URL(string: meta.scriptURL) else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            var script = try JSONDecoder().decode(InstallerScript.self, from: data)
            // Override metadata from the index entry
            script.name = "\(meta.gameName) – \(meta.runner)"
            script.gameName = meta.gameName
            script.version = meta.version
            script.runner = meta.runner
            script.platform = meta.platform
            script.description = meta.description
            return script
        } catch {
            lastError = "Fehler beim Download von \(meta.gameName): \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: - Cache

    private func cacheURL() -> URL {
        cacheDir.appendingPathComponent("index.json")
    }

    private func saveCached(_ entries: [CommunityScript]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: cacheURL(), options: .atomic)
    }

    private func loadCached() {
        guard let data = try? Data(contentsOf: cacheURL()),
              let entries = try? JSONDecoder().decode([CommunityScript].self, from: data) else { return }
        scripts = entries
    }

    func clearCache() {
        scripts = []
        try? FileManager.default.removeItem(at: cacheURL())
    }
}
