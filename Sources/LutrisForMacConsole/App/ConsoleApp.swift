import SwiftUI
import LutrisForMacCore

private let libraryURL = FileManager.default
    .urls(for: .applicationSupportDirectory, in: .userDomainMask)
    .first!
    .appendingPathComponent("LutrisForMac")
    .appendingPathComponent("games.json")

private func recordPlaySession(gameID: UUID, duration: TimeInterval) {
    guard duration > 10, let data = try? Data(contentsOf: libraryURL),
          var games = try? JSONDecoder().decode([Game].self, from: data),
          let idx = games.firstIndex(where: { $0.id == gameID })
    else { return }
    games[idx].playTime += duration
    games[idx].lastPlayed = Date()
    if let encoded = try? JSONEncoder().encode(games) {
        try? encoded.write(to: libraryURL, options: .atomic)
    }
}

@main
struct ConsoleApp: App {
    @StateObject private var lang = LanguageManager.shared

    var body: some Scene {
        WindowGroup {
            ConsoleMainView(onLaunch: { game in launchGame(game) })
                .id(lang.refreshID)
                .environment(\.locale, lang.locale)
                .onAppear {
                    if let w = NSApp.windows.first(where: { $0.isVisible }),
                       let screen = w.screen ?? NSScreen.main {
                        w.styleMask = [.borderless, .resizable]
                        w.setFrame(screen.frame, display: true)
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 1280, height: 800)
    }

    private func launchGame(_ game: Game) {
        guard !GameSessionManager.shared.isGameRunning(game.id) else { return }

        let isWineRunner = game.runner == "Wine" || game.runner == "CrossOver" || game.runner == "Whisky" || game.runner == "Kegworks"
        let isNative = game.runner == "Native" || game.platform == "macOS"
        let startTime = Date()
        let wineManager = WineManager.shared
        let runnerManager = RunnerManager.shared

        Task {
            do {
                // Button-Mapping aktivieren
                ControllerManager.shared.activateMapping(for: game.id)

                // --- Steam Emulator ---
                if game.installPath.hasPrefix("steam://"), game.steamEmulatorEnabled == true {
                    let sid = GameSessionManager.shared.startSession(
                        gameID: game.id, gameName: game.name, coverURL: game.coverURL,
                        names: [(game.installPath as NSString).lastPathComponent],
                        discordRPCEnabled: game.runtimeSettings.discordRPC
                    )
                    _ = try await launchViaSteamEmulator(game: game, startTime: startTime, sessionID: sid, wineManager: wineManager, runnerManager: runnerManager)
                    let duration = Date().timeIntervalSince(startTime)
                    if duration > 10 { recordPlaySession(gameID: game.id, duration: duration) }
                    return
                }

                // --- Wine / CrossOver ---
                if isWineRunner {
                    let exeName = (game.installPath as NSString).lastPathComponent
                    let sid = GameSessionManager.shared.startSession(
                        gameID: game.id, gameName: game.name, coverURL: game.coverURL,
                        names: exeName.contains(".") ? [exeName] : [],
                        discordRPCEnabled: game.runtimeSettings.discordRPC
                    )
                    _ = try await wineManager.launchGame(game: game)
                    if game.runner == "CrossOver", game.installPath.hasSuffix(".app") {
                        GameSessionManager.shared.monitorApp(named: exeName, sessionID: sid)
                    }
                    let duration = Date().timeIntervalSince(startTime)
                    if duration > 10 { recordPlaySession(gameID: game.id, duration: duration) }
                    return
                }

                // --- URL schemes ---
                if game.installPath.contains("://") {
                    if let url = URL(string: game.installPath) {
                        _ = GameSessionManager.shared.startSession(
                            gameID: game.id, gameName: game.name, coverURL: game.coverURL,
                            names: [url.host ?? url.scheme ?? ""],
                            discordRPCEnabled: game.runtimeSettings.discordRPC
                        )
                        NSWorkspace.shared.open(url)
                        let duration = Date().timeIntervalSince(startTime)
                        if duration > 10 { recordPlaySession(gameID: game.id, duration: duration) }
                        return
                    }
                }

                let env = ProcessRunner.parseEnvironmentVariables(from: game.environmentVariables)
                let config = game.runnerConfig

                // --- Native macOS .app ---
                if isNative || !runnerManager.runners.contains(where: { $0.name == game.runner }) {
                    let url = URL(fileURLWithPath: game.installPath)
                    guard FileManager.default.fileExists(atPath: url.path) else { return }
                    if url.pathExtension == "app" {
                        let sid = GameSessionManager.shared.startSession(
                            gameID: game.id, gameName: game.name, coverURL: game.coverURL,
                            discordRPCEnabled: game.runtimeSettings.discordRPC
                        )
                        let openConfig = NSWorkspace.OpenConfiguration()
                        openConfig.activates = true
                        openConfig.createsNewApplicationInstance = false
                        let runningApp = try await NSWorkspace.shared.openApplication(at: url, configuration: openConfig)
                        let pid = runningApp.processIdentifier
                        if pid > 0 {
                            GameSessionManager.shared.addPID(pid, sessionID: sid)
                        } else {
                            GameSessionManager.shared.addName(url.lastPathComponent, sessionID: sid)
                        }
                    } else {
                        _ = GameSessionManager.shared.startSession(
                            gameID: game.id, gameName: game.name, coverURL: game.coverURL,
                            names: [url.lastPathComponent],
                            discordRPCEnabled: game.runtimeSettings.discordRPC
                        )
                        NSWorkspace.shared.open(url)
                    }
                    let duration = Date().timeIntervalSince(startTime)
                    if duration > 10 { recordPlaySession(gameID: game.id, duration: duration) }
                    return
                }

                // --- Emulator / other runners ---
                let runnerInfo = runnerManager.runners.first(where: { $0.name == game.runner })
                let isCLIRunner = runnerInfo?.launchTemplate.isCLI ?? true
                let sid = GameSessionManager.shared.startSession(
                    gameID: game.id, gameName: game.name, coverURL: game.coverURL,
                    names: isCLIRunner ? [(game.installPath as NSString).lastPathComponent] : [],
                    discordRPCEnabled: game.runtimeSettings.discordRPC
                )
                let pid = try await runnerManager.launchGame(
                    installPath: game.installPath,
                    runnerName: game.runner,
                    runnerConfig: config,
                    environment: env,
                    captureOutput: game.runtimeSettings.processLogging
                )
                if let pid {
                    GameSessionManager.shared.addPID(pid, sessionID: sid)
                } else if isCLIRunner {
                    GameSessionManager.shared.endSession(sid)
                } else {
                    GameSessionManager.shared.addName((game.installPath as NSString).lastPathComponent, sessionID: sid)
                }
                let duration = Date().timeIntervalSince(startTime)
                if duration > 10 { recordPlaySession(gameID: game.id, duration: duration) }
            } catch {
                GameSessionManager.shared.endSession(for: game.id)
            }
        }
    }

    private func launchViaSteamEmulator(game: Game, startTime: Date, sessionID: UUID, wineManager: WineManager, runnerManager: RunnerManager) async throws -> String {
        guard let steamID = game.steamAppID, !steamID.isEmpty else {
            throw LaunchError.steamLaunchDisabled
        }

        let steamLibraries = [
            "\(NSHomeDirectory())/Library/Application Support/Steam/steamapps",
            "/Library/Application Support/Steam/steamapps",
        ]
        var installDir: String?
        for lib in steamLibraries {
            guard FileManager.default.fileExists(atPath: lib) else { continue }
            let manifestPath = "\(lib)/appmanifest_\(steamID).acf"
            guard let manifest = try? String(contentsOfFile: manifestPath, encoding: .utf8) else { continue }
            for line in manifest.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("\"installdir\"") {
                    let parts = trimmed.components(separatedBy: "\"")
                    if parts.count >= 4 { installDir = "\(lib)/common/\(parts[3])" }
                    break
                }
            }
            break
        }

        guard let dir = installDir else {
            throw LaunchError.steamLaunchDisabled
        }

        guard let exePath = findExe(directory: dir) else {
            throw LaunchError.steamLaunchDisabled
        }

        var modifiedGame = game
        modifiedGame.installPath = exePath
        modifiedGame.launchViaSteam = false

        let isWine = game.runner == "CrossOver" || game.runner == "Wine" || game.runner == "Whisky" || game.runner == "Kegworks"
        if isWine {
            let output = try await wineManager.launchGame(game: modifiedGame)
            GameSessionManager.shared.addName((exePath as NSString).lastPathComponent, sessionID: sessionID)
            return output
        } else {
            let pid = try await runnerManager.launchGame(
                installPath: exePath,
                runnerName: game.runner,
                runnerConfig: game.runnerConfig,
                environment: ProcessRunner.parseEnvironmentVariables(from: game.environmentVariables),
                captureOutput: game.runtimeSettings.processLogging
            )
            if let pid { GameSessionManager.shared.addPID(pid, sessionID: sessionID) }
            else { GameSessionManager.shared.addName((exePath as NSString).lastPathComponent, sessionID: sessionID) }
            return exePath
        }
    }

    private func findExe(directory: String) -> String? {
        guard let enumerator = FileManager.default.enumerator(atPath: directory) else { return nil }
        for case let file as String in enumerator {
            let ext = (file as NSString).pathExtension.lowercased()
            if ["exe", "app", "sh"].contains(ext) {
                return (directory as NSString).appendingPathComponent(file)
            }
        }
        return nil
    }
}

enum LaunchError: Error {
    case steamLaunchDisabled
}