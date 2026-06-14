import Foundation

struct Runner: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var displayName: String
    var category: RunnerCategory
    var installType: String
    var launchTemplate: LaunchTemplate
    var installed: Bool
    var installPath: String
    var binaryPath: String
    var supportsPlatforms: [String]
    var configFields: [RunnerConfigField]

    enum RunnerCategory: String, Codable, CaseIterable {
        case wine = "Wine/Proton"
        case native = "Native macOS"
        case windows = "Windows"
        case linux = "Linux"
        case retro = "Retro-Emulatoren"
        case nintendo = "Nintendo-Emulatoren"
        case playstation = "PlayStation-Emulatoren"
        case sega = "Sega-Emulatoren"
        case handheld = "Handheld-Emulatoren"
        case other = "Andere"

        var systemImage: String {
            switch self {
            case .wine: return "wineglass"
            case .native: return "macwindow"
            case .windows: return "pc"
            case .linux: return "terminal"
            case .retro: return "sparkle.magnifyingglass"
            case .nintendo: return "gamecontroller"
            case .playstation: return "playstation.logo"
            case .sega: return "gear"
            case .handheld: return "hand.raised"
            case .other: return "ellipsis.circle"
            }
        }
    }

    enum LaunchTemplate: Codable, Hashable {
        case nativeApp           // NSWorkspace.shared.open
        case cli(String)         // custom command template with {gamePath} placeholder
        case wine(String)        // Wine binary path
        case retroarch(String)   // RetroArch core
        case dosbox              // DOSBox
        case mame                // MAME
        case scummvm             // ScummVM
        case custom              // user-defined command

        var isCLI: Bool {
            if case .nativeApp = self { return false }
            return true
        }

        var displayDescription: String {
            switch self {
            case .nativeApp: return "Öffnet die .app mit NSWorkspace"
            case .cli(let cmd): return "CLI: \(cmd)"
            case .wine(let path): return "Wine: \(path)"
            case .retroarch(let core): return "RetroArch: \(core)"
            case .dosbox: return "DOSBox"
            case .mame: return "MAME"
            case .scummvm: return "ScummVM"
            case .custom: return "Benutzerdefiniert"
            }
        }
    }

    struct DetectionPath: Codable {
        let type: DetectionType
        let path: String
        let bundleID: String?

        enum DetectionType: String, Codable {
            case appBundle
            case homebrew
            case custom
            case script
        }
    }

    struct RunnerConfigField: Identifiable, Hashable, Codable {
        let id: String
        var label: String
        var type: ConfigType
        var defaultValue: String
        var help: String

        enum ConfigType: String, Codable {
            case text
            case toggle
            case picker
            case filePicker
        }

        init(id: String, label: String, type: ConfigType, defaultValue: String = "", help: String = "") {
            self.id = id
            self.label = label
            self.type = type
            self.defaultValue = defaultValue
            self.help = help
        }
    }

    init(
        id: UUID = UUID(),
        name: String,
        displayName: String = "",
        category: RunnerCategory,
        installType: String = "",
        launchTemplate: LaunchTemplate,
        installed: Bool = false,
        installPath: String = "",
        binaryPath: String = "",
        supportsPlatforms: [String] = [],
        configFields: [RunnerConfigField] = []
    ) {
        self.id = id
        self.name = name
        self.displayName = displayName.isEmpty ? name : displayName
        self.category = category
        self.installType = installType
        self.launchTemplate = launchTemplate
        self.installed = installed
        self.installPath = installPath
        self.binaryPath = binaryPath
        self.supportsPlatforms = supportsPlatforms
        self.configFields = configFields
    }
}
