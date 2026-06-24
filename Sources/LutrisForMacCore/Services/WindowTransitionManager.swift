import AppKit

@MainActor
public enum WindowTransitionManager {

    /// Findet die URL des anderen Executables im selben Verzeichnis (funktioniert
    /// sowohl im `.build/debug/` als auch im `.app/Contents/MacOS/`).
    private static func otherExecutableURL(named name: String) -> URL? {
        guard let myDir = Bundle.main.executableURL?.deletingLastPathComponent() else { return nil }
        let url = myDir.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return url
    }

    /// Startet die Console-App als separaten Prozess und beendet die Desktop-App.
    public static func switchToConsole() {
        guard let consoleURL = otherExecutableURL(named: "LutrisForMacConsole") else {
            let alert = NSAlert()
            alert.messageText = "Console-Modus nicht gefunden"
            alert.informativeText = "LutrisForMacConsole wurde nicht im App-Bundle gefunden.\n\nBitte führe ./build-app.sh aus um beide Apps zu bauen."
            alert.runModal()
            return
        }
        let task = Process()
        task.executableURL = consoleURL
        do {
            try task.run()
            exit(0)
        } catch {
            NSLog("[WindowTransitionManager] Fehler beim Starten von LutrisForMacConsole: \(error)")
            let alert = NSAlert()
            alert.messageText = "Fehler beim Starten"
            alert.informativeText = "LutrisForMacConsole konnte nicht gestartet werden: \(error.localizedDescription)"
            alert.runModal()
        }
    }

    /// Startet die Desktop-App als separaten Prozess und beendet die Console-App.
    public static func switchToDesktop() {
        guard let desktopURL = otherExecutableURL(named: "LutrisForMac") else {
            let alert = NSAlert()
            alert.messageText = "Desktop-App nicht gefunden"
            alert.informativeText = "LutrisForMac wurde nicht im App-Bundle gefunden.\n\nBitte führe ./build-app.sh aus um beide Apps zu bauen."
            alert.runModal()
            return
        }
        let task = Process()
        task.executableURL = desktopURL
        do {
            try task.run()
            exit(0)
        } catch {
            NSLog("[WindowTransitionManager] Fehler beim Starten von LutrisForMac: \(error)")
            let alert = NSAlert()
            alert.messageText = "Fehler beim Starten"
            alert.informativeText = "LutrisForMac konnte nicht gestartet werden: \(error.localizedDescription)"
            alert.runModal()
        }
    }
}
