import Foundation
import AppKit

@MainActor
final class WinetricksManager: ObservableObject {
    static let shared = WinetricksManager()

    static let scriptURL = URL(string: "https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks")!

    @Published var isInstalled = false
    @Published var binaryPath: String?
    @Published var verbs: [WinetricksVerb] = []
    @Published var isLoadingVerbs = false
    @Published var isRunning = false
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0
    @Published var output: String = ""

    private let supportDir: URL
    private var bundledPath: String {
        supportDir.appendingPathComponent("winetricks").path
    }

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        supportDir = appSupport.appendingPathComponent("LutrisForMac", isDirectory: true)
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        detect()
    }

    func detect() {
        // 1. Gebundeltes Script (App Support)
        if FileManager.default.isExecutableFile(atPath: bundledPath) {
            binaryPath = bundledPath
            isInstalled = true
            return
        }

        // 2. Homebrew / System
        let candidates = [
            "/opt/homebrew/bin/winetricks",
            "/usr/local/bin/winetricks",
            "\(NSHomeDirectory())/.homebrew/bin/winetricks",
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                binaryPath = path
                isInstalled = true
                return
            }
        }

        // 3. which
        let task = Process()
        task.launchPath = "/usr/bin/which"
        task.arguments = ["winetricks"]
        let pipe = Pipe()
        task.standardOutput = pipe
        try? task.run()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) {
            binaryPath = path
            isInstalled = true
        }
    }

    enum DownloadError: Error, LocalizedError {
        case downloadFailed(String)
        case makeExecutableFailed(String)

        var errorDescription: String? {
            switch self {
            case .downloadFailed(let msg): return "Winetricks-Download fehlgeschlagen: \(msg)"
            case .makeExecutableFailed(let path): return "Konnte Winetricks nicht ausführbar machen: \(path)"
            }
        }
    }

    func downloadIfNeeded() async throws {
        if isInstalled { return }
        isDownloading = true
        downloadProgress = 0
        defer { isDownloading = false }

        let session = URLSession.shared
        let (data, _) = try await session.data(from: Self.scriptURL)
        let tmpPath = FileManager.default.temporaryDirectory.appendingPathComponent("winetricks")
        try data.write(to: tmpPath, options: .atomic)

        try? FileManager.default.removeItem(atPath: bundledPath)
        try FileManager.default.moveItem(atPath: tmpPath.path, toPath: bundledPath)

        let attr = [FileAttributeKey.posixPermissions: 0o755]
        try FileManager.default.setAttributes(attr, ofItemAtPath: bundledPath)

        guard FileManager.default.isExecutableFile(atPath: bundledPath) else {
            throw DownloadError.makeExecutableFailed(bundledPath)
        }

        binaryPath = bundledPath
        isInstalled = true
    }

    func refreshVerbs() async {
        guard let binary = binaryPath else { return }
        isLoadingVerbs = true
        defer { isLoadingVerbs = false }

        let task = Process()
        task.launchPath = binary
        task.arguments = ["list-all"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return }

        var parsed: [WinetricksVerb] = []
        var currentCategory = ""

        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("=====") {
                currentCategory = trimmed.replacingOccurrences(of: "=", with: "").trimmingCharacters(in: .whitespaces)
            } else if !trimmed.isEmpty, !trimmed.hasPrefix("#") {
                let parts = trimmed.split(separator: " ", maxSplits: 1).map(String.init)
                if parts.count >= 1 {
                    let name = parts[0]
                    let desc = parts.count > 1 ? parts[1] : ""
                    parsed.append(WinetricksVerb(name: name, description: desc, category: currentCategory))
                }
            }
        }
        verbs = parsed
    }

    func run(verbs: [String], prefix: String, architecture: String, winePath: String? = nil) -> AsyncStream<String> {
        AsyncStream { continuation in
            Task {
                guard let binary = binaryPath else {
                    continuation.yield("Winetricks nicht gefunden.\n")
                    continuation.finish()
                    return
                }

                isRunning = true
                output = ""
                defer { isRunning = false }

                let task = Process()
                task.launchPath = binary
                task.arguments = ["--unattended"] + verbs
                var env = ProcessInfo.processInfo.environment
                env["WINEPREFIX"] = prefix
                env["WINEARCH"] = architecture
                if let winePath {
                    env["WINE"] = winePath
                    let wineDir = URL(fileURLWithPath: winePath).deletingLastPathComponent().path
                    let existingPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
                    env["PATH"] = [wineDir, "/opt/homebrew/bin", "/usr/local/bin", "\(NSHomeDirectory())/.homebrew/bin", existingPath].joined(separator: ":")
                } else {
                    let brewPaths = ["/opt/homebrew/bin", "/usr/local/bin", "\(NSHomeDirectory())/.homebrew/bin"]
                    let existingPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
                    env["PATH"] = brewPaths.joined(separator: ":") + ":" + existingPath
                }
                task.environment = env

                let pipe = Pipe()
                task.standardOutput = pipe
                task.standardError = pipe

                do {
                    try task.run()

                    let handle = pipe.fileHandleForReading
                    handle.readabilityHandler = { handler in
                        let data = handler.availableData
                        guard !data.isEmpty else { return }
                        if let text = String(data: data, encoding: .utf8) {
                            Task { @MainActor in
                                self.output += text
                            }
                            continuation.yield(text)
                        }
                    }

                    task.waitUntilExit()
                    handle.readabilityHandler = nil
                    let remaining = handle.readDataToEndOfFile()
                    if let text = String(data: remaining, encoding: .utf8), !text.isEmpty {
                        Task { @MainActor in
                            self.output += text
                        }
                        continuation.yield(text)
                    }
                } catch {
                    let msg = "Fehler: \(error.localizedDescription)\n"
                    Task { @MainActor in
                        self.output += msg
                    }
                    continuation.yield(msg)
                }

                continuation.finish()
            }
        }
    }
}

struct WinetricksVerb: Identifiable {
    var id: String { name }
    let name: String
    let description: String
    let category: String
}
