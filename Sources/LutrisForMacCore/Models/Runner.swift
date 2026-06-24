import Foundation

public struct Runner: Identifiable, Hashable, Codable {
    public let id: UUID
    public var name: String
    public var displayName: String
    public var category: RunnerCategory
    public var installType: String
    public var launchTemplate: LaunchTemplate
    public var installed: Bool
    public var installPath: String
    public var binaryPath: String
    public var supportsPlatforms: [String]
    public var configFields: [RunnerConfigField]

    public enum RunnerCategory: String, Codable, CaseIterable {
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

        public var systemImage: String {
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

    public enum LaunchTemplate: Codable, Hashable {
        case nativeApp
        case cli(String)
        case wine(String)
        case retroarch(String)
        case dosbox
        case mame
        case scummvm
        case custom

        public var isCLI: Bool {
            if case .nativeApp = self { return false }
            return true
        }

        public var displayDescription: String {
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

    public struct DetectionPath: Codable {
        public let type: DetectionType
        public let path: String
        public let bundleID: String?

        public enum DetectionType: String, Codable {
            case appBundle
            case homebrew
            case custom
            case script
        }
    }

    public struct RunnerConfigField: Identifiable, Hashable, Codable {
        public let id: String
        public var label: String
        public var type: ConfigType
        public var defaultValue: String
        public var help: String

        public enum ConfigType: String, Codable {
            case text
            case toggle
            case picker
            case filePicker
        }

        public init(id: String, label: String, type: ConfigType, defaultValue: String = "", help: String = "") {
            self.id = id
            self.label = label
            self.type = type
            self.defaultValue = defaultValue
            self.help = help
        }
    }

    public init(
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
