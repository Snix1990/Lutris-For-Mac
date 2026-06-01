import Foundation

struct ScannedGame: Identifiable {
    let id = UUID()
    let serviceName: String
    let gameID: String
    let name: String
    let installPath: String
    let runner: String
    let iconPath: String?
}

@MainActor
final class ServiceManager: ObservableObject {
    static let shared = ServiceManager()

    @Published var services: [GameService] = []
    @Published var scannedGames: [ScannedGame] = []
    @Published var isScanning = false

    private init() {
        detectServices()
    }

    func refresh() {
        detectServices()
    }

    // MARK: - Detection

    private func detectServices() {
        let defs: [(name: String, display: String, type: GameService.ServiceType, path: String, icon: String)] = [
            ("Steam", "Steam", .steam, "/Applications/Steam.app", "gamecontroller"),
            ("Heroic", "Heroic Games Launcher", .heroic, "/Applications/Heroic.app", "gamecontroller"),
            ("itch.io", "itch.io", .itchio, "/Applications/itch.app", "gift"),
            ("Battle.net", "Battle.net", .battlenet, "/Applications/Battle.net.app", "bolt"),
            ("Epic", "Epic Games", .epic, "/Applications/Epic Games Launcher.app", "star"),
            ("GOG Galaxy", "GOG Galaxy", .gog, "/Applications/GOG Galaxy.app", "star"),
            ("Ryujinx", "Ryujinx (Switch)", .ryujinx, "/Applications/Ryujinx.app", "gamecontroller"),
        ]

        services = defs.map { def in
            let installed = FileManager.default.fileExists(atPath: def.path)
            let gameCount = countImportedGames(for: def.name)
            return GameService(
                name: def.name,
                displayName: def.display,
                type: def.type,
                installed: installed,
                installPath: installed ? def.path : "",
                connected: gameCount > 0,
                gameCount: gameCount,
                iconSystemName: def.icon
            )
        }
    }

    private func countImportedGames(for serviceName: String) -> Int {
        guard let data = try? Data(contentsOf: importedGamesFile),
              let imported = try? JSONDecoder().decode([String: [String]].self, from: data) else {
            return 0
        }
        return imported[serviceName]?.count ?? 0
    }

    // MARK: - Scanning

    func scanAllServices() async {
        isScanning = true
        scannedGames = []
        defer { isScanning = false }

        let home = NSHomeDirectory()
        let lib = home + "/Library/Application Support"

        await withTaskGroup(of: [ScannedGame].self) { group in
            group.addTask { await self.scanSteam(lib: lib) }
            group.addTask { await self.scanHeroic(lib: lib) }
            group.addTask { await self.scanItchio(home: home) }
            group.addTask { await self.scanBattleNet(home: home) }
            group.addTask { await self.scanRyujinx(lib: lib) }

            for await games in group {
                scannedGames.append(contentsOf: games)
            }
        }

        // Services aktualisieren
        detectServices()
    }

    // MARK: - Steam

    private func scanSteam(lib: String) async -> [ScannedGame] {
        let steamAppsPath = "\(lib)/Steam/steamapps"
        guard FileManager.default.fileExists(atPath: steamAppsPath) else { return [] }

        var games: [ScannedGame] = []
        let fm = FileManager.default

        guard let contents = try? fm.contentsOfDirectory(atPath: steamAppsPath) else { return [] }

        for file in contents where file.hasPrefix("appmanifest_") && file.hasSuffix(".acf") {
            let path = "\(steamAppsPath)/\(file)"
            guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { continue }

            // ACF ist quasi key-value, einfaches Parsen
            let appID = extractACFValue(content, key: "appid") ?? ""
            let name = extractACFValue(content, key: "name") ?? "Unknown"
            let installDir = extractACFValue(content, key: "installdir") ?? ""

            // Steam-App-Pfad (für macOS - .app bundles)
            let appPath = "\(steamAppsPath)/common/\(installDir)"
            let macOSBinary = "\(appPath)/\(installDir).app"
            let actualPath = fm.fileExists(atPath: macOSBinary) ? macOSBinary : appPath

            games.append(ScannedGame(
                serviceName: "Steam",
                gameID: appID,
                name: name,
                installPath: actualPath,
                runner: "Native",
                iconPath: nil
            ))
        }
        return games
    }

    private func extractACFValue(_ text: String, key: String) -> String? {
        guard let range = text.range(of: "\"\(key)\"\\s*\"", options: .regularExpression) else { return nil }
        let val = text[range.upperBound...]
        guard let end = val.firstIndex(of: "\"") else { return nil }
        return String(val[..<end])
    }

    // MARK: - Heroic (Epic/GOG)

    private func scanHeroic(lib: String) async -> [ScannedGame] {
        let heroicPath = "\(lib)/heroic"
        guard FileManager.default.fileExists(atPath: heroicPath) else { return [] }

        var games: [ScannedGame] = []

        // Heroic store config (legendaryConfigPath)
        let legendaryPath = "\(heroicPath)/legendary_config"
        if let installed = try? JSONDecoder().decode([String: HeroicInstalled].self,
            from: Data(contentsOf: URL(fileURLWithPath: "\(legendaryPath)/installed.json"))) {
            for (id, entry) in installed {
                let basePath = entry.install_path ?? "\(heroicPath)/Games/\(entry.title ?? id)"
                games.append(ScannedGame(
                    serviceName: "Heroic",
                    gameID: id,
                    name: entry.title ?? id,
                    installPath: basePath,
                    runner: "Wine",
                    iconPath: nil
                ))
            }
        }

        // GOG installs from Heroic
        let gogPath = "\(heroicPath)/gog_store/installed.json"
        if let gogData = try? Data(contentsOf: URL(fileURLWithPath: gogPath)),
           let gogInstalled = try? JSONDecoder().decode([String: HeroicInstalled].self, from: gogData) {
            for (id, entry) in gogInstalled {
                games.append(ScannedGame(
                    serviceName: "GOG Galaxy",
                    gameID: id,
                    name: entry.title ?? id,
                    installPath: entry.install_path ?? "",
                    runner: "Wine",
                    iconPath: nil
                ))
            }
        }

        return games
    }

    private struct HeroicInstalled: Codable {
        let title: String?
        let install_path: String?
        let app_name: String?
    }

    // MARK: - itch.io

    private func scanItchio(home: String) async -> [ScannedGame] {
        let itchioPath = "\(home)/.config/itch"
        guard FileManager.default.fileExists(atPath: itchioPath) else { return [] }

        var games: [ScannedGame] = []

        // itch.io speichert installierte Spiele in db/cave.sqlite oder als JSON
        let cavesPath = "\(itchioPath)/db/caves.json"
        if let data = try? Data(contentsOf: URL(fileURLWithPath: cavesPath)),
           let caves = try? JSONDecoder().decode([ItchioCave].self, from: data) {
            for cave in caves {
                let basePath = cave.installLocation ?? "\(home)/Library/Application Support/itch/games/\(cave.game?.url ?? cave.id ?? "")"
                games.append(ScannedGame(
                    serviceName: "itch.io",
                    gameID: cave.id ?? "",
                    name: cave.game?.title ?? cave.id ?? "Unknown",
                    installPath: basePath,
                    runner: "Native",
                    iconPath: nil
                ))
            }
        }

        return games
    }

    private struct ItchioCave: Codable {
        let id: String?
        let game: ItchioGame?
        let installLocation: String?

        struct ItchioGame: Codable {
            let title: String?
            let url: String?
        }
    }

    // MARK: - Battle.net

    private func scanBattleNet(home: String) async -> [ScannedGame] {
        let battlenetPath = "\(home)/Library/Application Support/Battle.net"
        guard FileManager.default.fileExists(atPath: battlenetPath) else { return [] }

        var games: [ScannedGame] = []

        // Battle.net speichert Spiele in einer JSON-DB
        let dbPath = "\(battlenetPath)/Battle.net.config"
        if (try? Data(contentsOf: URL(fileURLWithPath: dbPath))) != nil {
            // Vereinfachte Erkennung über bekannte Blizzard-App-Pfade
            let blizzardApps = [
                "/Applications/World of Warcraft/_retail_/World of Warcraft.app",
                "/Applications/Overwatch.app",
                "/Applications/Diablo III.app",
                "/Applications/StarCraft II.app",
                "/Applications/Hearthstone.app",
                "/Applications/Heroes of the Storm.app",
                "/Applications/Call of Duty/Modern Warfare.app",
            ]
            for appPath in blizzardApps where FileManager.default.fileExists(atPath: appPath) {
                let name = URL(fileURLWithPath: appPath).deletingPathExtension().lastPathComponent
                games.append(ScannedGame(
                    serviceName: "Battle.net",
                    gameID: name,
                    name: name,
                    installPath: appPath,
                    runner: "Native",
                    iconPath: nil
                ))
            }
        }

        return games
    }

    // MARK: - Ryujinx

    private func scanRyujinx(lib: String) async -> [ScannedGame] {
        let ryujinxPath = "\(lib)/Ryujinx"
        guard FileManager.default.fileExists(atPath: ryujinxPath) else { return [] }

        let ryujinxApp = "/Applications/Ryujinx.app"
        guard FileManager.default.fileExists(atPath: ryujinxApp) else { return [] }

        var games: [ScannedGame] = []
        var gameDirs: [String] = []

        // Game-Verzeichnisse aus Ryujinx Config lesen
        let configPath = "\(ryujinxPath)/config.json"
        if let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
           let config = try? JSONDecoder().decode(RyujinxConfig.self, from: data) {
            gameDirs = config.gameDirs ?? config.gamesList ?? []
        }

        // Fallback: bekannte Standard-Pfade
        if gameDirs.isEmpty {
            let candidates = [
                "\(NSHomeDirectory())/Games/Switch",
                "\(NSHomeDirectory())/Documents/Ryujinx/games",
                "\(ryujinxPath)/games",
            ]
            gameDirs = candidates.filter { FileManager.default.fileExists(atPath: $0) }
        }

        // ROM-Dateien in den Verzeichnissen scannen
        let romExtensions = ["nsp", "xci", "nca"]
        for dir in gameDirs {
            let romFiles = collectROMs(at: dir, extensions: romExtensions)
            for fileURL in romFiles {
                let name = fileURL.deletingPathExtension().lastPathComponent
                let gameID = fileURL.lastPathComponent

                games.append(ScannedGame(
                    serviceName: "Ryujinx",
                    gameID: gameID,
                    name: name,
                    installPath: fileURL.path,
                    runner: "Ryujinx",
                    iconPath: nil
                ))
            }
        }

        return games
    }

    private struct RyujinxConfig: Codable {
        let gameDirs: [String]?
        let gamesList: [String]?

        enum CodingKeys: String, CodingKey {
            case gameDirs = "game_dirs"
            case gamesList = "GamesList"
        }
    }

    private func collectROMs(at directory: String, extensions: [String]) -> [URL] {
        var results: [URL] = []
        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: directory),
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return results }

        for case let fileURL as URL in enumerator {
            if extensions.contains(fileURL.pathExtension.lowercased()) {
                results.append(fileURL)
            }
        }
        return results
    }

    // MARK: - Import

    private let importedGamesFile: URL = {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("LutrisForMac", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("imported_games.json")
    }()

    private var importedTracker: [String: [String]] {
        get { ((try? JSONDecoder().decode([String: [String]].self, from: Data(contentsOf: importedGamesFile))) ??
               [:]) }
        set { if let data = try? JSONEncoder().encode(newValue) { try? data.write(to: importedGamesFile, options: .atomic) } }
    }

    func importGames(_ games: [ScannedGame], into library: inout [Game]) -> Int {
        var count = 0
        var tracker = importedTracker

        for scanned in games {
            let key = "\(scanned.serviceName)/\(scanned.gameID)"
            if tracker[scanned.serviceName]?.contains(key) ?? false { continue }

            let newGame = Game(
                name: scanned.name,
                platform: platformForService(scanned.serviceName),
                installPath: scanned.installPath,
                runner: scanned.runner,
                notes: "Importiert von \(scanned.serviceName) (ID: \(scanned.gameID))",
                serviceName: scanned.serviceName
            )

            if !library.contains(where: { $0.name == scanned.name && $0.installPath == scanned.installPath }) {
                library.append(newGame)
                count += 1
            }

            tracker[scanned.serviceName, default: []].append(key)
        }

        importedTracker = tracker
        detectServices()
        return count
    }

    private func platformForService(_ name: String) -> String {
        switch name {
        case "Steam": return "Steam"
        case "Heroic": return "Epic/GOG"
        case "itch.io": return "itch.io"
        case "Battle.net": return "Battle.net"
        case "GOG Galaxy": return "GOG"
        case "Ryujinx": return "Switch"
        default: return "Windows"
        }
    }
}
