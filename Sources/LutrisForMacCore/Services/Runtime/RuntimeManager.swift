import Foundation
import AppKit

// MARK: - RuntimeManager

@MainActor
public final class RuntimeManager: ObservableObject {
    public static let shared = RuntimeManager()

    @Published public var isHealthOK = true
    @Published public var lastHealthMessage: String?
    @Published public var apiPort: UInt16 = 9876

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

    public func startAll() {
        guard !hasStarted else { return }
        hasStarted = true

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

                    if let game = GameRepository.game(for: gameID) {
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

    public func startGameRuntime(osdEnabled: Bool = true) {
        if osdEnabled {
            OSDBridge.show?()
        }
    }

    public func stopGameRuntime() {
        OSDBridge.hide?()
        RuntimeAPI.shared.stop()
    }

    public func ensureAPIServer() {
        guard !RuntimeAPI.shared.isRunning else { return }
        RuntimeAPI.shared.port = apiPort
        RuntimeAPI.shared.start()
    }

    public func runPreLaunch(game: Game) {
        guard !game.preLaunchScript.isEmpty else { return }
        ensureAPIServer()
        RuntimeAPI.shared.runPreLaunchScript(game.preLaunchScript, gameName: game.name)
    }

    public func stopAll() {
        hasStarted = false
        RuntimeAPI.shared.stop()
        observationTokens.forEach { NotificationCenter.default.removeObserver($0) }
        observationTokens.removeAll()
    }

    // MARK: - Health-Check

    public func checkHealth(game: Game) -> Bool {
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

public extension Notification.Name {
    static let launchGame = Notification.Name("launchGame")
    static let importGameConfig = Notification.Name("importGameConfig")
}
