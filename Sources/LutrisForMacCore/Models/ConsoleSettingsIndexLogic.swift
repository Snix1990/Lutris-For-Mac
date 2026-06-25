import Foundation

// MARK: - ConsoleSettingsIndexLogic

/// Stateless logic for ConsoleSettingsView's `actionForIndex` and `itemCount`.
/// Ermöglicht Unit-Testing ohne View- oder Controller-Abhängigkeiten.
public enum ConsoleSettingsIndexLogic {

    public enum SettingAction: Equatable {
        case toggle(Int)
        case controllerInfo(Int)
        case uiNavHeader
        case uiNavAutoDetection
        case uiNavControllerLayout(Int)
        case uiNavCustomHeader
        case uiNavCustomMapping(Int)
        case uiNavCustomAdd
        case uiNavCustomReset
        case hidRunnerHeader
        case hidRunnerItem(Int)
        case remappingHeader
        case remappingItem(Int)
        case remappingAdd
        case about
        case desktopExit
    }

    /// Ordnet einem flachen Index die entsprechende Aktion zu.
    public static func actionForIndex(
        _ index: Int,
        toggleCount: Int,
        controllerCount: Int,
        uiNavExpanded: Bool,
        uiCustomExpanded: Bool,
        customMappingCount: Int,
        hidRunnerExpanded: Bool,
        runnerCount: Int,
        remappingExpanded: Bool,
        remappingCount: Int
    ) -> SettingAction? {
        var cursor = 0

        // Toggles
        if index < cursor + toggleCount {
            return .toggle(index - cursor)
        }
        cursor += toggleCount

        // Controller
        let ctrlCount = max(controllerCount, 1)
        if index < cursor + ctrlCount {
            return .controllerInfo(index - cursor)
        }
        cursor += ctrlCount

        // UI Navigation Header
        guard index >= cursor else { return nil }
        if index == cursor { return .uiNavHeader }
        cursor += 1

        if uiNavExpanded {
            // Auto-Detection
            if index == cursor { return .uiNavAutoDetection }
            cursor += 1

            // Controller-Layout Picker
            if index < cursor + controllerCount {
                return .uiNavControllerLayout(index - cursor)
            }
            cursor += controllerCount

            // Custom Mapping Header
            if index == cursor { return .uiNavCustomHeader }
            cursor += 1

            if uiCustomExpanded {
                // Custom Mapping Items
                if index < cursor + customMappingCount {
                    return .uiNavCustomMapping(index - cursor)
                }
                cursor += customMappingCount

                // Add Button
                if index == cursor { return .uiNavCustomAdd }
                cursor += 1

                // Reset Button
                if customMappingCount > 0 {
                    if index == cursor { return .uiNavCustomReset }
                    cursor += 1
                }
            }
        }

        // HID Runner Header
        if index == cursor { return .hidRunnerHeader }
        cursor += 1

        if hidRunnerExpanded {
            if index < cursor + runnerCount {
                return .hidRunnerItem(index - cursor)
            }
            cursor += runnerCount
        }

        // Remapping Header
        if index == cursor { return .remappingHeader }
        cursor += 1

        if remappingExpanded {
            if index < cursor + remappingCount {
                return .remappingItem(index - cursor)
            }
            cursor += remappingCount

            if index == cursor { return .remappingAdd }
            cursor += 1
        }

        // About
        if index == cursor { return .about }
        cursor += 1

        // Desktop Exit
        if index == cursor { return .desktopExit }

        return nil
    }

    // MARK: - Section Boundaries

    /// Alle vom View benötigten Abschnitts-Grenzen.
    /// Einzige Quelle der Wahrheit – View darf keine eigene Cursor-Arithmetik haben.
    public struct SettingsBoundaries: Equatable {
        public let uiNavigationStart: Int
        public let virtualHIDStart: Int
        public let remappingStart: Int
        public let aboutStart: Int
        public let totalCount: Int
    }

    /// Berechnet alle Abschnitts-Grenzen in einem Durchlauf.
    public static func computeBoundaries(
        toggleCount: Int,
        controllerCount: Int,
        uiNavExpanded: Bool,
        uiCustomExpanded: Bool,
        customMappingCount: Int,
        hidRunnerExpanded: Bool,
        runnerCount: Int,
        remappingExpanded: Bool,
        remappingCount: Int
    ) -> SettingsBoundaries {
        let ctrlCount = max(controllerCount, 1)

        // toggles + controllers
        var cursor = toggleCount + ctrlCount
        let uiNavStart = cursor

        // uiNavHeader
        cursor += 1

        if uiNavExpanded {
            cursor += 1 // auto-detection
            cursor += controllerCount
            cursor += 1 // custom header
            if uiCustomExpanded {
                cursor += customMappingCount
                cursor += 1 // add
                if customMappingCount > 0 { cursor += 1 /* reset */ }
            }
        }

        let virtualHIDStart = cursor

        // hidRunnerHeader
        cursor += 1
        if hidRunnerExpanded { cursor += runnerCount }

        let remappingStart = cursor

        // remappingHeader
        cursor += 1
        if remappingExpanded {
            cursor += remappingCount
            cursor += 1 // add
        }

        let aboutStart = cursor

        cursor += 1 // about
        cursor += 1 // desktop exit

        return SettingsBoundaries(
            uiNavigationStart: uiNavStart,
            virtualHIDStart: virtualHIDStart,
            remappingStart: remappingStart,
            aboutStart: aboutStart,
            totalCount: cursor
        )
    }

    /// Anzahl der Items — immer konsistent mit `actionForIndex`.
    public static func itemCount(
        toggleCount: Int,
        controllerCount: Int,
        uiNavExpanded: Bool,
        uiCustomExpanded: Bool,
        customMappingCount: Int,
        hidRunnerExpanded: Bool,
        runnerCount: Int,
        remappingExpanded: Bool,
        remappingCount: Int
    ) -> Int {
        var cursor = 0
        cursor += toggleCount
        cursor += max(controllerCount, 1)
        cursor += 1 // uiNavHeader
        if uiNavExpanded {
            cursor += 1 // auto-detection
            cursor += controllerCount
            cursor += 1 // custom header
            if uiCustomExpanded {
                cursor += customMappingCount
                cursor += 1 // add
                if customMappingCount > 0 { cursor += 1 /* reset */ }
            }
        }
        cursor += 1 // hidRunnerHeader
        if hidRunnerExpanded { cursor += runnerCount }
        cursor += 1 // remappingHeader
        if remappingExpanded {
            cursor += remappingCount
            cursor += 1 // add
        }
        cursor += 1 // about
        cursor += 1 // desktop exit
        return cursor
    }
}
