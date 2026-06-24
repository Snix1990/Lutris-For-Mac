import Foundation

// MARK: - DebugChannel

public struct DebugChannel: Identifiable, Codable {
    public let id: String
    public let displayName: String
    public let `default`: String

    public init(id: String, displayName: String, default: String) {
        self.id = id
        self.displayName = displayName
        self.default = `default`
    }
}

// MARK: - Known Wine Debug Channels

public let wineDebugChannels: [DebugChannel] = [
    DebugChannel(id: "err", displayName: "Errors", default: "+err"),
    DebugChannel(id: "warn", displayName: "Warnings", default: "+warn"),
    DebugChannel(id: "fixme", displayName: "FIXME", default: "+fixme"),
    DebugChannel(id: "trace", displayName: "Trace", default: "+trace"),
    DebugChannel(id: "loaddll", displayName: "DLL Loads", default: "+loaddll"),
    DebugChannel(id: "snoop", displayName: "Snoop (DLL tracing)", default: "+snoop"),
    DebugChannel(id: "heap", displayName: "Heap", default: "+heap"),
    DebugChannel(id: "relay", displayName: "Relay (API trace)", default: "+relay"),
    DebugChannel(id: "ole", displayName: "OLE", default: "+ole"),
    DebugChannel(id: "seh", displayName: "SEH (exceptions)", default: "+seh"),
    DebugChannel(id: "tid", displayName: "Thread IDs", default: "+tid"),
    DebugChannel(id: "timestamp", displayName: "Timestamps", default: "+timestamp"),
]

// MARK: - Presets

public enum DebugPreset: String, CaseIterable {
    case minimal = "minimal"
    case errorsOnly = "errors"
    case warnings = "warnings"
    case normal = "normal"
    case verbose = "verbose"
    case custom = "custom"

    public var displayName: String {
        switch self {
        case .minimal: return "Minimal (–all)"
        case .errorsOnly: return "Nur Fehler (err+fixme)"
        case .warnings: return "Warnungen (warn+err+fixme)"
        case .normal: return "Normal (err+fixme+loaddll)"
        case .verbose: return "Ausführlich (alle +tid)"
        case .custom: return "Benutzerdefiniert"
        }
    }

    public var wineDebugValue: String {
        switch self {
        case .minimal: return "-all"
        case .errorsOnly: return "+err,+fixme"
        case .warnings: return "+err,+warn,+fixme"
        case .normal: return "+err,+fixme,+loaddll"
        case .verbose: return "+err,+warn,+fixme,+loaddll,+tid,+timestamp,+seh"
        case .custom: return ""
        }
    }
}

// MARK: - WineDebugManager

@MainActor
public final class WineDebugManager: ObservableObject {
    public static let shared = WineDebugManager()

    @Published public var preset: DebugPreset = .normal
    @Published public var customString: String = ""
    @Published public var enabledChannelIDs: Set<String> = []
    @Published public var filterDebugLog: Bool = true

    private let defaultsPresetKey = "wineDebugPreset"
    private let defaultsCustomKey = "wineDebugCustom"
    private let defaultsFilterKey = "wineDebugFilter"

    private init() {
        load()
    }

    public func resolvedDebugString() -> String {
        if preset == .custom {
            return customString.trimmingCharacters(in: .whitespaces)
        }
        return preset.wineDebugValue
    }

    public func setPreset(_ newPreset: DebugPreset) {
        preset = newPreset
        if newPreset != .custom {
            enabledChannelIDs = Set(channelIDs(from: newPreset.wineDebugValue))
        }
        save()
    }

    public func toggleChannel(_ id: String) {
        if preset != .custom {
            preset = .custom
            enabledChannelIDs = Set(channelIDs(from: preset.wineDebugValue))
        }
        if enabledChannelIDs.contains(id) {
            enabledChannelIDs.remove(id)
        } else {
            enabledChannelIDs.insert(id)
        }
        customString = buildCustomString()
        save()
    }

    private func buildCustomString() -> String {
        enabledChannelIDs.sorted().map { "+\($0)" }.joined(separator: ",")
    }

    private func channelIDs(from debugString: String) -> [String] {
        debugString
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "+", with: "") }
            .filter { !$0.isEmpty && !$0.hasPrefix("-") }
    }

    private func save() {
        UserDefaults.standard.set(preset.rawValue, forKey: defaultsPresetKey)
        UserDefaults.standard.set(customString, forKey: defaultsCustomKey)
        UserDefaults.standard.set(filterDebugLog, forKey: defaultsFilterKey)
    }

    private func load() {
        if let raw = UserDefaults.standard.string(forKey: defaultsPresetKey),
           let p = DebugPreset(rawValue: raw) {
            preset = p
        }
        customString = UserDefaults.standard.string(forKey: defaultsCustomKey) ?? ""
        filterDebugLog = UserDefaults.standard.object(forKey: defaultsFilterKey) as? Bool ?? true
        if preset != .custom {
            enabledChannelIDs = Set(channelIDs(from: preset.wineDebugValue))
        } else {
            enabledChannelIDs = Set(channelIDs(from: customString))
        }
    }
}
