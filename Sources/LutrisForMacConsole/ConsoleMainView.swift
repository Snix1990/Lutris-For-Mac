import SwiftUI
import LutrisForMacCore

// ================================================================
// ConsoleMainView.swift (Optimiert)
// ================================================================

public struct ConsoleMainView: View {
    let games: [Game]
    let onLaunch: ((Game) -> Void)?
    @StateObject private var consoleState = ConsoleState()
    @StateObject private var focusManager = ConsoleFocusManager()
    @StateObject private var navState = ConsoleNavState()
    @State private var selectedDetailGame: Game?
    @State private var showControllerSettings = false
    @AppStorage("console_low_power_mode") private var lowPowerMode = false


    private var speedMultiplier: CGFloat {
        lowPowerMode ? 0 : 1.0
    }
    
    public init(games: [Game] = ConsoleDataSource.games, onLaunch: ((Game) -> Void)? = nil) {
        self.games = games
        self.onLaunch = onLaunch
    }

    private var onShowDetails: (Game) -> Void {
        { game in selectedDetailGame = game }
    }

    public var body: some View {
        ZStack {
            RetroWaveBackground(speedMultiplier: speedMultiplier, lowPowerMode: lowPowerMode)
            
            VStack(spacing: 0) {
                // NavBar oben
                if consoleState.currentScreen != .welcome {
                    ConsoleNavBar()
                        .environmentObject(navState)
                        .environmentObject(focusManager)
                }
                
                // Content-Bereich mit Transition
                ZStack {
                    if consoleState.currentScreen == .welcome {
                        WelcomeView(onContinue: {
                            navState.activeScreen = .library
                            consoleState.showLibrary()
                        })
                        .transition(.opacity)
                    } else {
                        // Falls Controller-Settings aktiv ist, diese anzeigen (statt Settings)
                        if showControllerSettings {
                            ConsoleControllerSettingsView(
                                onBack: {
                                    showControllerSettings = false
                                },
                                consoleState: consoleState
                            )
                            .environmentObject(focusManager)
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                        } else {
                            switch navState.activeScreen {
                            case .settings:
                                ConsoleSettingsView(onBack: { navState.navigate(to: .library) },
                                                     onExitDesktop: {
                                                         WindowTransitionManager.switchToDesktop()
                                                     },
                                                     onOpenControllerSettings: {
                                                         showControllerSettings = true
                                                     },
                                                     consoleState: consoleState)
                                    .environmentObject(focusManager)
                                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                            case .favorites:
                                ConsoleFavoritesView(
                                    games: games,
                                    onBack: { navState.navigate(to: .library) },
                                    consoleState: consoleState,
                                    focusManager: focusManager,
                                    onLaunch: onLaunch,
                                    onShowDetails: onShowDetails
                                )
                                .transition(.opacity.combined(with: .move(edge: .trailing)))
                            default:
                                ConsoleLibraryView(
                                    games: games,
                                    consoleState: consoleState,
                                    focusManager: focusManager,
                                    onLaunch: onLaunch,
                                    onShowDetails: onShowDetails
                                )
                                .transition(.opacity.combined(with: .move(edge: .leading)))
                            }
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: navState.activeScreen)
                .animation(.easeInOut(duration: 0.3), value: consoleState.currentScreen)
            }
            .id(consoleState.currentScreen)

            if let game = selectedDetailGame {
                ConsoleGameDetailView(
                    game: game,
                    onLaunch: { onLaunch?(game) },
                    onBack: { selectedDetailGame = nil },
                    mainFocusManager: focusManager
                )
            }


        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .consoleKeyboardNavigation(focusManager: focusManager, consoleState: consoleState)
        .onChange(of: navState.activeScreen) { _, newScreen in
            if let idx = navState.tabs.firstIndex(where: { $0.screen == newScreen }) {
                focusManager.lastTopBarFocusIndex = idx
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .consoleNavigate)) { noti in
            if let screen = noti.object as? ConsoleScreen {
                switch screen {
                case .library:
                    consoleState.showFavoritesOnly = false
                    consoleState.showLibrary()
                case .favorites:
                    consoleState.showLibrary()
                case .settings:
                    consoleState.showSettings()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .consoleConfirm)) { noti in
            if consoleState.currentScreen == .welcome {
                navState.activeScreen = .library
                consoleState.showLibrary()
                return
            }
            guard let sectionRaw = noti.userInfo?["section"] as? Int,
                  let section = ConsoleSection(rawValue: sectionRaw),
                  section == .topBar,
                  let index = noti.userInfo?["index"] as? Int,
                  index < navState.tabs.count
            else { return }
            let tab = navState.tabs[index]
            navState.navigate(to: tab.screen)
        }
        .onReceive(NotificationCenter.default.publisher(for: .consoleMenu)) { _ in
            consoleState.showWelcome()
            focusManager.lastTopBarFocusIndex = 0
        }
        .onAppear {
            consoleState.currentScreen = .welcome
            navState.activeScreen = .library
            consoleState.startAutoTransition(after: 8)
            ControllerNavigationSystem.shared.activate(focusManager: focusManager)
            // Fallback: Controller werden manchmal erst später discovered
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                ControllerNavigationSystem.shared.activate(focusManager: focusManager)
            }
        }
    }
}

#Preview("Console Mode") {
    ConsoleMainView()
        .frame(width: 1280, height: 720)
        .environmentObject(ConsoleNavState())
        .environmentObject(ConsoleFocusManager())
}
