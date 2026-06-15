import Foundation
import AppKit

// MARK: - RuntimeManager

@MainActor
final class RuntimeManager: ObservableObject {
    static let shared = RuntimeManager()

    @Published var isHealthOK = true
    @Published var lastHealthMessage: String?
    @Published var apiPort: UInt16 = 9876

    private var observationTokens: [NSObjectProtocol] = []
    private var hasStarted = false

    private init() {}

    deinit {
        let tokens = observationTokens
        Task { @MainActor in
            RuntimeAPI.shared.stop()
            tokens.forEach { NotificationCenter.default.removeObserver($0) }
        }
    }

    // MARK: - Lifecycle

    func startAll() {
        guard !hasStarted else { return }
        hasStarted = true

        // Observe session ends for webhook + scripting
        observationTokens.append(
            NotificationCenter.default.addObserver(
                forName: .gameSessionEnded,
                object: nil,
                queue: .main
            ) { [weak self] note in
                Task { @MainActor in
                    self?.stopGameRuntime()
                    guard let userInfo = note.userInfo,
                          let gameName = userInfo["gameName"] as? String,
                          let playTime = userInfo["playTime"] as? TimeInterval,
                          let gameID = userInfo["gameID"] as? UUID else { return }
                    let exitCode = userInfo["exitCode"] as? Int32 ?? 0

                    let games = GameLibraryViewModel.shared.games
                    if let game = games.first(where: { $0.id == gameID }) {
                        if game.runtimeSettings.webhook {
                            RuntimeAPI.shared.fireWebhook(
                                gameName: gameName,
                                playTime: playTime,
                                exitCode: exitCode
                            )
                        }
                        if !game.postExitScript.isEmpty {
                            RuntimeAPI.shared.runPostExitScript(
                                game.postExitScript,
                                gameName: gameName,
                                playTime: playTime
                            )
                        }
                    }
                }
            }
        )

        observationTokens.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification,
                object: nil,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    RuntimeAPI.shared.stop()
                }
            }
        )
    }

    func startGameRuntime(osdEnabled: Bool = true) {
        if OSDManager.shared.settings.enabled && osdEnabled {
            OSDManager.shared.show()
        }
    }

    func stopGameRuntime() {
        OSDManager.shared.hide()
        RuntimeAPI.shared.stop()
    }

    func ensureAPIServer() {
        guard !RuntimeAPI.shared.isRunning else { return }
        RuntimeAPI.shared.port = apiPort
        RuntimeAPI.shared.start()
    }

    func runPreLaunch(game: Game) {
        guard !game.preLaunchScript.isEmpty else { return }
        ensureAPIServer()
        RuntimeAPI.shared.runPreLaunchScript(game.preLaunchScript, gameName: game.name)
    }

    func stopAll() {
        hasStarted = false
        RuntimeAPI.shared.stop()
        observationTokens.forEach { NotificationCenter.default.removeObserver($0) }
        observationTokens.removeAll()
    }

    // MARK: - Health-Check

    func checkHealth(game: Game) -> Bool {
        guard game.runtimeSettings.healthCheck else { return true }
        let result = UpdateManager.shared.healthCheck(game: game)
        switch result {
        case .success:
            isHealthOK = true
            lastHealthMessage = nil
            return true
        case .warning(let msg):
            isHealthOK = true
            lastHealthMessage = msg
            NotificationManager.warning(title: game.name, message: msg, duration: 4)
            return true
        case .failure(let msg):
            isHealthOK = false
            lastHealthMessage = msg
            NotificationManager.error(title: game.name, message: msg, duration: 6)
            return false
        }
    }

}

extension Notification.Name {
    static let gameSessionEnded = Notification.Name("gameSessionEnded")
}
