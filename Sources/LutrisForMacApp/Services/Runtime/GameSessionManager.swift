import Foundation
import AppKit

// MARK: - Game Session

struct GameSession: Identifiable {
    let id = UUID()
    let gameID: UUID
    let gameName: String
    let coverURL: String
    let startTime = Date()
    var watchedPIDs: Set<Int32>
    var watchedNames: Set<String>
    var exitedPIDs: Set<Int32> = []
    var childPIDs: Set<Int32> = []

    var isActive: Bool {
        let remaining = watchedPIDs.subtracting(exitedPIDs)
        return !remaining.isEmpty
    }

    mutating func addPID(_ pid: Int32) { watchedPIDs.insert(pid) }
    mutating func markExited(_ pid: Int32) { exitedPIDs.insert(pid) }

    /// Discover child processes via pgrep for all watched PIDs
    mutating func discoverChildren() {
        for pid in watchedPIDs.subtracting(exitedPIDs) {
            let children = Self.childPIDs(of: pid)
            for c in children where !watchedPIDs.contains(c) {
                watchedPIDs.insert(c)
                childPIDs.insert(c)
            }
        }
    }

    private static func childPIDs(of parent: Int32) -> [Int32] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-o", "pid=", "--ppid", "\(parent)"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        guard (try? task.run()) != nil else { return [] }
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return output.split(separator: "\n").compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
    }
}

// MARK: - Session Manager

@MainActor
final class GameSessionManager: ObservableObject {
    static let shared = GameSessionManager()

    @Published private(set) var activeSessions: [GameSession] = []

    private var monitoringTasks: [UUID: Task<Void, Never>] = [:]
    private let monitorInterval: UInt64 = 2_000_000_000 // 2 seconds

    private init() {}

    // MARK: - Session Lifecycle

    /// Start a new game session: sets Discord RPC + begins PID monitoring.
    /// - Returns: session ID (store for later adding PIDs or ending manually)
    @discardableResult
    func startSession(gameID: UUID, gameName: String, coverURL: String, pids: [Int32] = [], names: [String] = []) -> UUID {
        var session = GameSession(
            gameID: gameID,
            gameName: gameName,
            coverURL: coverURL,
            watchedPIDs: Set(pids),
            watchedNames: Set(names)
        )

        // If no PIDs yet but names provided, try to resolve them now
        if pids.isEmpty {
            for name in names {
                if let pid = resolvePID(name: name) {
                    session.addPID(pid)
                }
            }
        }

        let sid = session.id
        activeSessions.append(session)

        // Set Discord presence (per game runtimeSettings)
        let gameInLibrary = GameLibraryViewModel.shared.games.first(where: { $0.id == gameID })
        if gameInLibrary?.runtimeSettings.discordRPC != false {
            DesktopIntegrationManager.shared.updateDiscordPresence(
                gameName: gameName,
                coverURL: coverURL
            )
        }

        // Start monitoring loop
        let task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: self?.monitorInterval ?? 2_000_000_000)
                self?.pollSession(sid)
            }
        }
        monitoringTasks[sid] = task

        return sid
    }

    /// Add a PID to an active session (e.g., after discovering the game exe as child of wine).
    func addPID(_ pid: Int32, sessionID: UUID) {
        guard let idx = activeSessions.firstIndex(where: { $0.id == sessionID }) else { return }
        activeSessions[idx].addPID(pid)
    }

    /// Add a process name to watch (resolved via pgrep on each poll).
    func addName(_ name: String, sessionID: UUID) {
        guard let idx = activeSessions.firstIndex(where: { $0.id == sessionID }) else { return }
        activeSessions[idx].watchedNames.insert(name)
    }

    /// Manually end a session (clear RPC, stop monitoring).
    func endSession(_ sessionID: UUID) {
        guard let session = activeSessions.first(where: { $0.id == sessionID }) else { return }
        let playTime = Date().timeIntervalSince(session.startTime)

        monitoringTasks[sessionID]?.cancel()
        monitoringTasks[sessionID] = nil
        activeSessions.removeAll { $0.id == sessionID }

        if activeSessions.isEmpty {
            DesktopIntegrationManager.shared.clearDiscordPresence()
        }

        // Notify for webhook + scripting
        NotificationCenter.default.post(
            name: .gameSessionEnded,
            object: nil,
            userInfo: [
                "gameName": session.gameName,
                "gameID": session.gameID,
                "playTime": playTime,
                "exitCode": 0,
            ]
        )
    }

    // MARK: - Singleton Check

    /// End the session for a specific game (e.g. on launch failure).
    func endSession(for gameID: UUID) {
        if let session = activeSessions.first(where: { $0.gameID == gameID }) {
            endSession(session.id)
        }
    }

    /// Returns true if a session for this gameID is already active.
    func isGameRunning(_ gameID: UUID) -> Bool {
        guard let idx = activeSessions.firstIndex(where: { $0.gameID == gameID }) else { return false }
        let session = activeSessions[idx]
        // Alle PIDs checken — wenn keine mehr lebt, Session aufräumen
        let alivePIDs = session.watchedPIDs.filter { kill($0, 0) == 0 && !session.exitedPIDs.contains($0) }
        if alivePIDs.isEmpty {
            endSession(session.id)
            return false
        }
        return true
    }

    /// End all active sessions and clear Discord RPC.
    func endAllSessions() {
        for (id, task) in monitoringTasks {
            task.cancel()
            monitoringTasks[id] = nil
        }
        activeSessions.removeAll()
        DesktopIntegrationManager.shared.clearDiscordPresence()
    }

    /// Alle aktiven PIDs aus allen Sessions (für OSD-Fenstererkennung).
    var activeGamePIDs: Set<Int32> {
        var pids: Set<Int32> = []
        for session in activeSessions {
            pids.formUnion(session.watchedPIDs.subtracting(session.exitedPIDs))
        }
        return pids
    }

    // MARK: - Polling

    private func pollSession(_ sid: UUID) {
        guard let idx = activeSessions.firstIndex(where: { $0.id == sid }) else { return }

        // Discover children for all watched PIDs
        activeSessions[idx].discoverChildren()

        let session = activeSessions[idx]

        // Check each PID with kill(pid, 0)
        var changed = false
        let pidsCopy = session.watchedPIDs
        for pid in pidsCopy {
            if kill(pid, 0) != 0 {
                activeSessions[idx].markExited(pid)
                changed = true
            }
        }

        // Resolve names to PIDs and add them
        for name in session.watchedNames {
            if let pid = resolvePID(name: name), !session.watchedPIDs.contains(pid) {
                activeSessions[idx].addPID(pid)
                changed = true
            }
        }

        // Check if session ended
        if changed {
            let stillActive = activeSessions[idx].isActive
            if !stillActive {
                endSession(sid)
            }
        }
    }

    /// Resolve a process name to PID using pgrep.
    private func resolvePID(name: String) -> Int32? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-fi", name]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        guard (try? task.run()) != nil else { return nil }
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        let pidStr = output.split(separator: "\n").first?.trimmingCharacters(in: .whitespaces) ?? ""
        return Int32(pidStr)
    }

    // MARK: - Convenience for .app launches

    /// Monitor a native .app after launch via NSWorkspace.
    func monitorApp(named appName: String, sessionID: UUID) {
        // Try to find the app's PID via its .app bundle
        if let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.localizedName?.lowercased() == appName.lowercased() ||
            $0.bundleURL?.lastPathComponent.lowercased() == appName.lowercased()
        }) {
            addPID(app.processIdentifier, sessionID: sessionID)
        } else {
            // Fallback: watch by name
            addName(appName, sessionID: sessionID)
        }
    }
}

// MARK: - DesktopIntegrationManager extension for session-based launch

extension DesktopIntegrationManager {

    /// Launch a game session with Discord RPC + PID monitoring (backward-compatible helper).
    /// Use this from ContentView instead of raw updateDiscordPresence + waitForGameProcess.
    @MainActor
    func launchSession(
        gameID: UUID = UUID(),
        gameName: String,
        coverURL: String,
        pids: [Int32] = [],
        names: [String] = [],
        appBundleName: String? = nil
    ) -> UUID {
        let sid = GameSessionManager.shared.startSession(
            gameID: gameID,
            gameName: gameName,
            coverURL: coverURL,
            pids: pids,
            names: names
        )
        if let appName = appBundleName {
            GameSessionManager.shared.monitorApp(named: appName, sessionID: sid)
        }
        return sid
    }
}
