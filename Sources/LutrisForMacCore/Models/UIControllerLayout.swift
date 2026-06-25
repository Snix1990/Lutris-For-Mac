import Foundation

// MARK: - UI Controller Layout

public enum UIControllerLayout: String, Codable, CaseIterable, Sendable {
    case xbox = "Xbox"
    case playstation = "PlayStation"
    case nintendo = "Nintendo Switch"
    case generic = "Generic"
}

// MARK: - Logical UI Actions

public enum UIAction: String, Codable, CaseIterable, Sendable {
    case confirm
    case back
    case toggleSearch
    case menu
    case navTabLeft
    case navTabRight
    case moveUp
    case moveDown
    case moveLeft
    case moveRight
    case cycleContentSectionUp
    case cycleContentSectionDown

    public var displayName: String {
        switch self {
        case .confirm: return "Confirm (Bestätigen)"
        case .back: return "Back (Zurück)"
        case .toggleSearch: return "Search (Suche)"
        case .menu: return "Menu (Hauptmenü)"
        case .navTabLeft: return "Tab Left (Tab links)"
        case .navTabRight: return "Tab Right (Tab rechts)"
        case .moveUp: return "Move Up (Hoch)"
        case .moveDown: return "Move Down (Runter)"
        case .moveLeft: return "Move Left (Links)"
        case .moveRight: return "Move Right (Rechts)"
        case .cycleContentSectionUp: return "Section Up (Sektion hoch)"
        case .cycleContentSectionDown: return "Section Down (Sektion runter)"
        }
    }
}

// MARK: - Physical Button IDs (matching GCController extended gamepad)

public let allPhysicalButtons: [String] = [
    "buttonA", "buttonB", "buttonX", "buttonY",
    "leftShoulder", "rightShoulder",
    "leftTrigger", "rightTrigger",
    "dpadUp", "dpadDown", "dpadLeft", "dpadRight",
    "leftThumbStickUp", "leftThumbStickDown", "leftThumbStickLeft", "leftThumbStickRight",
    "leftThumbstickButton", "rightThumbstickButton",
    "buttonMenu", "buttonOptions",
]

public let physicalButtonDisplayNames: [String: String] = [
    "buttonA": "A (Bottom)",
    "buttonB": "B (Right)",
    "buttonX": "X (Left)",
    "buttonY": "Y (Top)",
    "leftShoulder": "L1 (Left Shoulder)",
    "rightShoulder": "R1 (Right Shoulder)",
    "leftTrigger": "L2 (Left Trigger)",
    "rightTrigger": "R2 (Right Trigger)",
    "dpadUp": "DPad ↑",
    "dpadDown": "DPad ↓",
    "dpadLeft": "DPad ←",
    "dpadRight": "DPad →",
    "leftThumbStickUp": "L-Stick ↑",
    "leftThumbStickDown": "L-Stick ↓",
    "leftThumbStickLeft": "L-Stick ←",
    "leftThumbStickRight": "L-Stick →",
    "leftThumbstickButton": "L3 (L-Stick Button)",
    "rightThumbstickButton": "R3 (R-Stick Button)",
    "buttonMenu": "Menu",
    "buttonOptions": "Options",
]

// MARK: - Default Mapping Per Layout

public extension UIControllerLayout {

    /// Returns the physical button ID for the given UI action under this layout.
    func physicalButtonID(for action: UIAction) -> String {
        switch self {
        case .xbox, .playstation, .generic:
            return xboxLikeMapping(for: action)
        case .nintendo:
            return nintendoMapping(for: action)
        }
    }

    /// The reverse mapping: for a given physical button ID, returns the UI action(s).
    /// Used when polling to determine which action to fire.
    func actionsForPhysicalButton(_ physicalID: String) -> [UIAction] {
        // In rare cases one physical button could trigger multiple actions,
        // but we keep it 1:1 for simplicity.
        for action in UIAction.allCases {
            if physicalButtonID(for: action) == physicalID {
                return [action]
            }
        }
        return []
    }

    /// Build a full mapping dictionary: physicalID → UIAction
    var physicalToAction: [String: UIAction] {
        var result: [String: UIAction] = [:]
        for action in UIAction.allCases {
            let phys = physicalButtonID(for: action)
            result[phys] = action
        }
        return result
    }

    /// Build reverse mapping: UIAction → physicalID
    var actionToPhysical: [UIAction: String] {
        var result: [UIAction: String] = [:]
        for action in UIAction.allCases {
            result[action] = physicalButtonID(for: action)
        }
        return result
    }
}

// MARK: - Private Mapping Helpers

private extension UIControllerLayout {

    func xboxLikeMapping(for action: UIAction) -> String {
        switch action {
        case .confirm:               return "buttonA"
        case .back:                  return "buttonB"
        case .toggleSearch:          return "buttonOptions"
        case .menu:                  return "buttonMenu"
        case .navTabLeft:            return "leftShoulder"
        case .navTabRight:           return "rightShoulder"
        case .moveUp:                return "leftThumbStickUp"
        case .moveDown:              return "leftThumbStickDown"
        case .moveLeft:              return "leftThumbStickLeft"
        case .moveRight:             return "leftThumbStickRight"
        case .cycleContentSectionUp: return "dpadUp"
        case .cycleContentSectionDown: return "dpadDown"
        }
    }

    func nintendoMapping(for action: UIAction) -> String {
        switch action {
        // Nintendo: right button (A) = confirm, bottom button (B) = back
        case .confirm:               return "buttonB"
        case .back:                  return "buttonA"
        case .toggleSearch:          return "buttonOptions"
        case .menu:                  return "buttonMenu"
        case .navTabLeft:            return "leftShoulder"
        case .navTabRight:           return "rightShoulder"
        case .moveUp:                return "leftThumbStickUp"
        case .moveDown:              return "leftThumbStickDown"
        case .moveLeft:              return "leftThumbStickLeft"
        case .moveRight:             return "leftThumbStickRight"
        case .cycleContentSectionUp: return "dpadUp"
        case .cycleContentSectionDown: return "dpadDown"
        }
    }
}

// MARK: - Custom Mapping Override

/// A custom mapping for UI navigation actions (user-customizable).
public struct UICustomMapping: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var action: UIAction
    public var physicalButtonID: String
    public var isActive: Bool = true
}
