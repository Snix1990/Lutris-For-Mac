import SwiftUI
import LutrisForMacCore

@main
struct ConsoleApp: App {
    @StateObject private var lang = LanguageManager.shared

    var body: some Scene {
        WindowGroup {
            ConsoleMainView()
                .id(lang.refreshID)
                .environment(\.locale, lang.locale)
                .onAppear {
                    if let w = NSApp.windows.first(where: { $0.isVisible }),
                       let screen = w.screen ?? NSScreen.main {
                        w.styleMask = [.borderless, .resizable]
                        w.setFrame(screen.frame, display: true)
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 1280, height: 800)
    }
}
