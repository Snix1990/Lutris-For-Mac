import Foundation

// MARK: - SortOption

enum SortOption: String, CaseIterable {
    case name = "Name"
    case lastPlayed = "Zuletzt gespielt"
    case playTime = "Spielzeit"
    case rating = "Bewertung"
    case recentlyAdded = "Hinzugefügt"

    var displayName: String { tr(rawValue) }
}

// MARK: - GameLibraryViewModel

@MainActor
final class GameLibraryViewModel: ObservableObject {
    // MARK: - Published State
    @Published var games: [Game] = []
    @Published var selectedRunner: String? = nil
    @Published var selectedPlatform: String? = nil
    @Published var selectedCategory: Runner.RunnerCategory? = nil
    @Published var selectedGameCategory: String? = nil
    @Published var searchText: String = ""
    @Published var showFavoritesOnly: Bool = false
    @Published var sortOption: SortOption = .name
    @Published var sortAscending: Bool = true
    @Published var pendingManualGameID: UUID? = nil

    // MARK: - Filtered & Computed Properties

    var filteredGames: [Game] {
        var result = games

        if !searchText.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }

        if showFavoritesOnly {
            result = result.filter(\.isFavorite)
        }

        if let category = selectedCategory {
            result = result.filter { game in
                let runnerInst = RunnerManager.shared.runners.first(where: { $0.name == game.runner })
                return runnerInst?.category == category
            }
        }

        if let runner = selectedRunner {
            result = result.filter { $0.runner == runner || $0.serviceName == runner }
        }

        if let platform = selectedPlatform {
            result = result.filter { $0.platform == platform }
        }

        if let cat = selectedGameCategory {
            result = result.filter { $0.category == cat }
        }

        result.sort { a, b in
            let ascending = sortAscending
            switch sortOption {
            case .name:
                return ascending ? a.name.localizedCompare(b.name) == .orderedAscending : a.name.localizedCompare(b.name) == .orderedDescending
            case .lastPlayed:
                switch (a.lastPlayed, b.lastPlayed) {
                case (nil, nil): return ascending ? a.name < b.name : a.name > b.name
                case (nil, _): return ascending ? false : true
                case (_, nil): return ascending ? true : false
                case (let la?, let lb?): return ascending ? la < lb : la > lb
                }
            case .playTime:
                return ascending ? a.playTime < b.playTime : a.playTime > b.playTime
            case .rating:
                return ascending ? a.rating < b.rating : a.rating > b.rating
            case .recentlyAdded:
                return ascending ? a.id.uuidString < b.id.uuidString : a.id.uuidString > b.id.uuidString
            }
        }

        return result
    }

    var availableRunners: [String] {
        Array(Set(games.map(\.runner))).sorted()
    }

    var availablePlatforms: [String] {
        Array(Set(games.map(\.platform))).sorted()
    }

    var availableCategories: [Runner.RunnerCategory] {
        let used = Set(games.compactMap { game in
            RunnerManager.shared.runners.first(where: { $0.name == game.runner })?.category
        })
        return Runner.RunnerCategory.allCases.filter { used.contains($0) }
    }

    var availableGameCategories: [String] {
        Array(Set(games.map(\.category).filter { !$0.isEmpty })).sorted()
    }

    var favoriteCount: Int {
        games.filter(\.isFavorite).count
    }

    var totalPlayTime: TimeInterval {
        games.reduce(0) { $0 + $1.playTime }
    }

    var averageRating: Double {
        let rated = games.filter { $0.rating > 0 }
        guard !rated.isEmpty else { return 0 }
        return Double(rated.reduce(0) { $0 + $1.rating }) / Double(rated.count)
    }

    var mostPlayedGame: Game? {
        games.max(by: { $0.playTime < $1.playTime })
    }

    var lastPlayedGame: Game? {
        games.compactMap { $0.lastPlayed }.max().flatMap { date in
            games.first { $0.lastPlayed == date }
        }
    }

    var platformStats: [(String, Int)] {
        Dictionary(grouping: games, by: \.platform)
            .map { ($0.key, $0.value.count) }
            .sorted { $0.1 > $1.1 }
    }

    var categoryStats: [(String, Int)] {
        Dictionary(grouping: games.filter { !$0.category.isEmpty }, by: \.category)
            .map { ($0.key, $0.value.count) }
            .sorted { $0.1 > $1.1 }
    }

    var runnerStats: [(String, Int)] {
        Dictionary(grouping: games, by: \.runner)
            .map { ($0.key, $0.value.count) }
            .sorted { $0.1 > $1.1 }
    }

    var ratingStats: [Int: Int] {
        let valid = games.filter { $0.rating > 0 }
        return Dictionary(grouping: valid, by: \.rating).mapValues(\.count)
    }

    var gamesWithCategory: Int { games.filter { !$0.category.isEmpty }.count }
    var gamesRated: Int { games.filter { $0.rating > 0 }.count }

    // MARK: - Persistence

    private lazy var storageURL: URL = {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = folder.appendingPathComponent("LutrisForMac", isDirectory: true)
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
        return appFolder.appendingPathComponent("games.json")
    }()

    init() {
        loadLibrary()
    }

    func refreshLibrary() {
        loadLibrary()
    }

    private func loadLibrary() {
        if let data = try? Data(contentsOf: storageURL),
           let content = try? JSONDecoder().decode([Game].self, from: data),
           !content.isEmpty {
            games = content
            return
        }

        let sampleGames = [
            Game(name: "Super Example", platform: "macOS", installPath: "/Applications/SuperExample.app", runner: "Native", notes: "Ein Beispiel für ein Spiel.", category: "Produktivität", isFavorite: true, rating: 4, playTime: 7200),
            Game(name: "Retro Adventure", platform: "Wine", installPath: "/Users/Shared/RetroAdventure", runner: "Wine", environmentVariables: "WINEARCH=win32\nWINEPREFIX=~/.wine-retro", notes: "Funktioniert mit dem integrierten Wine-Runtime.", category: "Abenteuer", rating: 5, playTime: 36000, lastPlayed: Date().addingTimeInterval(-86400)),
            Game(name: "Indie Quest", platform: "macOS", installPath: "/Applications/IndieQuest.app", runner: "Native", notes: "Ein kleines Indie-Spiel.", category: "Indie", isFavorite: true, rating: 3, playTime: 1800),
        ]
        games = sampleGames
        saveLibrary()
    }

    func saveLibrary() {
        do {
            let data = try JSONEncoder().encode(games)
            try data.write(to: storageURL, options: [.atomic])
        } catch {
            #if DEBUG
            print("Fehler beim Speichern der Bibliothek: \(error)")
            #endif
        }
    }

    // MARK: - Game CRUD

    @discardableResult
    func addPlaceholderGame() -> Game {
        let newGame = Game(
            name: "Neues Spiel",
            platform: "macOS",
            installPath: "/Applications/MeinSpiel.app",
            runner: "Native"
        )
        games.append(newGame)
        saveLibrary()
        return newGame
    }

    func updateGame(_ game: Game) {
        guard let index = games.firstIndex(where: { $0.id == game.id }) else { return }
        games[index] = game
        saveLibrary()
    }

    func deleteGame(_ game: Game) {
        games.removeAll { $0.id == game.id }
        saveLibrary()
    }

    func recordPlaySession(gameID: UUID, duration: TimeInterval) {
        guard let index = games.firstIndex(where: { $0.id == gameID }) else { return }
        games[index].playTime += duration
        games[index].lastPlayed = Date()
        saveLibrary()
    }

    func toggleFavorite(gameID: UUID) {
        guard let index = games.firstIndex(where: { $0.id == gameID }) else { return }
        games[index].isFavorite.toggle()
        saveLibrary()
    }

    func setRating(gameID: UUID, rating: Int) {
        guard let index = games.firstIndex(where: { $0.id == gameID }) else { return }
        games[index].rating = min(max(rating, 0), 5)
        saveLibrary()
    }

    func setCategory(gameID: UUID, category: String) {
        guard let index = games.firstIndex(where: { $0.id == gameID }) else { return }
        games[index].category = category
        saveLibrary()
    }

    // MARK: - Steam Sync

    @Published var isSteamSyncing = false
    @Published var steamSyncProgress: String = ""
    @Published var steamSyncError: String?
    @Published var steamSyncResults: Int = 0

    func syncSteamLibrary(apiKey: String, steamID: String) async {
        guard !apiKey.isEmpty, !steamID.isEmpty else { return }
        isSteamSyncing = true
        steamSyncProgress = "Verbindung zu Steam…"
        steamSyncError = nil
        steamSyncResults = 0

        do {
            let steamGames = try await SteamAPI.shared.fetchOwnedGames(apiKey: apiKey, steamID: steamID)
            steamSyncProgress = "\(steamGames.count) Spiele gefunden, importiere…"
            var imported = 0

            for steamGame in steamGames {
                let appID = String(steamGame.appid)
                let name = steamGame.name ?? "Steam App \(appID)"

                guard !self.games.contains(where: { $0.steamAppID == appID }) else { continue }

                let cover = SteamAPI.shared.coverURL(for: steamGame.appid).absoluteString
                let game = Game(
                    name: name,
                    platform: "Steam",
                    installPath: "steam://rungameid/\(appID)",
                    runner: "Native",
                    notes: "Importiert von Steam (AppID: \(appID))",
                    category: "Steam",
                    playTime: TimeInterval(steamGame.playtimeForever),
                    coverURL: cover,
                    steamAppID: appID,
                    launchViaSteam: true
                )

                self.games.append(game)
                imported += 1
            }

            if imported > 0 { self.saveLibrary() }
            steamSyncResults = imported
            steamSyncProgress = "\(imported) neue Spiele importiert."
        } catch {
            steamSyncError = error.localizedDescription
            steamSyncProgress = "Fehlgeschlagen"
        }

        isSteamSyncing = false
    }

    // MARK: - CrossOver Import

    func importFromCrossOverBottles() -> Int {
        let candidates = WineManager.shared.scanCrossOverBottlesForGames()
        var added = 0

        for candidate in candidates {
            let installPath = candidate.exePath ?? "CrossOver:\(candidate.bottleName)"
            let prefixName = "CrossOver: \(candidate.bottleName)"
            guard !games.contains(where: { $0.installPath == installPath || ($0.name == candidate.name && $0.winePrefixName == prefixName) }) else { continue }

            let existingPrefix = WineManager.shared.prefixes.first(where: { $0.name == prefixName })
            let wineVersion = WineManager.shared.installedVersions.first(where: { $0.type == .crossover })

            let game = Game(
                name: candidate.name,
                platform: "Windows",
                installPath: installPath,
                runner: "CrossOver",
                category: "CrossOver",
                wineVersionName: wineVersion?.name,
                winePrefixName: existingPrefix?.name,
                winePrefixID: existingPrefix?.id,
                wineRenderMode: .auto,
                wineESync: true,
                wineShaderCache: true
            )
            games.append(game)
            added += 1
        }

        if added > 0 { saveLibrary() }
        return added
    }

    // MARK: - Script Runner

    func runInstallScript(for game: Game) async {
        let scriptPath = game.installScriptPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !scriptPath.isEmpty else {
            #if DEBUG
            print("Kein Installationsskript definiert für \(game.name).")
            #endif
            return
        }

        let scriptURL = URL(fileURLWithPath: scriptPath)
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            #if DEBUG
            print("Installationsskript-Datei existiert nicht: \(scriptURL.path)")
            #endif
            return
        }

        if !FileManager.default.isExecutableFile(atPath: scriptURL.path) {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        }

        let environment = ProcessRunner.parseEnvironmentVariables(from: game.environmentVariables)
        let currentDirectory = FileManager.default.fileExists(atPath: game.installPath)
            ? URL(fileURLWithPath: game.installPath, isDirectory: true)
            : nil

        do {
            let output = try await ProcessRunner.run(
                command: scriptURL.path,
                currentDirectory: currentDirectory,
                environment: environment
            )
            #if DEBUG
            print("Installationsskript ausgeführt für \(game.name):\n\(output)")
            #endif
        } catch {
            #if DEBUG
            print("Installationsskript-Fehler: \(error)")
            #endif
        }
    }
}
