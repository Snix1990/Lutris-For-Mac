import Foundation
import AppKit

// MARK: - Game Session

public struct GameSession: Identifiable {
    public let id = UUID()
    public let gameID: UUID
    public let gameName: String
    public let coverURL: String
    public let startTime = Date()
    public var watchedPIDs: Set<Int32>
    public var watchedNames: Set<String>
    public var exitedPIDs: Set<Int32> = []
    public var childPIDs: Set<Int32> = []

    public var isActive: Bool {
        let remaining = watchedPIDs.subtracting(exitedPIDs)
        return !remaining.isEmpty
    }

    public mutating func addPID(_ pid: Int32) { watchedPIDs.insert(pid) }
    public mutating func markExited(_ pid: Int32) { exitedPIDs.insert(pid) }

    public mutating func discoverChildren() {
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
public final class GameSessionManager: ObservableObject {
    public static let shared = GameSessionManager()

    @Published public private(set) var activeSessions: [GameSession] = []

    private var monitoringTasks: [UUID: Task<Void, Never>] = [:]
    private let monitorInterval: UInt64 = 2_000_000_000

    private init() {}

    // MARK: - Session Lifecycle

    @discardableResult
    public func startSession(gameID: UUID, gameName: String, coverURL: String, pids: [Int32] = [], names: [String] = [], discordRPCEnabled: Bool = true) -> UUID {
        var session = GameSession(
            gameID: gameID,
            gameName: gameName,
            coverURL: coverURL,
            watchedPIDs: Set(pids),
            watchedNames: Set(names)
        )

        if pids.isEmpty {
            for name in names {
                if let pid = resolvePID(name: name) {
                    session.addPID(pid)
                }
            }
        }

        let sid = session.id
        activeSessions.append(session)

        if discordRPCEnabled {
            DesktopIntegrationManager.shared.updateDiscordPresence(
                gameName: gameName,
                coverURL: coverURL
            )
        }

        let task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: self?.monitorInterval ?? 2_000_000_000)
                self?.pollSession(sid)
            }
        }
        monitoringTasks[sid] = task

        return sid
    }

    public func addPID(_ pid: Int32, sessionID: UUID) {
        guard let idx = activeSessions.firstIndex(where: { $0.id == sessionID }) else { return }
        activeSessions[idx].addPID(pid)
    }

    public func addName(_ name: String, sessionID: UUID) {
        guard let idx = activeSessions.firstIndex(where: { $0.id == sessionID }) else { return }
        activeSessions[idx].watchedNames.insert(name)
    }

    public func endSession(_ sessionID: UUID) {
        guard let session = activeSessions.first(where: { $0.id == sessionID }) else { return }
        let playTime = Date().timeIntervalSince(session.startTime)

        monitoringTasks[sessionID]?.cancel()
        monitoringTasks[sessionID] = nil
        activeSessions.removeAll { $0.id == sessionID }

        if activeSessions.isEmpty {
            DesktopIntegrationManager.shared.clearDiscordPresence()
        }

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

    public func endSession(for gameID: UUID) {
        if let session = activeSessions.first(where: { $0.gameID == gameID }) {
            endSession(session.id)
        }
    }

    public func isGameRunning(_ gameID: UUID) -> Bool {
        guard let idx = activeSessions.firstIndex(where: { $0.gameID == gameID }) else { return false }
        let session = activeSessions[idx]
        let alivePIDs = session.watchedPIDs.filter { kill($0, 0) == 0 && !session.exitedPIDs.contains($0) }
        if alivePIDs.isEmpty {
            endSession(session.id)
            return false
        }
        return true
    }

    public func endAllSessions() {
        for (id, task) in monitoringTasks {
            task.cancel()
            monitoringTasks[id] = nil
        }
        activeSessions.removeAll()
        DesktopIntegrationManager.shared.clearDiscordPresence()
    }

    public var activeGamePIDs: Set<Int32> {
        var pids: Set<Int32> = []
        for session in activeSessions {
            pids.formUnion(session.watchedPIDs.subtracting(session.exitedPIDs))
        }
        return pids
    }

    // MARK: - Polling

    private func pollSession(_ sid: UUID) {
        guard let idx = activeSessions.firstIndex(where: { $0.id == sid }) else { return }

        activeSessions[idx].discoverChildren()

        let session = activeSessions[idx]

        var changed = false
        let pidsCopy = session.watchedPIDs
        for pid in pidsCopy {
            if kill(pid, 0) != 0 {
                activeSessions[idx].markExited(pid)
                changed = true
            }
        }

        for name in session.watchedNames {
            if let pid = resolvePID(name: name), !session.watchedPIDs.contains(pid) {
                activeSessions[idx].addPID(pid)
                changed = true
            }
        }

        if changed {
            let stillActive = activeSessions[idx].isActive
            if !stillActive {
                endSession(sid)
            }
        }
    }

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

    public func monitorApp(named appName: String, sessionID: UUID) {
        if let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.localizedName?.lowercased() == appName.lowercased() ||
            $0.bundleURL?.lastPathComponent.lowercased() == appName.lowercased()
        }) {
            addPID(app.processIdentifier, sessionID: sessionID)
        } else {
            addName(appName, sessionID: sessionID)
        }
    }
}

// MARK: - Notification Names

public extension Notification.Name {
    static let gameSessionEnded = Notification.Name("gameSessionEnded")
}

// MARK: - DesktopIntegrationManager extension for session-based launch

extension DesktopIntegrationManager {

    @MainActor
    public func launchSession(
        gameID: UUID = UUID(),
        gameName: String,
        coverURL: String,
        pids: [Int32] = [],
        names: [String] = [],
        appBundleName: String? = nil,
        discordRPCEnabled: Bool = true
    ) -> UUID {
        let sid = GameSessionManager.shared.startSession(
            gameID: gameID,
            gameName: gameName,
            coverURL: coverURL,
            pids: pids,
            names: names,
            discordRPCEnabled: discordRPCEnabled
        )
        if let appName = appBundleName {
            GameSessionManager.shared.monitorApp(named: appName, sessionID: sid)
        }
        return sid
    }
}
