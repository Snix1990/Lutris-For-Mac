import Foundation
import AppKit

@MainActor
final class InstallerEngine: ObservableObject {
    static let shared = InstallerEngine()

    @Published var isRunning = false
    @Published var currentTaskIndex: Int = 0
    @Published var currentTaskDescription: String = ""
    @Published var progress: Double = 0
    @Published var log: [String] = []
    @Published var variables: [String: String] = [:]
    @Published var pendingInput: InputRequest? = nil
    @Published var error: String? = nil

    private let wineManager = WineManager.shared
    private var script: InstallerScript?
    private var cancellled = false

    struct InputRequest: Identifiable {
        let id = UUID()
        let prompt: String
        let variable: String
        let defaultValue: String?
    }

    func cancel() {
        cancellled = true
    }

    func run(script: InstallerScript, gamePath: String, gameName: String) async -> Bool {
        self.script = script
        self.cancellled = false
        self.isRunning = true
        self.currentTaskIndex = 0
        self.progress = 0
        self.log = []
        self.error = nil
        defer {
            isRunning = false
            self.script = nil
        }

        let total = Double(script.tasks.count)

        // Basis-Variablen
        var vars: [String: String] = [
            "gameName": gameName,
            "gamePath": gamePath,
            "home": NSHomeDirectory(),
            "tmp": FileManager.default.temporaryDirectory.path,
            "desktop": "\(NSHomeDirectory())/Desktop",
            "applications": "/Applications",
            "supportDir": "\(NSHomeDirectory())/Library/Application Support/LutrisForMac",
        ]

        // Benutzerdefinierte Env-Vars aus Script
        for (key, value) in script.environmentVariables {
            vars[key] = resolveVariables(value, vars: vars)
        }

        for (key, value) in variables {
            vars[key] = value
        }

        variables = vars

        for (index, task) in script.tasks.enumerated() {
            guard !cancellled else {
                log.append("❌ Abgebrochen")
                return false
            }

            currentTaskIndex = index
            progress = Double(index) / total
            vars = variables

            do {
                try await executeTask(task, vars: &vars)
            } catch {
                let msg = "Fehler bei Schritt \(index + 1): \(error.localizedDescription)"
                log.append("❌ \(msg)")
                self.error = msg
                return false
            }
        }

        progress = 1.0
        log.append("✅ Installation abgeschlossen!")
        return true
    }

    private func executeTask(_ task: InstallerScript.InstallTask, vars: inout [String: String]) async throws {
        switch task {
        case .mkdir(let path, let desc):
            let resolved = resolveVariables(path, vars: vars)
            log.append("📁 \(desc ?? "Erstelle Verzeichnis"): \(resolved)")
            currentTaskDescription = desc ?? "Erstelle Verzeichnis"
            try FileManager.default.createDirectory(atPath: resolved, withIntermediateDirectories: true)

        case .download(let url, let dest, let desc):
            let resolvedURL = resolveVariables(url, vars: vars)
            let resolvedDest = resolveVariables(dest, vars: vars)
            log.append("⬇️ \(desc ?? "Lade herunter"): \(resolvedURL)")
            currentTaskDescription = desc ?? "Lade herunter..."

            let destURL = URL(fileURLWithPath: resolvedDest)
            try FileManager.default.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)

            let (data, _) = try await URLSession.shared.data(from: URL(string: resolvedURL)!)
            try data.write(to: destURL, options: .atomic)
            log.append("✅ Download abgeschlossen: \(resolvedDest)")

        case .extract(let archive, let dest, let type, let desc):
            let resolvedArchive = resolveVariables(archive, vars: vars)
            let resolvedDest = resolveVariables(dest, vars: vars)
            log.append("📦 \(desc ?? "Extrahiere"): \(resolvedArchive)")
            currentTaskDescription = desc ?? "Extrahiere..."
            try FileManager.default.createDirectory(atPath: resolvedDest, withIntermediateDirectories: true)

            let ext = type ?? detectArchiveType(resolvedArchive)
            try extractArchive(archive: resolvedArchive, dest: resolvedDest, type: ext)
            log.append("✅ Extraktion abgeschlossen")

        case .execute(let command, let desc):
            let resolved = resolveVariables(command, vars: vars)
            log.append("🖥️ \(desc ?? "Führe aus"): \(resolved)")
            currentTaskDescription = desc ?? "Führe Befehl aus..."
            let output = try await ProcessRunner.run(command: resolved, currentDirectory: nil, environment: [:])
            log.append(output)

        case .wineExecute(let executable, let args, let winePrefix, let desc):
            let resolvedExe = resolveVariables(executable, vars: vars)
            let resolvedArgs = args.map { resolveVariables($0, vars: vars) } ?? ""
            let prefixName = winePrefix.map { resolveVariables($0, vars: vars) }
            log.append("🍷 \(desc ?? "Wine: \(resolvedExe)")")
            currentTaskDescription = desc ?? "Führe Wine-Installer aus..."

            let wine: WineVersion? = {
                if let versionName = vars["useWineVersion"], !versionName.isEmpty {
                    return wineManager.installedVersions.first(where: { $0.name == versionName })
                }
                return wineManager.installedVersions.first
            }()
            guard let wine else { throw InstallerError.noWineVersion }

            var env = ProcessInfo.processInfo.environment
            env["WINEPREFIX"] = "\(vars["supportDir"] ?? "")/prefixes/\(prefixName ?? "default")"
            env["WINEARCH"] = "win64"
            env["WINEDLLOVERRIDES"] = "winemenubuilder.exe=d"

            let cmd = "\(wine.wineBinaryPath) \(resolvedArgs) \"\(resolvedExe)\""
            let output = try await ProcessRunner.run(command: cmd, currentDirectory: nil, environment: env)
            log.append(output)

        case .wineCfg(let desc):
            log.append("⚙️ \(desc ?? "Wine-Konfiguration")")
            currentTaskDescription = desc ?? "Wine-Konfiguration..."
            guard let prefix = wineManager.prefixes.last else {
                throw InstallerError.noWinePrefix
            }
            wineManager.runWinecfg(for: prefix)

        case .createPrefix(let name, let arch, let desc):
            let resolvedName = resolveVariables(name, vars: vars)
            log.append("🔧 \(desc ?? "Erstelle Wineprefix"): \(resolvedName)")
            currentTaskDescription = desc ?? "Erstelle Wineprefix..."
            let wineArch = arch == "win32" ? WinePrefix.WineArch.win32 : WinePrefix.WineArch.win64
            try await wineManager.createPrefix(name: resolvedName, architecture: wineArch)
            log.append("✅ Wineprefix erstellt: \(resolvedName)")

        case .setEnvironment(let key, let value, let desc):
            let resolvedValue = resolveVariables(value, vars: vars)
            log.append("🔑 \(desc ?? "Setze Variable"): \(key)=\(resolvedValue)")
            currentTaskDescription = desc ?? "Setze Umgebungsvariable"
            vars[key] = resolvedValue
            variables[key] = resolvedValue

        case .message(let text, let desc):
            let resolved = resolveVariables(text, vars: vars)
            log.append("💬 \(desc ?? "Info"): \(resolved)")
            currentTaskDescription = desc ?? resolved

        case .input(let prompt, let variable, let defaultVal, let desc):
            let resolvedPrompt = resolveVariables(prompt, vars: vars)
            log.append("❓ \(desc ?? "Eingabe"): \(resolvedPrompt)")
            currentTaskDescription = desc ?? "Warte auf Eingabe..."

            // Warte auf Benutzereingabe über das published pendingInput
            let request = InputRequest(prompt: resolvedPrompt, variable: variable, defaultValue: defaultVal)
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                self.pendingInput = request
                self.inputContinuation = continuation
            }

            if let value = variables[variable] {
                vars[variable] = value
                log.append("✅ Eingabe: \(variable)=\(value)")
            }
        }
    }

    // HACK: Continuation für Input-Requests
    private var inputContinuation: CheckedContinuation<Void, Never>?

    nonisolated func submitInput(value: String) {
        Task { @MainActor in
            if let variable = pendingInput?.variable {
                variables[variable] = value
                pendingInput = nil
                inputContinuation?.resume()
                inputContinuation = nil
            }
        }
    }

    // MARK: - Extrahierung

    private func extractArchive(archive: String, dest: String, type: InstallerScript.InstallTask.ExtractType) throws {
        let fm = FileManager.default
        switch type {
        case .zip:
            let task = Process()
            task.launchPath = "/usr/bin/unzip"
            task.arguments = ["-o", archive, "-d", dest]
            try task.run()
            task.waitUntilExit()

        case .tarGz:
            try runTar(archive: archive, dest: dest, options: "-xzf")

        case .tarBz2:
            try runTar(archive: archive, dest: dest, options: "-xjf")

        case .tarXz:
            try runTar(archive: archive, dest: dest, options: "-xJf")

        case .dmg:
            // DMG mounten und kopieren
            let mountPoint = "/Volumes/installer_dmg_\(UUID().uuidString.prefix(8))"
            let mountTask = Process()
            mountTask.launchPath = "/usr/bin/hdiutil"
            mountTask.arguments = ["attach", archive, "-mountpoint", mountPoint, "-nobrowse"]
            try mountTask.run()
            mountTask.waitUntilExit()

            defer {
                let detach = Process()
                detach.launchPath = "/usr/bin/hdiutil"
                detach.arguments = ["detach", mountPoint]
                try? detach.run()
                detach.waitUntilExit()
            }

            // Kopiere den Inhalt
            if let contents = try? fm.contentsOfDirectory(atPath: mountPoint) {
                for item in contents {
                    let src = "\(mountPoint)/\(item)"
                    let dst = "\(dest)/\(item)"
                    try? fm.removeItem(atPath: dst)
                    try fm.copyItem(atPath: src, toPath: dst)
                }
            }

        case .sevenZip:
            try runCommand("/usr/local/bin/7z", args: ["x", archive, "-o\(dest)", "-y"])

        case .rar:
            try runCommand("/usr/local/bin/unrar", args: ["x", archive, dest])
        }
    }

    private func runTar(archive: String, dest: String, options: String) throws {
        let task = Process()
        task.launchPath = "/usr/bin/tar"
        task.arguments = [options, archive, "-C", dest, "--strip-components=1"]
        try task.run()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            throw InstallerError.extractionFailed
        }
    }

    private func runCommand(_ path: String, args: [String]) throws {
        guard FileManager.default.isExecutableFile(atPath: path) else {
            throw InstallerError.toolNotFound(path)
        }
        let task = Process()
        task.launchPath = path
        task.arguments = args
        try task.run()
        task.waitUntilExit()
    }

    private func detectArchiveType(_ path: String) -> InstallerScript.InstallTask.ExtractType {
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()
        let lastPath = url.lastPathComponent.lowercased()

        if lastPath.hasSuffix(".tar.gz") || lastPath.hasSuffix(".tgz") { return .tarGz }
        if lastPath.hasSuffix(".tar.bz2") || lastPath.hasSuffix(".tbz") { return .tarBz2 }
        if lastPath.hasSuffix(".tar.xz") { return .tarXz }
        switch ext {
        case "zip": return .zip
        case "dmg": return .dmg
        case "7z": return .sevenZip
        case "rar": return .rar
        default: return .zip
        }
    }

    private func resolveVariables(_ text: String, vars: [String: String]) -> String {
        var result = text
        for (key, value) in vars {
            result = result.replacingOccurrences(of: "{\(key)}", with: value)
        }
        return result
    }

    private func runCommand(_ path: String, args: [String]) async throws {
        guard FileManager.default.isExecutableFile(atPath: path) else {
            throw InstallerError.toolNotFound(path)
        }
        let output = try await ProcessRunner.run(command: "\(path) \(args.joined(separator: " "))", currentDirectory: nil, environment: [:])
        log.append(output)
    }
}

enum InstallerError: LocalizedError {
    case noWineVersion
    case noWinePrefix
    case extractionFailed
    case toolNotFound(String)

    var errorDescription: String? {
        switch self {
        case .noWineVersion: return "Keine Wine-Version gefunden"
        case .noWinePrefix: return "Kein Wine-Prefix vorhanden"
        case .extractionFailed: return "Extraktion fehlgeschlagen"
        case .toolNotFound(let tool): return "Werkzeug nicht gefunden: \(tool). Installiere es via Homebrew."
        }
    }
}
