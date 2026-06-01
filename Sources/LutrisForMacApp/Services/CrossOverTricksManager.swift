import Foundation

@MainActor
final class CrossOverTricksManager: ObservableObject {
    static let shared = CrossOverTricksManager()

    static let scriptURL = URL(string: "https://media.codeweavers.com/pub/crossover/crossvertricks/crossovertricks")!

    @Published var isInstalled = false
    @Published var binaryPath: String?
    @Published var isRunning = false
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0
    @Published var output: String = ""
    @Published var installedComponents: Set<String> = []

    private let supportDir: URL
    private var bundledPath: String {
        supportDir.appendingPathComponent("crossovertricks").path
    }

    private let wineManager = WineManager.shared

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        supportDir = appSupport.appendingPathComponent("LutrisForMac", isDirectory: true)
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        detect()
    }

    func detect() {
        // 1. Gebündeltes Script (App Support)
        if FileManager.default.isExecutableFile(atPath: bundledPath) {
            binaryPath = bundledPath
            isInstalled = true
            return
        }

        // 2. CrossOver.app Bundle (alle bekannten Pfade)
        let crossoverPaths = wineManager.crossOverInstallations
            .filter { $0.isInstalled }
            .flatMap { co -> [String] in
                let base = co.path
                return [
                    "\(base)/Contents/SharedSupport/CrossOver/bin/crossovertricks",
                    "\(base)/Contents/SharedSupport/crossovertricks",
                    "\(base)/Contents/Resources/crossovertricks",
                    "\(base)/Contents/Resources/bin/crossovertricks",
                ]
            }
        for path in crossoverPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                binaryPath = path
                isInstalled = true
                return
            }
        }

        // 3. CrossOver.app – nicht-executable Version kopieren
        for path in crossoverPaths where FileManager.default.fileExists(atPath: path) {
            try? FileManager.default.removeItem(atPath: bundledPath)
            try? FileManager.default.copyItem(atPath: path, toPath: bundledPath)
            let attr = [FileAttributeKey.posixPermissions: 0o755]
            try? FileManager.default.setAttributes(attr, ofItemAtPath: bundledPath)
            if FileManager.default.isExecutableFile(atPath: bundledPath) {
                binaryPath = bundledPath
                isInstalled = true
                return
            }
        }

        // 4. `which crossovertricks`
        let task = Process()
        task.launchPath = "/usr/bin/which"
        task.arguments = ["crossovertricks"]
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
        case crossOverNotInstalled

        var errorDescription: String? {
            switch self {
            case .downloadFailed(let msg): return "crossovertricks-Download fehlgeschlagen: \(msg)"
            case .makeExecutableFailed(let path): return "Konnte crossovertricks nicht ausführbar machen: \(path)"
            case .crossOverNotInstalled: return "CrossOver ist nicht installiert. crossovertricks benötigt CrossOver."
            }
        }
    }

    /// Lädt crossovertricks herunter (oder kopiert aus CrossOver.app).
    /// Wirft crossOverNotInstalled wenn weder CrossOver noch das Script verfügbar sind.
    func downloadIfNeeded() async throws {
        if isInstalled { return }

        // Prüfen ob CrossOver.app existiert
        let hasCrossOver = wineManager.crossOverInstallations.contains(where: { $0.isInstalled })

        isDownloading = true
        downloadProgress = 0
        defer { isDownloading = false }

        if hasCrossOver {
            // Versuche aus CrossOver.app zu kopieren
            let crossoverPaths = wineManager.crossOverInstallations
                .filter { $0.isInstalled }
                .flatMap { co -> [String] in
                    let base = co.path
                    return [
                        "\(base)/Contents/SharedSupport/CrossOver/bin/crossovertricks",
                        "\(base)/Contents/SharedSupport/crossovertricks",
                        "\(base)/Contents/Resources/crossovertricks",
                        "\(base)/Contents/Resources/bin/crossovertricks",
                    ]
                }
            for path in crossoverPaths where FileManager.default.fileExists(atPath: path) {
                try? FileManager.default.removeItem(atPath: bundledPath)
                try FileManager.default.copyItem(atPath: path, toPath: bundledPath)
                let attr = [FileAttributeKey.posixPermissions: 0o755]
                try FileManager.default.setAttributes(attr, ofItemAtPath: bundledPath)

                guard FileManager.default.isExecutableFile(atPath: bundledPath) else {
                    throw DownloadError.makeExecutableFailed(bundledPath)
                }
                binaryPath = bundledPath
                isInstalled = true
                return
            }
        }

        // Weder CrossOver noch crossovertricks vorhanden – Download
        let session = URLSession.shared
        let (data, response) = try await session.data(from: Self.scriptURL)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw DownloadError.downloadFailed("HTTP \(response.debugDescription)")
        }

        let tmpPath = FileManager.default.temporaryDirectory.appendingPathComponent("crossovertricks")
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

    /// Bekannte CrossOver-Komponenten
    static let knownComponents: [(id: String, name: String, description: String)] = [
        ("dxvk", "DXVK", "DirectX 9/10/11 → Vulkan (Grafikverbesserung)"),
        ("vcrun2019", "VC++ 2019", "Visual C++ 2019 Redistributable"),
        ("vcrun2015", "VC++ 2015", "Visual C++ 2015 Redistributable"),
        ("vcrun2013", "VC++ 2013", "Visual C++ 2013 Redistributable"),
        ("vcrun2012", "VC++ 2012", "Visual C++ 2012 Redistributable"),
        ("vcrun2010", "VC++ 2010", "Visual C++ 2010 Redistributable"),
        ("vcrun2008", "VC++ 2008", "Visual C++ 2008 Redistributable"),
        ("vcrun2005", "VC++ 2005", "Visual C++ 2005 Redistributable"),
        ("dotnet48", ".NET 4.8", ".NET Framework 4.8"),
        ("dotnet472", ".NET 4.7.2", ".NET Framework 4.7.2"),
        ("directx9", "DirectX 9", "DirectX 9 End-User Runtime"),
        ("d3dx9", "D3DX9", "Direct3D 9 Extension"),
        ("d3dx11_43", "D3DX11_43", "Direct3D 11 Extension"),
        ("xact", "XACT", "Cross-Platform Audio Creation Tool"),
        ("xinput", "XInput", "Xbox 360 Controller Support"),
        ("corefonts", "Core Fonts", "Arial, Times New Roman etc."),
        ("tahoma", "Tahoma", "Tahoma Schriftart"),
        ("fontsmooth-rgb", "Font Smoothing", "Schriftglättung (RGB)"),
        ("msxml3", "MS XML 3", "Microsoft XML Core Services 3"),
        ("msxml4", "MS XML 4", "Microsoft XML Core Services 4"),
        ("msxml6", "MS XML 6", "Microsoft XML Core Services 6"),
        ("physx", "PhysX", "NVIDIA PhysX"),
        ("openal", "OpenAL", "OpenAL Audio"),
        ("quicktime63", "QuickTime 6.3", "QuickTime 6.3 (ältere Spiele)"),
    ]

    func run(components: [String], bottleName: String) -> AsyncStream<String> {
        AsyncStream { continuation in
            Task {
                guard let binary = binaryPath else {
                    continuation.yield("crossovertricks nicht gefunden.\n")
                    continuation.finish()
                    return
                }

                isRunning = true
                output = ""
                defer { isRunning = false }

                let task = Process()
                task.launchPath = binary
                task.arguments = ["--bottle", bottleName, "--install"] + components

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
