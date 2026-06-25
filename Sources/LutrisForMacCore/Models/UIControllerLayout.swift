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

// MARK: - Physical Button (type-safe replacement for raw strings)

public enum PhysicalButton: String, Codable, CaseIterable, Hashable, Sendable {
    case buttonA
    case buttonB
    case buttonX
    case buttonY
    case leftShoulder
    case rightShoulder
    case leftTrigger
    case rightTrigger
    case dpadUp
    case dpadDown
    case dpadLeft
    case dpadRight
    case leftThumbStickUp
    case leftThumbStickDown
    case leftThumbStickLeft
    case leftThumbStickRight
    case leftThumbstickButton
    case rightThumbstickButton
    case buttonMenu
    case buttonOptions

    public var displayName: String {
        switch self {
        case .buttonA: return "A (Bottom)"
        case .buttonB: return "B (Right)"
        case .buttonX: return "X (Left)"
        case .buttonY: return "Y (Top)"
        case .leftShoulder: return "L1 (Left Shoulder)"
        case .rightShoulder: return "R1 (Right Shoulder)"
        case .leftTrigger: return "L2 (Left Trigger)"
        case .rightTrigger: return "R2 (Right Trigger)"
        case .dpadUp: return "DPad ↑"
        case .dpadDown: return "DPad ↓"
        case .dpadLeft: return "DPad ←"
        case .dpadRight: return "DPad →"
        case .leftThumbStickUp: return "L-Stick ↑"
        case .leftThumbStickDown: return "L-Stick ↓"
        case .leftThumbStickLeft: return "L-Stick ←"
        case .leftThumbStickRight: return "L-Stick →"
        case .leftThumbstickButton: return "L3 (L-Stick Button)"
        case .rightThumbstickButton: return "R3 (R-Stick Button)"
        case .buttonMenu: return "Menu"
        case .buttonOptions: return "Options"
        }
    }

    /// The raw string key used by GCController polling and prevState dictionary.
    /// (only needed internally by ControllerNavigationSystem)
    public var pollKey: String {
        rawValue.prefix(1).lowercased() + rawValue.dropFirst()
    }
}

// MARK: - Default Mapping Per Layout

public extension UIControllerLayout {

    /// Returns the physical button for the given UI action under this layout.
    func physicalButton(for action: UIAction) -> PhysicalButton {
        switch self {
        case .xbox, .playstation, .generic:
            return xboxLikeMapping(for: action)
        case .nintendo:
            return nintendoMapping(for: action)
        }
    }

    /// Build a full mapping dictionary: PhysicalButton → UIAction
    var physicalToAction: [PhysicalButton: UIAction] {
        Dictionary(uniqueKeysWithValues: UIAction.allCases.map {
            (physicalButton(for: $0), $0)
        })
    }

    /// Build reverse mapping: UIAction → PhysicalButton
    var actionToPhysical: [UIAction: PhysicalButton] {
        Dictionary(uniqueKeysWithValues: UIAction.allCases.map {
            ($0, physicalButton(for: $0))
        })
    }
}

// MARK: - Private Mapping Helpers

private extension UIControllerLayout {

    func xboxLikeMapping(for action: UIAction) -> PhysicalButton {
        switch action {
        case .confirm:               return .buttonA
        case .back:                  return .buttonB
        case .toggleSearch:          return .buttonOptions
        case .menu:                  return .buttonMenu
        case .navTabLeft:            return .leftShoulder
        case .navTabRight:           return .rightShoulder
        case .moveUp:                return .leftThumbStickUp
        case .moveDown:              return .leftThumbStickDown
        case .moveLeft:              return .leftThumbStickLeft
        case .moveRight:             return .leftThumbStickRight
        case .cycleContentSectionUp: return .dpadUp
        case .cycleContentSectionDown: return .dpadDown
        }
    }

    func nintendoMapping(for action: UIAction) -> PhysicalButton {
        switch action {
        case .confirm:               return .buttonB
        case .back:                  return .buttonA
        case .toggleSearch:          return .buttonOptions
        case .menu:                  return .buttonMenu
        case .navTabLeft:            return .leftShoulder
        case .navTabRight:           return .rightShoulder
        case .moveUp:                return .leftThumbStickUp
        case .moveDown:              return .leftThumbStickDown
        case .moveLeft:              return .leftThumbStickLeft
        case .moveRight:             return .leftThumbStickRight
        case .cycleContentSectionUp: return .dpadUp
        case .cycleContentSectionDown: return .dpadDown
        }
    }
}

// MARK: - Custom Mapping Override

/// A custom mapping for UI navigation actions (user-customizable).
public struct UICustomMapping: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var action: UIAction
    public var physicalButton: PhysicalButton
    public var isActive: Bool = true
}

// MARK: - Aliases for backward-compat string bridging

extension PhysicalButton {
    /// All physical buttons as an array (for pickers/settings UI)
    public static let allPhysicalButtons: [PhysicalButton] = allCases
}
