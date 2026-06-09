import Foundation
import AppKit

// MARK: - Models

/// Represents a single save file or folder found on disk.
struct SaveFileInfo: Identifiable, Codable, Equatable {
    var id = UUID()
    let relativePath: String       // relative to the save root
    let isDirectory: Bool
    let fileSize: Int64            // bytes
    let modificationDate: Date

    var fileName: String { (relativePath as NSString).lastPathComponent }
}

/// A snapshot = one backup of all saves for a game at a point in time.
struct SaveSnapshot: Identifiable, Codable, Equatable {
    var id = UUID()
    let gameID: UUID
    let gameName: String
    let runner: String
    let timestamp: Date
    let label: String              // user-visible name (e.g. "Before Update", "2025-01-15")
    let files: [SaveFileInfo]
    let totalSize: Int64

    static func empty(gameID: UUID, gameName: String, runner: String, label: String = "") -> SaveSnapshot {
        SaveSnapshot(
            gameID: gameID,
            gameName: gameName,
            runner: runner,
            timestamp: Date(),
            label: label,
            files: [],
            totalSize: 0
        )
    }
}

/// Conflict between local and remote snapshot.
struct SaveConflict: Identifiable {
    let id = UUID()
    let gameID: UUID
    let localSnapshot: SaveSnapshot
    let remoteSnapshot: SaveSnapshot
    var resolution: Resolution?

    enum Resolution: String, Codable {
        case useLocal
        case useRemote
        case keepBoth
    }

    var isResolved: Bool { resolution != nil }
}

// MARK: - Runner Save Paths

/// Describes where a given runner stores its saves.
struct RunnerSavePath {
    let runnerName: String
    let pathPatterns: [String]     // paths with ~ expansion, globs supported
    let isDirectory: Bool
    let description: String

    static let known: [RunnerSavePath] = [
        // --- Wine / CrossOver ---
        RunnerSavePath(runnerName: "Wine", pathPatterns: [
            "~/Library/Application Support/Wine/prefixes/*/drive_c/users/*/AppData/Local",
            "~/Library/Application Support/Wine/prefixes/*/drive_c/users/*/AppData/Roaming",
            "~/Library/Application Support/Wine/prefixes/*/drive_c/users/*/Documents/My Games",
            "~/Library/Application Support/Wine/prefixes/*/drive_c/ProgramData",
        ], isDirectory: true, description: "Wine AppData & Documents"),

        RunnerSavePath(runnerName: "CrossOver", pathPatterns: [
            "~/Library/Application Support/CrossOver/Bottles/*/drive_c/users/*/AppData/Local",
            "~/Library/Application Support/CrossOver/Bottles/*/drive_c/users/*/AppData/Roaming",
            "~/Library/Application Support/CrossOver/Bottles/*/drive_c/users/*/Documents/My Games",
            "~/Library/Application Support/CrossOver/Bottles/*/drive_c/ProgramData",
        ], isDirectory: true, description: "CrossOver AppData & Documents"),

        RunnerSavePath(runnerName: "Whisky", pathPatterns: [
            "~/Library/Containers/com.whisky.Whisky/Data/Programs/*/drive_c/users/*/AppData/Local",
            "~/Library/Containers/com.whisky.Whisky/Data/Programs/*/drive_c/users/*/Documents/My Games",
        ], isDirectory: true, description: "Whisky Bottle saves"),

        RunnerSavePath(runnerName: "Kegworks", pathPatterns: [
            "~/Library/Application Support/org.winehq.wine/prefixes/*/drive_c/users/*/AppData/Local",
            "~/Library/Application Support/org.winehq.wine/prefixes/*/drive_c/users/*/Documents/My Games",
        ], isDirectory: true, description: "Kegworks Wine saves"),

        // --- Steam (native macOS) ---
        RunnerSavePath(runnerName: "Steam", pathPatterns: [
            "~/Library/Application Support/Steam/steamapps/common/*",
            "~/Library/Application Support/Steam/userdata/*",
        ], isDirectory: true, description: "Steam userdata + game folders"),

        // --- Retro / Nintendo ---
        RunnerSavePath(runnerName: "Dolphin", pathPatterns: [
            "~/Library/Application Support/Dolphin/GC",
            "~/Library/Application Support/Dolphin/Wii",
            "~/Library/Application Support/Dolphin/StateSaves",
        ], isDirectory: true, description: "Dolphin GC/Wii saves + states"),

        RunnerSavePath(runnerName: "Citra", pathPatterns: [
            "~/Library/Application Support/Citra/sdmc",
            "~/Library/Application Support/Citra/nand",
        ], isDirectory: true, description: "Citra 3DS saves"),

        RunnerSavePath(runnerName: "Ryujinx", pathPatterns: [
            "~/Library/Application Support/Ryujinx/bis/user/save",
            "~/Library/Application Support/Ryujinx/games/*",
        ], isDirectory: true, description: "Ryujinx Switch saves"),

        RunnerSavePath(runnerName: "MelonDS", pathPatterns: [
            "~/Library/Application Support/melonDS/battery",
            "~/Library/Application Support/melonDS/savestates",
        ], isDirectory: true, description: "melonDS saves + states"),

        // --- PlayStation ---
        RunnerSavePath(runnerName: "PCSX2", pathPatterns: [
            "~/Library/Application Support/PCSX2/memcards",
            "~/Library/Application Support/PCSX2/savestates",
        ], isDirectory: true, description: "PCSX2 memory cards + states"),

        RunnerSavePath(runnerName: "RPCS3", pathPatterns: [
            "~/Library/Application Support/rpcs3/dev_hdd0/home/*/savedata",
            "~/Library/Application Support/rpcs3/dev_hdd0/home/*/savedata_backup",
        ], isDirectory: true, description: "RPCS3 PS3 savedata"),

        RunnerSavePath(runnerName: "DuckStation", pathPatterns: [
            "~/Library/Application Support/DuckStation/memcards",
            "~/Library/Application Support/DuckStation/savestates",
        ], isDirectory: true, description: "DuckStation memory cards + states"),

        // --- Sega ---
        RunnerSavePath(runnerName: "Flycast", pathPatterns: [
            "~/Library/Application Support/flycast/data",
        ], isDirectory: true, description: "Flycast VMU saves"),

        // --- Handheld ---
        RunnerSavePath(runnerName: "PPSSPP", pathPatterns: [
            "~/Library/Application Support/PPSSPP/memstick/PSP/SAVEDATA",
            "~/Library/Application Support/PPSSPP/state",
        ], isDirectory: true, description: "PPSSPP PSP saves + states"),

        // --- Multi-System ---
        RunnerSavePath(runnerName: "RetroArch", pathPatterns: [
            "~/Library/Application Support/RetroArch/saves",
            "~/Library/Application Support/RetroArch/states",
            "~/Library/Application Support/RetroArch/playlists",
        ], isDirectory: true, description: "RetroArch saves + states"),

        RunnerSavePath(runnerName: "OpenEmu", pathPatterns: [
            "~/Library/Application Support/OpenEmu/Game Library/Saves/*",
        ], isDirectory: true, description: "OpenEmu saves"),

        // --- DOS ---
        RunnerSavePath(runnerName: "DOSBox", pathPatterns: [
            "~/Library/Preferences/DOSBox*.conf",
        ], isDirectory: false, description: "DOSBox configs"),

        // --- ScummVM ---
        RunnerSavePath(runnerName: "ScummVM", pathPatterns: [
            "~/Library/Application Support/ScummVM/Saves",
        ], isDirectory: true, description: "ScummVM save files"),

        // --- MAME ---
        RunnerSavePath(runnerName: "MAME", pathPatterns: [
            "~/Library/Application Support/mame/cfg",
            "~/Library/Application Support/mame/nvram",
            "~/Library/Application Support/mame/sta",
        ], isDirectory: true, description: "MAME configs + NVRAM + states"),
    ]
}

// MARK: - Cloud Provider Protocol

@MainActor
protocol CloudSaveProvider: AnyObject {
    var name: String { get }
    var isAvailable: Bool { get }

    /// Upload a snapshot's files to the cloud.
    func upload(snapshot: SaveSnapshot, files: [URL]) async throws

    /// Download a snapshot's files from the cloud.
    func download(snapshot: SaveSnapshot, to destination: URL) async throws

    /// List all snapshots stored in the cloud for a game.
    func listSnapshots(gameID: UUID) async throws -> [SaveSnapshot]

    /// Delete a snapshot from the cloud.
    func delete(snapshot: SaveSnapshot) async throws
}

// MARK: - Cloud Save Manager

@MainActor
final class CloudSaveManager: ObservableObject {
    static let shared = CloudSaveManager()

    // MARK: - Published State

    @Published private(set) var backups: [SaveSnapshot] = []
    @Published private(set) var detectedSaves: [SaveFileInfo] = []
    @Published private(set) var conflicts: [SaveConflict] = []
    @Published private(set) var isScanning = false
    @Published private(set) var isSyncing = false
    @Published var cloudProvider: CloudSaveProvider? {
        didSet { loadBackups() }
    }

    // MARK: - Storage

    private let fileManager = FileManager.default
    private let storageURL: URL
    private let maxLocalBackups = 5
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let manifestFileName = "saves.json"

    private init() {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("LutrisForMac", isDirectory: true)
            .appendingPathComponent("CloudSaves", isDirectory: true)
        storageURL = base
        try? fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        cloudProvider = providerForType(CloudSyncSettingsManager.shared.settings.providerType)
    }

    private func providerForType(_ type: CloudProviderType) -> CloudSaveProvider {
        switch type {
        case .appleCloud:
            return AppleCloudProvider()
        default:
            return WebDAVProvider()
        }
    }

    // MARK: - Save Detection

    /// Scan known runner save paths for a specific game.
    /// - Returns: list of file metadata found
    func detectSaves(for game: Game) async throws -> [SaveFileInfo] {
        isScanning = true
        defer { isScanning = false }

        // Custom save path override
        if !game.customSavePath.isEmpty {
            let expanded = (game.customSavePath as NSString).expandingTildeInPath
            let url = URL(fileURLWithPath: expanded)
            if fileManager.fileExists(atPath: url.path) {
                let files = try scanFiles(at: url)
                detectedSaves = files
                return files
            }
        }

        let patterns = RunnerSavePath.known
            .filter { $0.runnerName.lowercased() == game.runner.lowercased() }
            .flatMap { $0.pathPatterns }

        guard !patterns.isEmpty else {
            // Fallback: try to find save dirs near the install path
            return try await scanFallbackPaths(game: game)
        }

        var results: [SaveFileInfo] = []
        for pattern in patterns {
            let expanded = (pattern as NSString).expandingTildeInPath
            let resolved = resolveGlob(expanded)
            for url in resolved {
                let files = try scanFiles(at: url)
                results.append(contentsOf: files)
            }
        }

        detectedSaves = results
        return results
    }

    private func scanFallbackPaths(game: Game) async throws -> [SaveFileInfo] {
        let installURL = URL(fileURLWithPath: game.installPath)
        let candidates = [
            installURL.deletingLastPathComponent().appendingPathComponent("Saves"),
            installURL.deletingLastPathComponent().appendingPathComponent("saves"),
            installURL.deletingLastPathComponent().appendingPathComponent("SaveData"),
            installURL.deletingLastPathComponent().appendingPathComponent("save"),
            installURL.appendingPathComponent("Saves"),
        ]
        var results: [SaveFileInfo] = []
        for url in candidates {
            guard fileManager.fileExists(atPath: url.path) else { continue }
            let files = try scanFiles(at: url)
            results.append(contentsOf: files)
        }
        return results
    }

    private func scanFiles(at url: URL) throws -> [SaveFileInfo] {
        guard fileManager.fileExists(atPath: url.path) else { return [] }

        let resourceKeys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        let isDir = (try url.resourceValues(forKeys: Set([.isDirectoryKey]))).isDirectory ?? false

        if isDir {
            guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: resourceKeys) else { return [] }
            var results: [SaveFileInfo] = []
            for case let fileURL as URL in enumerator {
                let res = try fileURL.resourceValues(forKeys: Set(resourceKeys))
                let relPath = fileURL.path.replacingOccurrences(of: url.path + "/", with: "")
                results.append(SaveFileInfo(
                    relativePath: relPath,
                    isDirectory: res.isDirectory ?? false,
                    fileSize: Int64(res.fileSize ?? 0),
                    modificationDate: res.contentModificationDate ?? Date()
                ))
            }
            return results
        } else {
            let res = try url.resourceValues(forKeys: Set(resourceKeys))
            return [SaveFileInfo(
                relativePath: url.lastPathComponent,
                isDirectory: false,
                fileSize: Int64(res.fileSize ?? 0),
                modificationDate: res.contentModificationDate ?? Date()
            )]
        }
    }

    // MARK: - Backup / Restore

    /// Create a local backup snapshot of the game's saves.
    @discardableResult
    func createBackup(for game: Game, label: String = "") async throws -> SaveSnapshot {
        let saves = try await detectSaves(for: game)
        let gameDir = gameDirURL(gameID: game.id)
        let snapshotDir = gameDir.appendingPathComponent("backup_\(ISO8601DateFormatter().string(from: Date()))")
        try fileManager.createDirectory(at: snapshotDir, withIntermediateDirectories: true)

        var totalSize: Int64 = 0
        var copiedFiles: [SaveFileInfo] = []

        for save in saves {
            guard let sourceURL = resolveSourceURL(for: save, game: game) else { continue }
            let dest = snapshotDir.appendingPathComponent(save.relativePath)

            if save.isDirectory {
                try? fileManager.removeItem(at: dest)
                try fileManager.createDirectory(at: dest, withIntermediateDirectories: true)
                try fileManager.copyItem(at: sourceURL, to: dest)
            } else {
                try? fileManager.removeItem(at: dest)
                try fileManager.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileManager.copyItem(at: sourceURL, to: dest)
            }
            totalSize += save.fileSize
            copiedFiles.append(save)
        }

        let snapshot = SaveSnapshot(
            id: UUID(),
            gameID: game.id,
            gameName: game.name,
            runner: game.runner,
            timestamp: Date(),
            label: label.isEmpty ? formattedDate(Date()) : label,
            files: copiedFiles,
            totalSize: totalSize
        )

        // Save manifest
        let manifestURL = snapshotDir.appendingPathComponent(manifestFileName)
        let data = try encoder.encode(snapshot)
        try data.write(to: manifestURL)

        // Re-index backups
        loadBackups()

        // Enforce max backups
        enforceBackupLimit(gameID: game.id)

        let sizeStr = ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
        NotificationManager.success(
            title: game.name,
            message: "Backup created – \(copiedFiles.count) files, \(sizeStr)",
            duration: 3
        )

        return snapshot
    }

    /// Restore a backup snapshot to the original save locations.
    func restoreBackup(_ snapshot: SaveSnapshot, game: Game) async throws {
        guard let snapshotDir = snapshotDirURL(snapshot) else {
            throw CloudSaveError.snapshotNotFound
        }

        for file in snapshot.files {
            guard let destURL = resolveSourceURL(for: file, game: game) else { continue }
            let sourceURL = snapshotDir.appendingPathComponent(file.relativePath)
            guard fileManager.fileExists(atPath: sourceURL.path) else { continue }

            if file.isDirectory {
                try? fileManager.removeItem(at: destURL)
                try fileManager.copyItem(at: sourceURL, to: destURL)
            } else {
                try? fileManager.removeItem(at: destURL)
                try fileManager.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileManager.copyItem(at: sourceURL, to: destURL)
            }
        }

        NotificationManager.success(
            title: snapshot.gameName,
            message: "Saves restored from: \(snapshot.label)",
            duration: 4
        )
    }

    /// Delete a local backup.
    func deleteBackup(_ snapshot: SaveSnapshot) {
        guard let dir = snapshotDirURL(snapshot) else { return }
        try? fileManager.removeItem(at: dir)
        loadBackups()
    }

    /// List all local backups for a game.
    func listBackups(for gameID: UUID) -> [SaveSnapshot] {
        backups.filter { $0.gameID == gameID }
            .sorted { $0.timestamp > $1.timestamp }
    }

    // MARK: - Conflict Detection

    /// Compare local and remote snapshots and detect conflicts.
    func detectConflicts(gameID: UUID, remote: SaveSnapshot) {
        let localBackups = listBackups(for: gameID)

        for local in localBackups {
            if local.id == remote.id { continue }
            let timeDiff = abs(local.timestamp.timeIntervalSince(remote.timestamp))
            if timeDiff > 60 && local.files != remote.files {
                let conflict = SaveConflict(
                    gameID: gameID,
                    localSnapshot: local,
                    remoteSnapshot: remote
                )
                if !conflicts.contains(where: { $0.id == conflict.id }) {
                    conflicts.append(conflict)
                }
            }
        }
    }

    /// Resolve a conflict with the given strategy.
    func resolveConflict(_ conflict: SaveConflict, resolution: SaveConflict.Resolution, game: Game? = nil) async throws {
        guard let idx = conflicts.firstIndex(where: { $0.id == conflict.id }) else { return }

        switch resolution {
        case .useLocal:
            if let provider = cloudProvider {
                try? await provider.delete(snapshot: conflict.remoteSnapshot)
            }
            NotificationManager.info(
                title: "Conflict Resolved",
                message: "Kept local snapshot, removed remote",
                duration: 3
            )

        case .useRemote:
            if let g = game {
                try await restoreBackup(conflict.remoteSnapshot, game: g)
                // Re-upload restored remote as a fresh local backup
                if let provider = cloudProvider, let dir = snapshotDirURL(conflict.remoteSnapshot) {
                    var fileURLs: [URL] = []
                    for file in conflict.remoteSnapshot.files {
                        let url = dir.appendingPathComponent(file.relativePath)
                        if fileManager.fileExists(atPath: url.path) { fileURLs.append(url) }
                    }
                    try? await provider.upload(snapshot: conflict.remoteSnapshot, files: fileURLs)
                }
            }
            NotificationManager.info(
                title: "Conflict Resolved",
                message: "Restored remote snapshot locally",
                duration: 3
            )

        case .keepBoth:
            NotificationManager.info(
                title: "Conflict Resolved",
                message: "Kept both local and remote versions",
                duration: 3
            )
        }

        conflicts[idx].resolution = resolution
    }

    // MARK: - Cloud Sync

    /// Full sync for a single game: backup → upload missing → download missing → resolve conflicts.
    func syncGame(game: Game) async throws {
        guard let provider = cloudProvider, CloudSyncSettingsManager.shared.settings.syncEnabled else {
            throw CloudSaveError.noProvider
        }
        isSyncing = true
        defer { isSyncing = false }

        // 1. Create a fresh backup first
        try await createBackup(for: game, label: "Before Sync (\(formattedDate(Date())))")

        // 2. Upload local snapshots not yet in cloud
        let remoteSnapshots = try await provider.listSnapshots(gameID: game.id)
        let remoteIDs = Set(remoteSnapshots.map(\.id))

        let localToUpload = listBackups(for: game.id).filter { !remoteIDs.contains($0.id) }
        for snapshot in localToUpload {
            NotificationManager.info(title: game.name, message: "Uploading – \(snapshot.label)", duration: 1.5)
            guard let dir = snapshotDirURL(snapshot) else { continue }
            var fileURLs: [URL] = []
            for file in snapshot.files {
                let url = dir.appendingPathComponent(file.relativePath)
                if fileManager.fileExists(atPath: url.path) {
                    fileURLs.append(url)
                }
            }
            try await provider.upload(snapshot: snapshot, files: fileURLs)
        }

        // 3. Download remote snapshots not yet local
        let localIDs = Set(listBackups(for: game.id).map(\.id))
        for remote in remoteSnapshots where !localIDs.contains(remote.id) {
            NotificationManager.info(title: game.name, message: "Downloading – \(remote.label)", duration: 1.5)
            let gameDir = gameDirURL(gameID: game.id)
            let snapshotDir = gameDir.appendingPathComponent("backup_remote_\(remote.id.uuidString.prefix(8))")
            try fileManager.createDirectory(at: snapshotDir, withIntermediateDirectories: true)
            try await provider.download(snapshot: remote, to: snapshotDir)

            let manifestURL = snapshotDir.appendingPathComponent(manifestFileName)
            let data = try encoder.encode(remote)
            try data.write(to: manifestURL)
        }
        loadBackups()

        // 4. Detect conflicts
        for remote in remoteSnapshots {
            detectConflicts(gameID: game.id, remote: remote)
        }

        if !conflicts.isEmpty {
            NotificationManager.warning(
                title: game.name,
                message: "\(conflicts.count) save conflict(s) detected – review in settings",
                duration: 5
            )
        } else {
            NotificationManager.success(
                title: game.name,
                message: "Saves synced (\(localToUpload.count) uploaded, \(remoteSnapshots.count) remote)",
                duration: 3
            )
        }
    }

    /// Sync all games that have local backups.
    func syncAll(games: [Game]) async throws {
        guard let provider = cloudProvider, CloudSyncSettingsManager.shared.settings.syncEnabled else {
            throw CloudSaveError.noProvider
        }
        isSyncing = true
        defer { isSyncing = false }

        var uploaded = 0
        var downloaded = 0

        for game in games {
            let localBackups = listBackups(for: game.id)
            guard !localBackups.isEmpty else { continue }

            NotificationManager.info(title: game.name, message: "Syncing saves...", duration: 1.5)

            // Upload missing
            let remoteSnapshots = try? await provider.listSnapshots(gameID: game.id)
            let remoteIDs = Set(remoteSnapshots?.map(\.id) ?? [])
            for snapshot in localBackups where !remoteIDs.contains(snapshot.id) {
                guard let dir = snapshotDirURL(snapshot) else { continue }
                var fileURLs: [URL] = []
                for file in snapshot.files {
                    let url = dir.appendingPathComponent(file.relativePath)
                    if fileManager.fileExists(atPath: url.path) {
                        fileURLs.append(url)
                    }
                }
                try await provider.upload(snapshot: snapshot, files: fileURLs)
                uploaded += 1
            }

            // Download missing
            guard let remotes = remoteSnapshots else { continue }
            let localIDs = Set(localBackups.map(\.id))
            for remote in remotes where !localIDs.contains(remote.id) {
                let gameDir = gameDirURL(gameID: game.id)
                let snapshotDir = gameDir.appendingPathComponent("backup_remote_\(remote.id.uuidString.prefix(8))")
                try fileManager.createDirectory(at: snapshotDir, withIntermediateDirectories: true)
                try await provider.download(snapshot: remote, to: snapshotDir)

                let manifestURL = snapshotDir.appendingPathComponent(manifestFileName)
                let data = try encoder.encode(remote)
                try data.write(to: manifestURL)
                downloaded += 1
            }
        }
        loadBackups()

        NotificationManager.success(
            title: "Cloud Sync",
            message: "\(uploaded) uploaded, \(downloaded) downloaded",
            duration: 3
        )
    }

    /// Upload all local backups for a game to the cloud.
    func uploadToCloud(gameID: UUID) async throws {
        guard let provider = cloudProvider else { throw CloudSaveError.noProvider }
        isSyncing = true
        defer { isSyncing = false }

        let localBackups = listBackups(for: gameID)
        for snapshot in localBackups {
            guard let dir = snapshotDirURL(snapshot) else { continue }
            var fileURLs: [URL] = []
            for file in snapshot.files {
                let url = dir.appendingPathComponent(file.relativePath)
                if fileManager.fileExists(atPath: url.path) {
                    fileURLs.append(url)
                }
            }
            try await provider.upload(snapshot: snapshot, files: fileURLs)
        }

        NotificationManager.success(
            title: "Cloud Sync",
            message: "\(localBackups.count) snapshot(s) uploaded",
            duration: 3
        )
    }

    /// Download remote snapshots for a game and create local backups.
    func downloadFromCloud(gameID: UUID, gameName: String, runner: String) async throws {
        guard let provider = cloudProvider else { throw CloudSaveError.noProvider }
        isSyncing = true
        defer { isSyncing = false }

        let remoteSnapshots = try await provider.listSnapshots(gameID: gameID)
        for remote in remoteSnapshots {
            let localBackups = listBackups(for: gameID)
            guard !localBackups.contains(where: { $0.id == remote.id }) else { continue }

            let gameDir = gameDirURL(gameID: gameID)
            let snapshotDir = gameDir.appendingPathComponent("backup_remote_\(remote.id.uuidString.prefix(8))")
            try fileManager.createDirectory(at: snapshotDir, withIntermediateDirectories: true)

            try await provider.download(snapshot: remote, to: snapshotDir)

            let manifestURL = snapshotDir.appendingPathComponent(manifestFileName)
            let data = try encoder.encode(remote)
            try data.write(to: manifestURL)
        }

        loadBackups()

        NotificationManager.success(
            title: "Cloud Sync",
            message: "\(remoteSnapshots.count) snapshot(s) downloaded for \(gameName)",
            duration: 3
        )
    }

    // MARK: - Helpers

    private func gameDirURL(gameID: UUID) -> URL {
        storageURL.appendingPathComponent(gameID.uuidString, isDirectory: true)
    }

    private func snapshotDirURL(_ snapshot: SaveSnapshot) -> URL? {
        let gameDir = gameDirURL(gameID: snapshot.gameID)
        guard fileManager.fileExists(atPath: gameDir.path),
              let contents = try? fileManager.contentsOfDirectory(atPath: gameDir.path) else { return nil }

        // Find the directory whose manifest matches the snapshot ID
        for name in contents {
            let dir = gameDir.appendingPathComponent(name)
            let manifestURL = dir.appendingPathComponent(manifestFileName)
            guard let data = try? Data(contentsOf: manifestURL),
                  let loaded = try? decoder.decode(SaveSnapshot.self, from: data),
                  loaded.id == snapshot.id else { continue }
            return dir
        }
        return nil
    }

    private func resolveSourceURL(for file: SaveFileInfo, game: Game) -> URL? {
        let patterns = RunnerSavePath.known
            .filter { $0.runnerName.lowercased() == game.runner.lowercased() }
            .flatMap { $0.pathPatterns }

        for pattern in patterns {
            let expanded = (pattern as NSString).expandingTildeInPath
            let resolved = resolveGlob(expanded)
            for root in resolved {
                let testPath = root.appendingPathComponent(file.relativePath).path
                if fileManager.fileExists(atPath: testPath) {
                    return URL(fileURLWithPath: testPath)
                }
            }
        }
        return nil
    }

    private func loadBackups() {
        guard let gameDirs = try? fileManager.contentsOfDirectory(at: storageURL, includingPropertiesForKeys: nil) else {
            backups = []
            return
        }

        var all: [SaveSnapshot] = []
        for gameDir in gameDirs {
            guard let backupDirs = try? fileManager.contentsOfDirectory(at: gameDir, includingPropertiesForKeys: nil) else { continue }
            for dir in backupDirs {
                let manifestURL = dir.appendingPathComponent(manifestFileName)
                guard let data = try? Data(contentsOf: manifestURL),
                      let snapshot = try? decoder.decode(SaveSnapshot.self, from: data) else { continue }
                all.append(snapshot)
            }
        }
        backups = all.sorted { $0.timestamp > $1.timestamp }
    }

    private func enforceBackupLimit(gameID: UUID) {
        var gameBackups = listBackups(for: gameID)
        while gameBackups.count > maxLocalBackups {
            if let oldest = gameBackups.last {
                deleteBackup(oldest)
            }
            gameBackups = listBackups(for: gameID)
        }
    }

    private func resolveGlob(_ pattern: String) -> [URL] {
        if pattern.contains("*") {
            let base = (pattern as NSString).deletingLastPathComponent
            let glob = (pattern as NSString).lastPathComponent
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/bash")
            task.arguments = ["-c", "ls -d '\(base)/\(glob)' 2>/dev/null"]
            let pipe = Pipe()
            task.standardOutput = pipe
            try? task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return output.split(separator: "\n").map { URL(fileURLWithPath: String($0)) }
        }
        return [URL(fileURLWithPath: pattern)]
    }

    private func formattedDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .short
        fmt.timeStyle = .short
        return fmt.string(from: date)
    }
}

// MARK: - Errors

enum CloudSaveError: LocalizedError {
    case noProvider
    case snapshotNotFound
    case uploadFailed(String)
    case downloadFailed(String)
    case conflictDetected

    var errorDescription: String? {
        switch self {
        case .noProvider: return "No cloud provider configured"
        case .snapshotNotFound: return "Snapshot directory not found on disk"
        case .uploadFailed(let msg): return "Upload failed: \(msg)"
        case .downloadFailed(let msg): return "Download failed: \(msg)"
        case .conflictDetected: return "Local and remote snapshots differ"
        }
    }
}
