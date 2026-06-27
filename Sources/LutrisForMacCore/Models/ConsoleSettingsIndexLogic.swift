import Foundation

// MARK: - ConsoleSettingsIndexLogic

/// Stateless logic for ConsoleSettingsView's `actionForIndex` and `itemCount`.
/// Ermöglicht Unit-Testing ohne View- oder Controller-Abhängigkeiten.
public enum ConsoleSettingsIndexLogic {

    public enum SettingAction: Equatable {
        case toggle(Int)
        case controllerSettings
        case about
        case desktopExit
    }

    /// Ordnet einem flachen Index die entsprechende Aktion zu.
    public static func actionForIndex(
        _ index: Int,
        toggleCount: Int,
        controllerSettingsAvailable: Bool
    ) -> SettingAction? {
        var cursor = 0

        // Toggles
        if index < cursor + toggleCount {
            return .toggle(index - cursor)
        }
        cursor += toggleCount

        // Controller Settings Navigation
        if controllerSettingsAvailable {
            if index == cursor { return .controllerSettings }
            cursor += 1
        }

        // About
        if index == cursor { return .about }
        cursor += 1

        // Desktop Exit
        if index == cursor { return .desktopExit }

        return nil
    }

    /// Anzahl der Items — immer konsistent mit `actionForIndex`.
    public static func itemCount(
        toggleCount: Int,
        controllerSettingsAvailable: Bool
    ) -> Int {
        var cursor = 0
        cursor += toggleCount
        if controllerSettingsAvailable { cursor += 1 }
        cursor += 1 // about
        cursor += 1 // desktop exit
        return cursor
    }
}
