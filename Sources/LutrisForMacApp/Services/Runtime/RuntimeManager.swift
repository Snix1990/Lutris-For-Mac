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

        // Start API server
        RuntimeAPI.shared.port = apiPort
        RuntimeAPI.shared.start()

        // Observe session ends for webhook + scripting
        observationTokens.append(
            NotificationCenter.default.addObserver(
                forName: .gameSessionEnded,
                object: nil,
                queue: .main
            ) { [weak self] note in
                guard let userInfo = note.userInfo,
                      let gameName = userInfo["gameName"] as? String,
                      let playTime = userInfo["playTime"] as? TimeInterval,
                      let gameID = userInfo["gameID"] as? UUID else { return }
                let exitCode = userInfo["exitCode"] as? Int32 ?? 0

                RuntimeAPI.shared.fireWebhook(
                    gameName: gameName,
                    playTime: playTime,
                    exitCode: exitCode
                )

                let games = GameLibraryViewModel.shared.games
                if let game = games.first(where: { $0.id == gameID }),
                   !game.postExitScript.isEmpty {
                    RuntimeAPI.shared.runPostExitScript(
                        game.postExitScript,
                        gameName: gameName,
                        playTime: playTime
                    )
                }
            }
        )

        observationTokens.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification,
                object: nil,
                queue: .main
            ) { _ in
                RuntimeAPI.shared.stop()
            }
        )
    }

    func stopAll() {
        hasStarted = false
        RuntimeAPI.shared.stop()
        observationTokens.forEach { NotificationCenter.default.removeObserver($0) }
        observationTokens.removeAll()
    }

    // MARK: - Health-Check

    func checkHealth(game: Game) -> Bool {
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

    func runPreLaunch(game: Game) {
        guard !game.preLaunchScript.isEmpty else { return }
        RuntimeAPI.shared.runPreLaunchScript(game.preLaunchScript, gameName: game.name)
    }
}

extension Notification.Name {
    static let gameSessionEnded = Notification.Name("gameSessionEnded")
}
