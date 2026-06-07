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
                variables = vars
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

            guard let urlObj = URL(string: resolvedURL) else {
                throw InstallerError.networkError("Ungültige URL: \(resolvedURL)")
            }

            var request = URLRequest(url: urlObj)
            request.timeoutInterval = 60

            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                let body = String(data: data, encoding: .utf8) ?? "<no body>"
                throw InstallerError.networkError("HTTP \(http.statusCode): \(body)")
            }

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
            let output = try await runCommandDirectly(resolved)
            log.append(output)

        case .wineExecute(let executable, let args, let winePrefix, let winePath, let desc):
            let resolvedExe = resolveVariables(executable, vars: vars)
            let resolvedArgs = args.map { resolveVariables($0, vars: vars) } ?? ""
            let prefixRaw = winePrefix.map { resolveVariables($0, vars: vars) }
            let resolvedWinePath = winePath.flatMap({ resolveVariables($0, vars: vars) })
            log.append("🍷 \(desc ?? "Wine: \(resolvedExe)")")
            currentTaskDescription = desc ?? "Führe Wine-Installer aus..."

            // select wine binary path (prefer explicit winePath even if not registered in installedVersions)
            let wineBin: String
            if let wp = resolvedWinePath, !wp.isEmpty {
                wineBin = wp
            } else if let versionName = vars["useWineVersion"], !versionName.isEmpty, let found = wineManager.installedVersions.first(where: { $0.name == versionName }) {
                wineBin = found.wineBinaryPath
            } else if let found = wineManager.installedVersions.first {
                wineBin = found.wineBinaryPath
            } else {
                throw InstallerError.noWineVersion
            }
            vars["wineBin"] = wineBin

            var env = ProcessInfo.processInfo.environment
            // respect absolute prefix paths
            if let p = prefixRaw, p.hasPrefix("/") {
                env["WINEPREFIX"] = p
            } else {
                env["WINEPREFIX"] = "\(vars["supportDir"] ?? "")/prefixes/\(prefixRaw ?? "default")"
            }
            vars["winePrefixPath"] = env["WINEPREFIX"] ?? ""

            // Ensure the prefix directory exists before running wine
            if let wpPath = env["WINEPREFIX"] {
                do {
                    try FileManager.default.createDirectory(atPath: wpPath, withIntermediateDirectories: true)
                } catch {
                    throw InstallerError.prefixCreationFailed(wpPath)
                }
            }
            env["WINEARCH"] = "win64"
            env["WINEDLLOVERRIDES"] = "winemenubuilder.exe=d"

            // Ensure we run in the directory where the installer resides so Wine doesn't copy/move it
            let exeURL = URL(fileURLWithPath: resolvedExe)
            let execDir = exeURL.deletingLastPathComponent()

            // Direct Process call (no bash -lc) to avoid blocking the Wine GUI
            let output = try await runWineDirectly(
                wineBinary: wineBin,
                exe: resolvedExe,
                args: resolvedArgs,
                workingDir: execDir,
                environment: env
            )
            log.append(output)


        case .wineTricks(let verbs, let prefixPath, let winePath, let desc):
            currentTaskDescription = desc ?? "Winetricks..."
            log.append("🧩 \(desc ?? "Winetricks: \(verbs.joined(separator: ", "))")")
            // ensure winetricks binary available
            let manager = WinetricksManager.shared
            do {
                try await manager.downloadIfNeeded()
            } catch {
                throw error
            }

            let resolvedPrefix = prefixPath.map { resolveVariables($0, vars: vars) } ?? vars["supportDir"].map { "\($0)/prefixes/default" } ?? vars["supportDir"] ?? ""
            let resolvedWinePath = winePath.map { resolveVariables($0, vars: vars) }
            // run winetricks and forward output
            let stream = manager.run(verbs: verbs, prefix: resolvedPrefix, architecture: "win64", winePath: resolvedWinePath)
            for await line in stream {
                log.append(line)
            }

        case .wineCfg(let desc):
            log.append("⚙️ \(desc ?? "Wine-Konfiguration")")
            currentTaskDescription = desc ?? "Wine-Konfiguration..."
            guard let prefix = wineManager.prefixes.last else {
                throw InstallerError.noWinePrefix
            }
            wineManager.runWinecfg(for: prefix)
        case .createPrefix(let name, let arch, let prefixPath, let winePath, let desc):
            let resolvedName = name.map { resolveVariables($0, vars: vars) }
            let resolvedPrefixPath = prefixPath.map { resolveVariables($0, vars: vars) }
            let resolvedWinePath = winePath.map { resolveVariables($0, vars: vars) }
            currentTaskDescription = desc ?? "Erstelle Wineprefix..."

            if let explicitPath = resolvedPrefixPath {
                log.append("🔧 \(desc ?? "Erstelle Wineprefix"): \(explicitPath)")
                try? FileManager.default.removeItem(atPath: explicitPath)
                try FileManager.default.createDirectory(atPath: explicitPath, withIntermediateDirectories: true)

                // choose wine binary
                let wineBin: String = resolvedWinePath ?? (wineManager.installedVersions.first?.wineBinaryPath ?? "")
                guard !wineBin.isEmpty, FileManager.default.isExecutableFile(atPath: wineBin) else {
                    throw InstallerError.noWineVersion
                }
                vars["wineBin"] = wineBin
                vars["winePrefixPath"] = explicitPath

                var env = ProcessInfo.processInfo.environment
                env["WINEPREFIX"] = explicitPath
                env["WINEARCH"] = arch
                env["WINEDLLOVERRIDES"] = "winemenubuilder.exe=d"
                let wineBinDir = URL(fileURLWithPath: wineBin).deletingLastPathComponent().path
                let existingPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
                env["PATH"] = [wineBinDir, existingPath].joined(separator: ":")

                // run wineboot silently and capture output (don't log partial output)
                log.append("🔄 Initialisiere Prefix...")
                let task = Process()
                task.launchPath = wineBin
                task.arguments = ["wineboot", "-i"]
                task.environment = env
                let pipe = Pipe()
                task.standardOutput = pipe
                task.standardError = pipe
                try task.run()

                // wait with timeout silently
                let timeout: TimeInterval = 60
                let start = Date()
                while Date().timeIntervalSince(start) < timeout {
                    if task.isRunning {
                        // silently wait, don't read/log partial output
                        try await Task.sleep(nanoseconds: 200_000_000)
                        continue
                    } else {
                        break
                    }
                }

                task.waitUntilExit()
                // drain output but don't log it
                let _ = pipe.fileHandleForReading.readDataToEndOfFile()

                // verification: check for drive_c and registry files
                let driveC = explicitPath + "/drive_c"
                let systemReg = explicitPath + "/system.reg"
                let maxWait: TimeInterval = 30
                let verifyStart = Date()
                while Date().timeIntervalSince(verifyStart) < maxWait {
                    if FileManager.default.fileExists(atPath: driveC) && FileManager.default.fileExists(atPath: systemReg) {
                        // ensure sizes stable
                        let attrs1 = try? FileManager.default.attributesOfItem(atPath: systemReg)
                        let size1 = attrs1?[.size] as? UInt64 ?? 0
                        try await Task.sleep(nanoseconds: 300_000_000)
                        let attrs2 = try? FileManager.default.attributesOfItem(atPath: systemReg)
                        let size2 = attrs2?[.size] as? UInt64 ?? 0
                        if size1 == size2 { break }
                    }
                    try await Task.sleep(nanoseconds: 300_000_000)
                }

                // add to wineManager prefixes
                let prefix = WinePrefix(name: resolvedName ?? URL(fileURLWithPath: explicitPath).lastPathComponent, path: explicitPath, architecture: arch == "win32" ? .win32 : .win64, windowsVersion: "win10", created: Date())
                wineManager.prefixes.append(prefix)
                wineManager.savePrefixes()
                log.append("✅ Wineprefix erstellt: \(explicitPath)")
            } else {
                let resolvedNameNonNull = resolveVariables(resolvedName ?? "", vars: vars)
                log.append("🔧 \(desc ?? "Erstelle Wineprefix"): \(resolvedNameNonNull)")
                currentTaskDescription = desc ?? "Erstelle Wineprefix..."
                let wineArch = arch == "win32" ? WinePrefix.WineArch.win32 : WinePrefix.WineArch.win64
                // Ensure support/prefixes dir exists before creating prefix
                if let support = vars["supportDir"] {
                    let prefixesPath = "\(support)/prefixes"
                    try? FileManager.default.createDirectory(atPath: prefixesPath, withIntermediateDirectories: true)
                }
                try await wineManager.createPrefix(name: resolvedNameNonNull, architecture: wineArch)
                log.append("✅ Wineprefix erstellt: \(resolvedNameNonNull)")
            }

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

    private func shellQuote(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private func runWineDirectly(
        wineBinary: String,
        exe: String,
        args: String,
        workingDir: URL,
        environment: [String: String]
    ) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let launchTask = Process()
            launchTask.executableURL = URL(fileURLWithPath: wineBinary)
            let wineArgs = args.isEmpty ? [] : args.components(separatedBy: .whitespaces)
            launchTask.arguments = wineArgs + [exe]
            launchTask.currentDirectoryURL = workingDir
            launchTask.environment = environment
            launchTask.standardOutput = FileHandle.nullDevice
            launchTask.standardError = FileHandle.nullDevice
            
            DispatchQueue.global().async {
                do {
                    try launchTask.run()
                    launchTask.waitUntilExit()
                    continuation.resume(returning: "")
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func runCommandDirectly(_ command: String) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let parts = parseCommand(command)
            guard !parts.isEmpty else {
                continuation.resume(returning: "")
                return
            }
            
            let executable = parts[0]
            let args = parts.count > 1 ? Array(parts[1...]) : []
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = args
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            DispatchQueue.global().async {
                do {
                    try process.run()
                    process.waitUntilExit()
                    
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    continuation.resume(returning: output)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func parseCommand(_ command: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var inQuotes = false
        var i = command.startIndex
        
        while i < command.endIndex {
            let char = command[i]
            
            if char == "\"" {
                inQuotes.toggle()
                i = command.index(after: i)
            } else if char == " " && !inQuotes {
                if !current.isEmpty {
                    parts.append(current)
                    current = ""
                }
                i = command.index(after: i)
            } else {
                current.append(char)
                i = command.index(after: i)
            }
        }
        
        if !current.isEmpty {
            parts.append(current)
        }
        
        return parts
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
    case prefixCreationFailed(String)
    case networkError(String)
    case toolNotFound(String)

    var errorDescription: String? {
        switch self {
        case .noWineVersion: return "Keine Wine-Version gefunden"
        case .noWinePrefix: return "Kein Wine-Prefix vorhanden"
        case .extractionFailed: return "Extraktion fehlgeschlagen"
        case .prefixCreationFailed(let path): return "Prefix-Verzeichnis konnte nicht erstellt werden: \(path)"
        case .networkError(let msg): return "Netzwerkfehler: \(msg)"
        case .toolNotFound(let tool): return "Werkzeug nicht gefunden: \(tool). Installiere es via Homebrew."
        }
    }
}
