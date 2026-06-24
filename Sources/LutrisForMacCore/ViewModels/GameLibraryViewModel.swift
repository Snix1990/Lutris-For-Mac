import Foundation
import AppKit
import UniformTypeIdentifiers
import Combine

// MARK: - SortOption

public enum SortOption: String, CaseIterable {
    case name = "Name"
    case lastPlayed = "Zuletzt gespielt"
    case playTime = "Spielzeit"
    case rating = "Bewertung"
    case recentlyAdded = "Hinzugefügt"

    public var displayName: String { tr(rawValue) }
}

// MARK: - GameLibraryViewModel

@MainActor
public final class GameLibraryViewModel: ObservableObject {
    public static let shared = GameLibraryViewModel()
    // MARK: - Published State
    @Published public var games: [Game] = []
    @Published public var selectedRunner: String? = nil
    @Published public var selectedPlatform: String? = nil
    @Published public var selectedCategory: Runner.RunnerCategory? = nil
    @Published public var selectedGameCategory: String? = nil
    @Published public var searchText: String = ""
    @Published public var showFavoritesOnly: Bool = false
    @Published public var sortOption: SortOption = .name
    @Published public var sortAscending: Bool = true
    @Published public var pendingManualGameID: UUID? = nil

    // Pre-computed stats, invalidated on $games change
    @Published public private(set) var cachedTotalPlayTime: TimeInterval = 0
    @Published public private(set) var cachedAverageRating: Double = 0
    @Published public private(set) var cachedFavoriteCount: Int = 0
    @Published public private(set) var cachedMostPlayedGame: Game? = nil
    @Published public private(set) var cachedLastPlayedGame: Game? = nil
    @Published public private(set) var cachedPlatformStats: [(String, Int)] = []
    @Published public private(set) var cachedCategoryStats: [(String, Int)] = []
    @Published public private(set) var cachedRunnerStats: [(String, Int)] = []
    @Published public private(set) var cachedRatingStats: [Int: Int] = [:]
    @Published public private(set) var cachedAvailableRunners: [String] = []
    @Published public private(set) var cachedAvailablePlatforms: [String] = []
    @Published public private(set) var cachedAvailableCategories: [Runner.RunnerCategory] = []
    @Published public private(set) var cachedAvailableGameCategories: [String] = []
    @Published public private(set) var cachedGamesWithCategory: Int = 0
    @Published public private(set) var cachedGamesRated: Int = 0
    private var statsCancellable: AnyCancellable?

    private let saveQueue = DispatchQueue(label: "com.lutris.saveLibrary", qos: .background)

    // MARK: - Filtered & Computed Properties

    public var filteredGames: [Game] {
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

    public var availableRunners: [String] { cachedAvailableRunners }
    public var availablePlatforms: [String] { cachedAvailablePlatforms }
    public var availableCategories: [Runner.RunnerCategory] { cachedAvailableCategories }
    public var availableGameCategories: [String] { cachedAvailableGameCategories }
    public var favoriteCount: Int { cachedFavoriteCount }
    public var totalPlayTime: TimeInterval { cachedTotalPlayTime }
    public var averageRating: Double { cachedAverageRating }
    public var mostPlayedGame: Game? { cachedMostPlayedGame }
    public var lastPlayedGame: Game? { cachedLastPlayedGame }
    public var platformStats: [(String, Int)] { cachedPlatformStats }
    public var categoryStats: [(String, Int)] { cachedCategoryStats }
    public var runnerStats: [(String, Int)] { cachedRunnerStats }
    public var ratingStats: [Int: Int] { cachedRatingStats }
    public var gamesWithCategory: Int { cachedGamesWithCategory }
    public var gamesRated: Int { cachedGamesRated }

    // MARK: - Persistence

    private lazy var storageURL: URL = {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = folder.appendingPathComponent("LutrisForMac", isDirectory: true)
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
        return appFolder.appendingPathComponent("games.json")
    }()

    public init() {
        loadLibrary()
        setupCombine()
        setupBridges()
    }

    private func setupBridges() {
        OSDBridge.show = { OSDManager.shared.show() }
        OSDBridge.hide = { OSDManager.shared.hide() }
    }

    private func setupCombine() {
        statsCancellable = $games
            .receive(on: RunLoop.main)
            .sink { [weak self] games in
                self?.recomputeStats(games: games)
                ConsoleDataSource.games = games
                GameRepository.allGames = games
            }
    }

    private func recomputeStats(games: [Game]) {
        cachedTotalPlayTime = games.reduce(0) { $0 + $1.playTime }

        let rated = games.filter { $0.rating > 0 }
        cachedAverageRating = rated.isEmpty ? 0 : Double(rated.reduce(0) { $0 + $1.rating }) / Double(rated.count)

        cachedFavoriteCount = games.filter(\.isFavorite).count

        cachedMostPlayedGame = games.max(by: { $0.playTime < $1.playTime })

        let lastDate = games.compactMap(\.lastPlayed).max()
        cachedLastPlayedGame = lastDate.flatMap { date in games.first { $0.lastPlayed == date } }

        cachedPlatformStats = Dictionary(grouping: games, by: \.platform)
            .map { ($0.key, $0.value.count) }
            .sorted { $0.1 > $1.1 }

        let catFiltered = games.filter { !$0.category.isEmpty }
        cachedCategoryStats = Dictionary(grouping: catFiltered, by: \.category)
            .map { ($0.key, $0.value.count) }
            .sorted { $0.1 > $1.1 }

        cachedRunnerStats = Dictionary(grouping: games, by: \.runner)
            .map { ($0.key, $0.value.count) }
            .sorted { $0.1 > $1.1 }

        let valid = games.filter { $0.rating > 0 }
        cachedRatingStats = Dictionary(grouping: valid, by: \.rating).mapValues(\.count)

        cachedAvailableRunners = Array(Set(games.map(\.runner))).sorted()

        cachedAvailablePlatforms = Array(Set(games.map(\.platform))).sorted()

        let used = Set(games.compactMap { game in
            RunnerManager.shared.runners.first(where: { $0.name == game.runner })?.category
        })
        cachedAvailableCategories = Runner.RunnerCategory.allCases.filter { used.contains($0) }

        cachedAvailableGameCategories = Array(Set(games.map(\.category).filter { !$0.isEmpty })).sorted()

        cachedGamesWithCategory = catFiltered.count
        cachedGamesRated = rated.count
    }

    public func refreshLibrary() {
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

    public func saveLibrary() {
        do {
            let data = try JSONEncoder().encode(games)
            saveQueue.async { [storageURL] in
                try? data.write(to: storageURL, options: [.atomic])
            }
        } catch {
            #if DEBUG
            print("Fehler beim Kodieren der Bibliothek: \(error)")
            #endif
        }
    }

    // MARK: - Game CRUD

    @discardableResult
    public func addPlaceholderGame() -> Game {
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

    public func updateGame(_ game: Game) {
        guard let index = games.firstIndex(where: { $0.id == game.id }) else { return }
        games[index] = game
        saveLibrary()
    }

    public func deleteGame(_ game: Game) {
        games.removeAll { $0.id == game.id }
        saveLibrary()
    }

    public func recordPlaySession(gameID: UUID, duration: TimeInterval) {
        guard let index = games.firstIndex(where: { $0.id == gameID }) else { return }
        games[index].playTime += duration
        games[index].lastPlayed = Date()
        saveLibrary()
    }

    public func toggleFavorite(gameID: UUID) {
        guard let index = games.firstIndex(where: { $0.id == gameID }) else { return }
        games[index].isFavorite.toggle()
        saveLibrary()
    }

    public func setRating(gameID: UUID, rating: Int) {
        guard let index = games.firstIndex(where: { $0.id == gameID }) else { return }
        games[index].rating = min(max(rating, 0), 5)
        saveLibrary()
    }

    public func setCategory(gameID: UUID, category: String) {
        guard let index = games.firstIndex(where: { $0.id == gameID }) else { return }
        games[index].category = category
        saveLibrary()
    }

    // MARK: - Drag & Drop

    public func addGame(from url: URL) {
        let path = url.path
        let ext = url.pathExtension.lowercased()

        switch ext {
        case "app":
            let name = url.deletingPathExtension().lastPathComponent
            let game = Game(name: name, platform: "macOS", installPath: path, runner: "Native")
            games.append(game)
            saveLibrary()

        case "exe":
            let name = url.deletingPathExtension().lastPathComponent
            let game = Game(name: name, platform: "Windows", installPath: path, runner: "Wine",
                            wineRenderMode: .auto, wineESync: true, wineShaderCache: true)
            games.append(game)
            saveLibrary()

        case "iso", "img", "gcm", "wbfs", "nkit", "chd", "rvz", "nsp", "xci", "nds", "3ds",
             "nes", "snes", "smc", "sfc", "n64", "z64", "v64", "gba", "gbc", "gb",
             "psx", "pbp", "cue", "bin", "mds":
            let name = url.deletingPathExtension().lastPathComponent
            let game = Game(name: name, platform: "Console", installPath: path, runner: "RetroArch")
            games.append(game)
            saveLibrary()

        default:
            break
        }
    }

    // MARK: - Per-Game Config Export / Import

    public func exportGameConfig(_ game: Game) -> URL? {
        let panel = NSSavePanel()
        panel.title = tr("Spielkonfiguration exportieren")
        panel.nameFieldStringValue = "\(game.name).lutrisgame.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            let data = try JSONEncoder().encode(game)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    public func importGameConfig() -> Game? {
        let panel = NSOpenPanel()
        panel.title = tr("Spielkonfiguration importieren")
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            let data = try Data(contentsOf: url)
            let game = try JSONDecoder().decode(Game.self, from: data)
            var imported = game
            imported.id = UUID()
            imported.playTime = 0
            imported.lastPlayed = nil
            games.append(imported)
            saveLibrary()
            return imported
        } catch {
            return nil
        }
    }

    // MARK: - Library Backup & Restore

    private var supportDir: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return folder.appendingPathComponent("LutrisForMac", isDirectory: true)
    }

    public func exportLibraryBackup() -> Bool {
        let panel = NSSavePanel()
        panel.title = tr("Bibliothek sichern")
        panel.nameFieldStringValue = "LutrisForMac-Backup.zip"
        panel.allowedContentTypes = [.archive]
        guard panel.runModal() == .OK, let url = panel.url else { return false }

        let fm = FileManager.default
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("lutrisbackup_\(UUID().uuidString)")
        try? fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        do {
            // games.json
            let gamesData = try JSONEncoder().encode(games)
            try gamesData.write(to: tmpDir.appendingPathComponent("games.json"))

            // media (covers, banners, icons)
            let mediaSrc = supportDir.appendingPathComponent("media")
            let mediaDst = tmpDir.appendingPathComponent("media")
            if fm.fileExists(atPath: mediaSrc.path) {
                try fm.copyItem(at: mediaSrc, to: mediaDst)
            }

            // wine configs
            for cfg in ["wine_versions.json", "wine_prefixes.json", "crossover_installations.json", "runners.json"] {
                let src = supportDir.appendingPathComponent(cfg)
                if fm.fileExists(atPath: src.path) {
                    try fm.copyItem(at: src, to: tmpDir.appendingPathComponent(cfg))
                }
            }

            // Pack as zip
            let zipTask = Process()
            zipTask.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            zipTask.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", tmpDir.path, url.path]
            try zipTask.run()
            zipTask.waitUntilExit()

            try? fm.removeItem(at: tmpDir)
            return zipTask.terminationStatus == 0
        } catch {
            try? fm.removeItem(at: tmpDir)
            return false
        }
    }

    public func importLibraryBackup() -> Bool {
        let panel = NSOpenPanel()
        panel.title = tr("Bibliothek wiederherstellen")
        panel.allowedContentTypes = [.archive, .zip, .application]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return false }

        let fm = FileManager.default
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("lutrisrestore_\(UUID().uuidString)")
        try? fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        defer { try? fm.removeItem(at: tmpDir) }

        do {
            // Extract zip
            let unzipTask = Process()
            unzipTask.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            unzipTask.arguments = ["-x", "-k", url.path, tmpDir.path]
            try unzipTask.run()
            unzipTask.waitUntilExit()
            guard unzipTask.terminationStatus == 0 else { return false }

            // Find the inner folder (ditto wraps in a folder)
            let contents = try fm.contentsOfDirectory(at: tmpDir, includingPropertiesForKeys: nil)
            let sourceDir = contents.first { $0.lastPathComponent.hasPrefix("lutrisbackup_") || $0.lastPathComponent == "LutrisForMac-Backup" }
                ?? contents.first { (try? fm.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil).contains { $0.lastPathComponent == "games.json" }) == true }
                ?? tmpDir

            // Restore games.json
            let gamesFile = sourceDir.appendingPathComponent("games.json")
            guard fm.fileExists(atPath: gamesFile.path) else { return false }
            let data = try Data(contentsOf: gamesFile)
            let imported = try JSONDecoder().decode([Game].self, from: data)
            games = imported
            saveLibrary()

            // Restore media
            let mediaSrc = sourceDir.appendingPathComponent("media")
            let mediaDst = supportDir.appendingPathComponent("media")
            if fm.fileExists(atPath: mediaSrc.path) {
                try? fm.removeItem(at: mediaDst)
                try fm.copyItem(at: mediaSrc, to: mediaDst)
            }

            // Restore configs
            for cfg in ["wine_versions.json", "wine_prefixes.json", "crossover_installations.json", "runners.json"] {
                let src = sourceDir.appendingPathComponent(cfg)
                let dst = supportDir.appendingPathComponent(cfg)
                if fm.fileExists(atPath: src.path) {
                    try? fm.removeItem(at: dst)
                    try fm.copyItem(at: src, to: dst)
                }
            }

            return true
        } catch {
            return false
        }
    }

    // MARK: - Steam Sync

    @Published public var isSteamSyncing = false
    @Published public var steamSyncProgress: String = ""
    @Published public var steamSyncError: String?
    @Published public var steamSyncResults: Int = 0

    public func syncSteamLibrary(apiKey: String, steamID: String) async {
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

    public func importFromCrossOverBottles() -> Int {
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

    public func runInstallScript(for game: Game) async {
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
