import SwiftUI

struct ControllerMenuCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandMenu("Controller") {
            Button {
                openWindow(id: "controller-settings")
            } label: {
                LText("Controller-Einstellungen")
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
        }
    }
}
