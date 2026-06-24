import SwiftUI

public enum KeybindAction: String, CaseIterable, Codable {
    case newGame = "newGame"
    case search = "search"
    case deleteGame = "deleteGame"
    case refreshLibrary = "refreshLibrary"
    case scanROMs = "scanROMs"
    case toggleOSD = "toggleOSD"
    case releaseMouse = "releaseMouse"

    public var defaultKey: KeyEquivalent {
        switch self {
        case .newGame: "n"
        case .search: "f"
        case .deleteGame: .delete
        case .refreshLibrary: "r"
        case .scanROMs: "s"
        case .toggleOSD: "o"
        case .releaseMouse: "m"
        }
    }

    public var defaultModifiers: EventModifiers {
        switch self {
        case .newGame: .command
        case .search: .command
        case .deleteGame: .command
        case .refreshLibrary: .command
        case .scanROMs: [.command, .shift]
        case .toggleOSD: [.command, .shift]
        case .releaseMouse: [.command, .shift]
        }
    }

    public var displayName: String {
        switch self {
        case .newGame: "Neues Spiel"
        case .search: "Suche fokussieren"
        case .deleteGame: "Spiel löschen"
        case .refreshLibrary: "Bibliothek aktualisieren"
        case .scanROMs: "ROMs scannen"
        case .toggleOSD: "OSD ein/aus"
        case .releaseMouse: "Maus freigeben / OSD"
        }
    }
}

public struct KeybindShortcut: Codable, Equatable {
    public var key: KeyEquivalent
    public var modifiers: EventModifiers

    public init(key: KeyEquivalent, modifiers: EventModifiers) {
        self.key = key
        self.modifiers = modifiers
    }

    public var displayString: String {
        var parts: [String] = []
        if modifiers.contains(.command) { parts.append("⌘") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.control) { parts.append("⌃") }
        let ch = key.character
        if ch == "\u{7f}" { parts.append("⌫") }
        else { parts.append(ch.uppercased()) }
        return parts.joined()
    }
}

public enum Keybinds {
    private static let defaultsKey = "customKeybinds"

    public static func shortcut(for action: KeybindAction) -> KeybindShortcut {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let dict = try? JSONDecoder().decode([String: KeybindShortcut].self, from: data),
              let custom = dict[action.rawValue] else {
            return KeybindShortcut(key: action.defaultKey, modifiers: action.defaultModifiers)
        }
        return custom
    }

    public static func setShortcut(_ shortcut: KeybindShortcut, for action: KeybindAction) {
        let data = UserDefaults.standard.data(forKey: defaultsKey)
        var dict = data.flatMap { try? JSONDecoder().decode([String: KeybindShortcut].self, from: $0) } ?? [:]
        dict[action.rawValue] = shortcut
        if let encoded = try? JSONEncoder().encode(dict) {
            UserDefaults.standard.set(encoded, forKey: defaultsKey)
        }
    }

    public static func reset(for action: KeybindAction) {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              var dict = try? JSONDecoder().decode([String: KeybindShortcut].self, from: data) else { return }
        dict.removeValue(forKey: action.rawValue)
        if dict.isEmpty {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
        } else if let encoded = try? JSONEncoder().encode(dict) {
            UserDefaults.standard.set(encoded, forKey: defaultsKey)
        }
    }

    public static func resetAll() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }
}

// MARK: - Codable conformance helpers

extension KeyEquivalent: @retroactive Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let str = try container.decode(String.self)
        self.init(Character(str))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(String(character))
    }
}

extension EventModifiers: @retroactive Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(Int.self)
        self.init(rawValue: raw)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
