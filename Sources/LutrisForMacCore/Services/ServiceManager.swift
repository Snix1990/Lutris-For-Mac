import Foundation

public struct ScannedGame: Identifiable {
    public let id = UUID()
    public let serviceName: String
    public let gameID: String
    public let name: String
    public let installPath: String
    public let runner: String
    public let iconPath: String?
}

@MainActor
public final class ServiceManager: ObservableObject {
    public static let shared = ServiceManager()

    @Published public var services: [GameService] = []
    @Published public var scannedGames: [ScannedGame] = []
    @Published public var isScanning = false

    private init() {
        detectServices()
    }

    public func refresh() {
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
            ("Amazon Games", "Amazon Games", .amazon, "/Applications/Amazon Games.app", "cart"),
            ("Ubisoft", "Ubisoft Connect", .ubisoft, "/Applications/Ubisoft Connect.app", "person.2"),
            ("Humble Bundle", "Humble Bundle", .humble, "/Applications/Humble Bundle.app", "gift"),
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
        importedTracker[serviceName]?.count ?? 0
    }

    // MARK: - Scanning

    public func scanAllServices() async {
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
            group.addTask { await self.scanAmazon(lib: lib) }
            group.addTask { await self.scanUbisoft(lib: lib) }
            group.addTask { await self.scanHumble(lib: lib) }

            for await games in group {
                scannedGames.append(contentsOf: games)
            }
        }

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

            let appID = extractACFValue(content, key: "appid") ?? ""
            let name = extractACFValue(content, key: "name") ?? "Unknown"
            let installDir = extractACFValue(content, key: "installdir") ?? ""

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

        let dbPath = "\(battlenetPath)/Battle.net.config"
        if (try? Data(contentsOf: URL(fileURLWithPath: dbPath))) != nil {
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

        let configPath = "\(ryujinxPath)/config.json"
        if let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
           let config = try? JSONDecoder().decode(RyujinxConfig.self, from: data) {
            gameDirs = config.gameDirs ?? config.gamesList ?? []
        }

        if gameDirs.isEmpty {
            let candidates = [
                "\(NSHomeDirectory())/Games/Switch",
                "\(NSHomeDirectory())/Documents/Ryujinx/games",
                "\(ryujinxPath)/games",
            ]
            gameDirs = candidates.filter { FileManager.default.fileExists(atPath: $0) }
        }

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

    // MARK: - Amazon Games

    private func scanAmazon(lib: String) async -> [ScannedGame] {
        let amazonPath = "\(lib)/Amazon Games"
        guard FileManager.default.fileExists(atPath: amazonPath) else { return [] }

        var games: [ScannedGame] = []

        let gamesDataPath = "\(amazonPath)/Data/Games"
        if let gameDirs = try? FileManager.default.contentsOfDirectory(atPath: gamesDataPath) {
            for dir in gameDirs {
                let detailPath = "\(gamesDataPath)/\(dir)/gameDetail.json"
                guard let data = try? Data(contentsOf: URL(fileURLWithPath: detailPath)),
                      let detail = try? JSONDecoder().decode(AmazonGameDetail.self, from: data)
                else { continue }

                games.append(ScannedGame(
                    serviceName: "Amazon Games",
                    gameID: detail.id ?? dir,
                    name: detail.title ?? dir,
                    installPath: detail.installPath ?? "\(amazonPath)/Games/\(detail.title ?? dir)",
                    runner: "Native",
                    iconPath: nil
                ))
            }
        }

        return games
    }

    private struct AmazonGameDetail: Codable {
        let id: String?
        let title: String?
        let installPath: String?

        enum CodingKeys: String, CodingKey {
            case id = "Id"
            case title = "Title"
            case installPath = "InstallPath"
        }
    }

    // MARK: - Ubisoft Connect

    private func scanUbisoft(lib: String) async -> [ScannedGame] {
        let ubisoftPath = "\(lib)/Ubisoft Game Launcher"
        guard FileManager.default.fileExists(atPath: ubisoftPath) else { return [] }

        var games: [ScannedGame] = []

        let installsPath = "\(ubisoftPath)/installs.json"
        if let data = try? Data(contentsOf: URL(fileURLWithPath: installsPath)),
           let installs = try? JSONDecoder().decode([String: UbisoftInstall].self, from: data) {
            for (id, entry) in installs {
                games.append(ScannedGame(
                    serviceName: "Ubisoft",
                    gameID: id,
                    name: entry.name ?? entry.title ?? id,
                    installPath: entry.installPath ?? "\(NSHomeDirectory())/Games/Ubisoft Game Launcher/\(entry.name ?? id)",
                    runner: "Native",
                    iconPath: nil
                ))
            }
        }

        if games.isEmpty {
            let gamesPath = "\(NSHomeDirectory())/Games/Ubisoft Game Launcher"
            if let gameDirs = try? FileManager.default.contentsOfDirectory(atPath: gamesPath) {
                for dir in gameDirs where dir.hasSuffix(".app") {
                    let name = (dir as NSString).deletingPathExtension
                    games.append(ScannedGame(
                        serviceName: "Ubisoft",
                        gameID: name,
                        name: name,
                        installPath: "\(gamesPath)/\(dir)",
                        runner: "Native",
                        iconPath: nil
                    ))
                }
            }
        }

        return games
    }

    private struct UbisoftInstall: Codable {
        let name: String?
        let title: String?
        let installPath: String?

        enum CodingKeys: String, CodingKey {
            case name
            case title
            case installPath = "install_path"
        }
    }

    // MARK: - Humble Bundle

    private func scanHumble(lib: String) async -> [ScannedGame] {
        let humblePath = "\(lib)/Humble Bundle"
        guard FileManager.default.fileExists(atPath: humblePath) else { return [] }

        var games: [ScannedGame] = []

        let libraryFiles = ["library.json", "game_config.json", "library/library.json"]
        for file in libraryFiles {
            let path = "\(humblePath)/\(file)"
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let library = try? JSONDecoder().decode([HumbleGame].self, from: data)
            else { continue }

            for entry in library {
                games.append(ScannedGame(
                    serviceName: "Humble Bundle",
                    gameID: entry.id ?? entry.machineName ?? entry.title ?? UUID().uuidString,
                    name: entry.title ?? entry.machineName ?? "Unknown",
                    installPath: entry.installPath ?? entry.downloadPath ?? "",
                    runner: entry.platform ?? "Native",
                    iconPath: nil
                ))
            }
            break
        }

        if games.isEmpty {
            let gamesPath = "\(lib)/Humble Bundle/Games"
            if let gameDirs = try? FileManager.default.contentsOfDirectory(atPath: gamesPath) {
                for dir in gameDirs where dir.hasSuffix(".app") {
                    let name = (dir as NSString).deletingPathExtension
                    games.append(ScannedGame(
                        serviceName: "Humble Bundle",
                        gameID: name,
                        name: name,
                        installPath: "\(gamesPath)/\(dir)",
                        runner: "Native",
                        iconPath: nil
                    ))
                }
            }
        }

        return games
    }

    private struct HumbleGame: Codable {
        let id: String?
        let title: String?
        let machineName: String?
        let installPath: String?
        let downloadPath: String?
        let platform: String?

        enum CodingKeys: String, CodingKey {
            case id
            case title
            case machineName = "machine_name"
            case installPath = "install_path"
            case downloadPath = "download_path"
            case platform
        }
    }

    // MARK: - Import

    private let importedGamesFile: URL = {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("LutrisForMac", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("imported_games.json")
    }()

    private var _importedTracker: [String: [String]]?
    private var importedTracker: [String: [String]] {
        get {
            if let cached = _importedTracker { return cached }
            let loaded = (try? JSONDecoder().decode([String: [String]].self,
                from: Data(contentsOf: importedGamesFile))) ?? [:]
            _importedTracker = loaded
            return loaded
        }
        set {
            _importedTracker = newValue
            if let data = try? JSONEncoder().encode(newValue) {
                try? data.write(to: importedGamesFile, options: .atomic)
            }
        }
    }

    public func importGames(_ games: [ScannedGame], into library: inout [Game]) -> Int {
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
        case "Amazon Games": return "Amazon Games"
        case "Ubisoft": return "Ubisoft"
        case "Humble Bundle": return "Humble Bundle"
        default: return "Windows"
        }
    }
}
