import SwiftUI
import LutrisForMacCore

struct ConsoleMenuCommands: Commands {
    var body: some Commands {
        CommandMenu("Console Mode") {
            Button("Console Mode öffnen") {
                WindowTransitionManager.switchToConsole()
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
        }
    }
}
