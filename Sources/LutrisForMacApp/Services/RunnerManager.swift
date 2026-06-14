import Foundation
import AppKit

@MainActor
final class RunnerManager: ObservableObject {
    static let shared = RunnerManager()

    @Published var runners: [Runner] = []
    @Published var customRunners: [Runner] = []
    @Published var gameRunnerConfigs: [UUID: [String: String]] = [:]

    private let configFile: URL

    private init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("LutrisForMac", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        configFile = folder.appendingPathComponent("runners.json")

        loadCustomRunners()
        detectAllRunners()
    }

    // MARK: - Runner-Definitionen

    private static let knownRunnerDefs: [Runner] = [
        Runner(
            name: "Wine",
            displayName: "Wine (Homebrew/System)",
            category: .wine,
            installType: "Homebrew / Gcenx-Builds",
            launchTemplate: .wine("/usr/local/bin/wine"),
            supportsPlatforms: ["Windows"]
        ),
        Runner(
            name: "CrossOver",
            displayName: "CrossOver",
            category: .wine,
            installType: "Commercial",
            launchTemplate: .wine("/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine"),
            supportsPlatforms: ["Windows"]
        ),

        // --- Emulatoren ---
        Runner(
            name: "DOSBox",
            displayName: "DOSBox",
            category: .retro,
            installType: "Homebrew / App",
            launchTemplate: .dosbox,
            supportsPlatforms: ["DOS"],
            configFields: [
                Runner.RunnerConfigField(id: "dosbox_conf", label: "Konfigurationsdatei", type: .filePicker, help: "Optional: DOSBox-Konfiguration (.conf)")
            ]
        ),
        Runner(
            name: "DOSBox-X",
            displayName: "DOSBox-X",
            category: .retro,
            installType: "Homebrew / App",
            launchTemplate: .dosbox,
            supportsPlatforms: ["DOS"]
        ),
        Runner(
            name: "ScummVM",
            displayName: "ScummVM",
            category: .retro,
            installType: "Homebrew / App",
            launchTemplate: .scummvm,
            supportsPlatforms: ["DOS", "Windows"],
            configFields: [
                Runner.RunnerConfigField(id: "scummvm_game_id", label: "ScummVM Game-ID", type: .text, defaultValue: "", help: "Spiele-ID aus ScummVM (z.B. monkey1)")
            ]
        ),
        // --- Nintendo ---
        Runner(
            name: "Dolphin",
            displayName: "Dolphin (GameCube/Wii)",
            category: .nintendo,
            installType: "Homebrew / App",
            launchTemplate: .nativeApp,
            supportsPlatforms: ["GameCube", "Wii"],
            configFields: [
                Runner.RunnerConfigField(id: "dolphin_user_dir", label: "Benutzer-Verzeichnis", type: .filePicker, help: "Optional: Pfad zum Dolphin-Benutzer-Ordner")
            ]
        ),
        Runner(
            name: "Ryujinx",
            displayName: "Ryujinx (Switch)",
            category: .nintendo,
            installType: "App",
            launchTemplate: .cli("{runnerPath} \"{gamePath}\""),
            supportsPlatforms: ["Switch"]
        ),
        Runner(
            name: "Astris",
            displayName: "Astris (Switch)",
            category: .nintendo,
            installType: "App (DMG)",
            launchTemplate: .nativeApp,
            supportsPlatforms: ["Switch"]
        ),
        Runner(
            name: "MelonDS",
            displayName: "melonDS (DS)",
            category: .nintendo,
            installType: "Homebrew / App",
            launchTemplate: .nativeApp,
            supportsPlatforms: ["Nintendo DS"]
        ),
        Runner(
            name: "Azahar",
            displayName: "Azahar (3DS)",
            category: .nintendo,
            installType: "App (ZIP)",
            launchTemplate: .nativeApp,
            supportsPlatforms: ["3DS"]
        ),

        // --- PlayStation ---
        Runner(
            name: "PCSX2",
            displayName: "PCSX2 (PS2)",
            category: .playstation,
            installType: "Homebrew / App",
            launchTemplate: .nativeApp,
            supportsPlatforms: ["PS2"]
        ),
        Runner(
            name: "RPCS3",
            displayName: "RPCS3 (PS3)",
            category: .playstation,
            installType: "App",
            launchTemplate: .nativeApp,
            supportsPlatforms: ["PS3"]
        ),
        Runner(
            name: "DuckStation",
            displayName: "DuckStation (PS1)",
            category: .playstation,
            installType: "Homebrew / App",
            launchTemplate: .nativeApp,
            supportsPlatforms: ["PS1"]
        ),

        // --- Sega ---
        Runner(
            name: "Flycast",
            displayName: "Flycast (Dreamcast/NAOMI)",
            category: .sega,
            installType: "Homebrew / App",
            launchTemplate: .nativeApp,
            supportsPlatforms: ["Dreamcast", "NAOMI"]
        ),

        // --- Handheld ---
        Runner(
            name: "PPSSPP",
            displayName: "PPSSPP (PSP)",
            category: .handheld,
            installType: "Homebrew / App",
            launchTemplate: .nativeApp,
            supportsPlatforms: ["PSP"]
        ),

        // --- RetroArch ---
        Runner(
            name: "RetroArch",
            displayName: "RetroArch (Multi-System)",
            category: .retro,
            installType: "Homebrew / App",
            launchTemplate: .retroarch(""),
            supportsPlatforms: ["Multi"],
            configFields: [
                Runner.RunnerConfigField(id: "retroarch_core", label: "Core", type: .text, defaultValue: "", help: "RetroArch-Core-Name (z.B. genesis_plus_gx_libretro)"),
                Runner.RunnerConfigField(id: "retroarch_config", label: "Konfigurationsdatei", type: .filePicker, help: "Optional: RetroArch-Konfiguration")
            ]
        ),

        // --- OpenEmu ---
        Runner(
            name: "OpenEmu",
            displayName: "OpenEmu (Multi-System)",
            category: .retro,
            installType: "App",
            launchTemplate: .nativeApp,
            supportsPlatforms: ["Multi"]
        ),

        // --- Mobile ---
        Runner(
            name: "PlayCover",
            displayName: "PlayCover (iOS/iPadOS)",
            category: .other,
            installType: "App (DMG)",
            launchTemplate: .nativeApp,
            supportsPlatforms: ["iOS", "iPadOS"]
        ),
    ]

    // MARK: - Erkennung

    func refresh() {
        detectAllRunners()
    }

    private func detectAllRunners() {
        var detected: [Runner] = []

        for def in Self.knownRunnerDefs {
            var runner = def
            let details = detectRunner(def)
            runner.installed = details.0
            runner.installPath = details.1
            runner.binaryPath = details.2
            detected.append(runner)
        }

        runners = detected + customRunners
    }

    private func detectRunner(_ runner: Runner) -> (Bool, String, String) {
        switch runner.name {
        case "Wine":
            return detectWine()
        case "CrossOver":
            return detectApp(path: "/Applications/CrossOver.app", binary: "Contents/SharedSupport/CrossOver/bin/wine")
        case "DOSBox":
            let (installed, path, _) = detectAppOrBrew(appName: "DOSBox", brewName: "dosbox")
            let bin = installed ? "\(path)/Contents/MacOS/DOSBox" : ""
            return (installed, path, bin)
        case "DOSBox-X":
            return detectAppOrBrew(appName: "DOSBox-X", brewName: "dosbox-x")
        case "ScummVM":
            return detectAppOrBrew(appName: "ScummVM", brewName: "scummvm")
        case "Dolphin":
            return detectAppOrBrew(appName: "Dolphin", brewName: "dolphin-emu")
        case "Ryujinx":
            return detectApp(path: "/Applications/Ryujinx.app", binary: "Contents/MacOS/Ryujinx")
        case "MelonDS":
            return detectApp(path: "/Applications/melonDS.app", binary: "Contents/MacOS/melonDS")
        case "PCSX2":
            return detectAppOrBrew(appName: "PCSX2", brewName: "pcsx2")
        case "RPCS3":
            return detectApp(path: "/Applications/rpcs3.app", binary: "Contents/MacOS/rpcs3")
        case "DuckStation":
            return detectAppOrBrew(appName: "DuckStation", brewName: "duckstation")
        case "Flycast":
            return detectApp(path: "/Applications/Flycast.app", binary: "Contents/MacOS/Flycast")
        case "PPSSPP":
            return detectAppOrBrew(appName: "PPSSPP", brewName: "ppsspp")
        case "RetroArch":
            return detectAppOrBrew(appName: "RetroArch", brewName: "retroarch")
        case "OpenEmu":
            return detectApp(path: "/Applications/OpenEmu.app", binary: "Contents/MacOS/OpenEmu")
        case "Astris":
            return detectApp(path: "/Applications/Astris.app", binary: "Contents/MacOS/Astris")
        case "Azahar":
            return detectApp(path: "\(NSHomeDirectory())/Programms/Azahar/azahar.app", binary: "Contents/MacOS/azahar")
        case "PlayCover":
            return detectApp(path: "/Applications/PlayCover.app", binary: "Contents/MacOS/PlayCover")
        default:
            return (false, "", "")
        }
    }

    private func detectWine() -> (Bool, String, String) {
        let checks = [
            "/opt/homebrew/bin/wine",
            "/usr/local/bin/wine",
            "/usr/bin/wine",
        ]
        for path in checks where FileManager.default.isExecutableFile(atPath: path) {
            return (true, URL(fileURLWithPath: path).deletingLastPathComponent().path, path)
        }
        return (false, "", "")
    }

    private func detectApp(path: String, binary: String) -> (Bool, String, String) {
        guard FileManager.default.fileExists(atPath: path) else { return (false, "", "") }
        let binPath = "\(path)/\(binary)"
        let exists = FileManager.default.isExecutableFile(atPath: binPath)
        return (exists, path, exists ? binPath : "")
    }

    private func detectAppOrBrew(appName: String, brewName: String) -> (Bool, String, String) {
        let appPath = "/Applications/\(appName).app"
        if FileManager.default.fileExists(atPath: appPath) {
            let bin = findBinaryInApp(appPath)
            return (true, appPath, bin)
        }

        let brewPaths = ["/opt/homebrew/bin/\(brewName)", "/usr/local/bin/\(brewName)"]
        for bp in brewPaths where FileManager.default.isExecutableFile(atPath: bp) {
            return (true, URL(fileURLWithPath: bp).deletingLastPathComponent().path, bp)
        }

        return (false, "", "")
    }

    private func findBinaryInApp(_ appPath: String) -> String {
        let bundle = Bundle(path: appPath)
        let exec = bundle?.executablePath
        if let exec, FileManager.default.isExecutableFile(atPath: exec) {
            return exec
        }
        let macosDir = "\(appPath)/Contents/MacOS"
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: macosDir) else { return "" }
        for item in contents where !item.hasPrefix(".") {
            let fullPath = "\(macosDir)/\(item)"
            if FileManager.default.isExecutableFile(atPath: fullPath) && !item.hasSuffix(".dylib") {
                return fullPath
            }
        }
        return ""
    }

    // MARK: - Custom Runners

    func addCustomRunner(name: String, binaryPath: String, category: Runner.RunnerCategory) {
        let runner = Runner(
            name: name,
            displayName: name,
            category: category,
            installType: "Benutzerdefiniert",
            launchTemplate: .custom,
            installed: FileManager.default.isExecutableFile(atPath: binaryPath),
            installPath: URL(fileURLWithPath: binaryPath).deletingLastPathComponent().path,
            binaryPath: binaryPath,
            supportsPlatforms: []
        )
        customRunners.append(runner)
        runners = runners.filter { $0.name != runner.name } + customRunners
        saveCustomRunners()
    }

    func removeCustomRunner(_ runner: Runner) {
        customRunners.removeAll { $0.id == runner.id }
        saveCustomRunners()
        detectAllRunners()
    }

    private func loadCustomRunners() {
        guard let data = try? Data(contentsOf: configFile),
              let loaded = try? JSONDecoder().decode([Runner].self, from: data) else { return }
        customRunners = loaded
    }

    private func saveCustomRunners() {
        guard let data = try? JSONEncoder().encode(customRunners) else { return }
        try? data.write(to: configFile, options: .atomic)
    }

    // MARK: - Launch

    /// Launch a game. Returns the PID of the launched process if available (for nativeApp only; CLI runners block until exit).
    @discardableResult
    func launchGame(installPath: String, runnerName: String, runnerConfig: [String: String] = [:], environment: [String: String] = [:]) async throws -> Int32? {
        guard let runner = runners.first(where: { $0.name == runnerName }) else {
            throw RunnerError.runnerNotFound(runnerName)
        }
        guard runner.installed else {
            throw RunnerError.runnerNotInstalled(runner.displayName)
        }

        switch runner.launchTemplate {
        case .nativeApp:
            let url = URL(fileURLWithPath: installPath)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw RunnerError.pathNotFound(installPath)
            }
            let runnerURL = URL(fileURLWithPath: runner.installPath)
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            if let app = try? await NSWorkspace.shared.openApplication(at: runnerURL, configuration: config) {
                return app.processIdentifier
            }
            NSWorkspace.shared.open(url)
            return nil

        case .cli(let template):
            let cmd = template
                .replacingOccurrences(of: "{gamePath}", with: installPath)
                .replacingOccurrences(of: "{runnerPath}", with: runner.binaryPath)
                .replacingOccurrences(of: "{runnerDir}", with: runner.installPath)
            _ = try await ProcessRunner.run(command: cmd, currentDirectory: nil, environment: environment)
            return nil

        case .wine(let binary):
            let wineBinary = FileManager.default.isExecutableFile(atPath: runner.binaryPath) ? runner.binaryPath : binary
            let env = environment.merging(["WINEDLLOVERRIDES": "winemenubuilder.exe=d"]) { _, new in new }
            let cmd = "\(wineBinary) \"\(installPath)\""
            _ = try await ProcessRunner.run(command: cmd, currentDirectory: nil, environment: env)
            return nil

        case .dosbox:
            let bin = runner.binaryPath.isEmpty ? "/Applications/DOSBox.app/Contents/MacOS/DOSBox" : runner.binaryPath
            let conf = runnerConfig["dosbox_conf"] ?? ""
            let cmd = conf.isEmpty ? "\"\(bin)\" \"\(installPath)\"" : "\"\(bin)\" -conf \"\(conf)\" \"\(installPath)\""
            _ = try await ProcessRunner.run(command: cmd, currentDirectory: nil, environment: environment)
            return nil

        case .scummvm:
            let bin = runner.binaryPath.isEmpty ? "/Applications/ScummVM.app/Contents/MacOS/scummvm" : runner.binaryPath
            let gameID = runnerConfig["scummvm_game_id"] ?? ""
            let cmd = gameID.isEmpty ? "\"\(bin)\" \"\(installPath)\"" : "\"\(bin)\" --path=\"\(installPath)\" \"\(gameID)\""
            _ = try await ProcessRunner.run(command: cmd, currentDirectory: nil, environment: environment)
            return nil

        case .retroarch:
            let bin = runner.binaryPath.isEmpty ? "/Applications/RetroArch.app/Contents/MacOS/RetroArch" : runner.binaryPath
            let core = runnerConfig["retroarch_core"] ?? ""
            var args = ""
            if core.isEmpty {
                args = "\"\(bin)\" --verbose \"\(installPath)\""
            } else {
                args = "\"\(bin)\" --verbose -L \"\(core)\" \"\(installPath)\""
            }
            let cmd = args
            _ = try await ProcessRunner.run(command: cmd, currentDirectory: nil, environment: environment)
            return nil

        case .custom:
            throw RunnerError.customRunnerNoCommand

        default:
            break
        }
        return nil
    }
}

enum RunnerError: LocalizedError {
    case runnerNotFound(String)
    case runnerNotInstalled(String)
    case pathNotFound(String)
    case customRunnerNoCommand

    var errorDescription: String? {
        switch self {
        case .runnerNotFound(let name): return "Runner nicht gefunden: \(name)"
        case .runnerNotInstalled(let name): return "\(name) ist nicht installiert. Installiere es über Homebrew oder lade es herunter."
        case .pathNotFound(let path): return "Pfad nicht gefunden: \(path)"
        case .customRunnerNoCommand: return "Kein Startbefehl für benutzerdefinierten Runner definiert."
        }
    }
}
