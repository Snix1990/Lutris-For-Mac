import Foundation

struct Emulator: Identifiable, Codable {
    let id: UUID
    let name: String
    let displayName: String
    let category: Runner.RunnerCategory
    let description: String
    let supportsPlatforms: [String]
    let installType: InstallType
    let appName: String?
    let brewName: String?
    let bundleID: String?

    // GitHub Release-Quelle (wenn verfügbar)
    let githubOwner: String?
    let githubRepo: String?

    // Fallback: direkte Download-URL
    let directDownloadURL: String?
    let downloadPageURL: String

    // Wird vom Manager gesetzt
    var installed: Bool = false
    var installPath: String = ""
    var installedVersion: String = ""
    var latestVersion: String = ""

    private static func extractVersion(_ s: String) -> [Int] {
        guard let range = s.range(of: #"\d+(\.\d+)*"#, options: .regularExpression) else { return [] }
        return s[range].split(separator: ".").compactMap { Int($0) }
    }

    private static func compareVersions(_ a: String, _ b: String) -> ComparisonResult {
        let va = extractVersion(a), vb = extractVersion(b)
        for i in 0..<min(va.count, vb.count) {
            if va[i] < vb[i] { return .orderedAscending }
            if va[i] > vb[i] { return .orderedDescending }
        }
        if va.count < vb.count { return .orderedAscending }
        if va.count > vb.count { return .orderedDescending }
        return .orderedSame
    }

    var updateAvailable: Bool {
        installed && !installedVersion.isEmpty && !latestVersion.isEmpty &&
        Self.compareVersions(installedVersion, latestVersion) != .orderedSame
    }

    enum InstallType: String, Codable, CaseIterable {
        case dmg
        case zip
        case tarGz
        case pkg
        case homebrew

        var displayName: String {
            switch self {
            case .dmg: return "DMG (App)"
            case .zip: return "ZIP (App)"
            case .tarGz: return "TAR.GZ"
            case .pkg: return "PKG-Installer"
            case .homebrew: return "Homebrew"
            }
        }
    }

    init(
        id: UUID = UUID(),
        name: String,
        displayName: String = "",
        category: Runner.RunnerCategory,
        description: String = "",
        supportsPlatforms: [String] = [],
        installType: InstallType,
        appName: String? = nil,
        brewName: String? = nil,
        bundleID: String? = nil,
        githubOwner: String? = nil,
        githubRepo: String? = nil,
        directDownloadURL: String? = nil,
        downloadPageURL: String = "",
        installed: Bool = false,
        installPath: String = ""
    ) {
        self.id = id
        self.name = name
        self.displayName = displayName.isEmpty ? name : displayName
        self.category = category
        self.description = description
        self.supportsPlatforms = supportsPlatforms
        self.installType = installType
        self.appName = appName
        self.brewName = brewName
        self.bundleID = bundleID
        self.githubOwner = githubOwner
        self.githubRepo = githubRepo
        self.directDownloadURL = directDownloadURL
        self.downloadPageURL = downloadPageURL
        self.installed = installed
        self.installPath = installPath
    }

    static let all: [Emulator] = [
        // --- Retro ---
        Emulator(
            name: "DOSBox",
            category: .retro,
            description: "DOS-Emulator für klassische DOS-Spiele",
            supportsPlatforms: ["DOS"],
            installType: .homebrew,
            appName: "DOSBox.app",
            brewName: "dosbox",
            downloadPageURL: "https://www.dosbox.com/download.php?main=1"
        ),
        Emulator(
            name: "DOSBox-X",
            displayName: "DOSBox-X (erweiterter DOS-Emulator)",
            category: .retro,
            description: "Erweiterter DOS-Emulator mit mehr Funktionen",
            supportsPlatforms: ["DOS"],
            installType: .zip,
            appName: "DOSBox-X.app",
            githubOwner: "joncampbell123",
            githubRepo: "dosbox-x",
            downloadPageURL: "https://dosbox-x.com/"
        ),
        Emulator(
            name: "ScummVM",
            category: .retro,
            description: "Emulator für klassische Point&Click-Adventures (Scumm, AGI, etc.)",
            supportsPlatforms: ["DOS", "Windows"],
            installType: .dmg,
            appName: "ScummVM.app",
            brewName: "scummvm",
            downloadPageURL: "https://www.scummvm.org/downloads/"
        ),
        Emulator(
            name: "RetroArch",
            displayName: "RetroArch (Multi-System)",
            category: .retro,
            description: "All-in-One-Emulator über Libretro-Cores",
            supportsPlatforms: ["Multi"],
            installType: .dmg,
            appName: "RetroArch.app",
            brewName: "retroarch",
            downloadPageURL: "https://retroarch.com/?page=platforms"
        ),
        Emulator(
            name: "OpenEmu",
            displayName: "OpenEmu (Multi-System, macOS-native UI)",
            category: .retro,
            description: "macOS-native Multi-System-Emulator",
            supportsPlatforms: ["Multi"],
            installType: .dmg,
            appName: "OpenEmu.app",
            bundleID: "org.openemu.OpenEmu",
            githubOwner: "OpenEmu",
            githubRepo: "OpenEmu",
            downloadPageURL: "https://openemu.org/download/"
        ),

        // --- Nintendo ---
        Emulator(
            name: "Dolphin",
            displayName: "Dolphin (GameCube/Wii)",
            category: .nintendo,
            description: "GameCube- und Wii-Emulator mit hoher Kompatibilität",
            supportsPlatforms: ["GameCube", "Wii"],
            installType: .dmg,
            appName: "Dolphin.app",
            brewName: "dolphin-emu",
            githubOwner: "dolphin-emu",
            githubRepo: "dolphin",
            downloadPageURL: "https://dolphin-emu.org/download/"
        ),
        Emulator(
            name: "MelonDS",
            displayName: "melonDS (Nintendo DS)",
            category: .nintendo,
            description: "Nintendo-DS-Emulator mit Multiplayer-Features",
            supportsPlatforms: ["Nintendo DS"],
            installType: .zip,
            appName: "melonDS.app",
            githubOwner: "melonDS-emu",
            githubRepo: "melonDS",
            downloadPageURL: "https://melonds.kuribo64.net/downloads.php"
        ),
        Emulator(
            name: "Ryujinx",
            displayName: "Ryujinx (Nintendo Switch)",
            category: .nintendo,
            description: "Nintendo-Switch-Emulator für macOS (Apple Silicon)",
            supportsPlatforms: ["Switch"],
            installType: .dmg,
            appName: "Ryujinx.app",
            githubOwner: "Ryujinx",
            githubRepo: "Ryujinx",
            downloadPageURL: "https://ryujinx.org/download"
        ),
        Emulator(
            name: "Astris",
            displayName: "Astris (Nintendo Switch)",
            category: .nintendo,
            description: "Nintendo-Switch-Emulator mit Vulkan-Unterstützung (Apple Silicon)",
            supportsPlatforms: ["Switch"],
            installType: .dmg,
            appName: "Astris.app",
            githubOwner: "V380-Ori",
            githubRepo: "Astris.Binaries",
            downloadPageURL: "https://github.com/V380-Ori/Astris.Binaries/releases"
        ),
        Emulator(
            name: "Azahar",
            displayName: "Azahar (Nintendo 3DS)",
            category: .nintendo,
            description: "Nintendo-3DS-Emulator mit Citra-Fork (Apple Silicon)",
            supportsPlatforms: ["3DS"],
            installType: .zip,
            appName: "azahar.app",
            githubOwner: "azahar-emu",
            githubRepo: "azahar",
            downloadPageURL: "https://github.com/azahar-emu/azahar/releases"
        ),

        // --- PlayStation ---
        Emulator(
            name: "PCSX2",
            displayName: "PCSX2 (PlayStation 2)",
            category: .playstation,
            description: "PlayStation-2-Emulator mit breiter Spielunterstützung",
            supportsPlatforms: ["PS2"],
            installType: .dmg,
            appName: "PCSX2.app",
            brewName: "pcsx2",
            githubOwner: "PCSX2",
            githubRepo: "pcsx2",
            downloadPageURL: "https://pcsx2.net/downloads/"
        ),
        Emulator(
            name: "RPCS3",
            displayName: "RPCS3 (PlayStation 3)",
            category: .playstation,
            description: "PlayStation-3-Emulator – experimentell auf macOS",
            supportsPlatforms: ["PS3"],
            installType: .dmg,
            appName: "RPCS3.app",
            downloadPageURL: "https://rpcs3.net/download"
        ),
        Emulator(
            name: "DuckStation",
            displayName: "DuckStation (PlayStation 1)",
            category: .playstation,
            description: "PlayStation-1-Emulator mit hoher Genauigkeit",
            supportsPlatforms: ["PS1"],
            installType: .zip,
            appName: "DuckStation.app",
            directDownloadURL: "https://github.com/stenzek/duckstation/releases/download/latest/duckstation-mac-release.zip",
            downloadPageURL: "https://github.com/stenzek/duckstation/releases"
        ),

        // --- Sega ---
        Emulator(
            name: "Flycast",
            displayName: "Flycast (Dreamcast/NAOMI)",
            category: .sega,
            description: "Sega-Dreamcast- und NAOMI-Emulator",
            supportsPlatforms: ["Dreamcast", "NAOMI"],
            installType: .zip,
            appName: "Flycast.app",
            githubOwner: "flyinghead",
            githubRepo: "flycast",
            downloadPageURL: "https://github.com/flyinghead/flycast/releases"
        ),

        // --- Handheld ---
        Emulator(
            name: "PPSSPP",
            displayName: "PPSSPP (PSP)",
            category: .handheld,
            description: "PSP-Emulator mit Hochskalierung",
            supportsPlatforms: ["PSP"],
            installType: .dmg,
            appName: "PPSSPP.app",
            brewName: "ppsspp",
            githubOwner: "hrydgard",
            githubRepo: "ppsspp",
            downloadPageURL: "https://github.com/hrydgard/ppsspp/releases"
        ),

        // --- Mobile / iPad ---
        Emulator(
            name: "PlayCover",
            displayName: "PlayCover (iOS/iPadOS-Apps auf macOS)",
            category: .other,
            description: "Führe iOS- und iPadOS-Apps auf Apple Silicon Macs aus",
            supportsPlatforms: ["iOS", "iPadOS"],
            installType: .dmg,
            appName: "PlayCover.app",
            githubOwner: "PlayCover",
            githubRepo: "PlayCover",
            downloadPageURL: "https://github.com/PlayCover/PlayCover/releases"
        ),
    ]
}
