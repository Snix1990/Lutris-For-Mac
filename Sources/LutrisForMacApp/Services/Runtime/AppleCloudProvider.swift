import Foundation
import AppKit
import AuthenticationServices

// MARK: - iCloud Availability

enum iCloudStatus {
    case available(containerURL: URL)
    case notSignedIn
    case unavailable

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }
}

func checkiCloudStatus() -> iCloudStatus {
    guard FileManager.default.ubiquityIdentityToken != nil else {
        return .notSignedIn
    }
    guard let url = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
        return .unavailable
    }
    return .available(containerURL: url)
}

// MARK: - Apple Cloud Provider

@MainActor
final class AppleCloudProvider: NSObject, CloudSaveProvider {
    let name = "Apple iCloud"

    var isAvailable: Bool {
        checkiCloudStatus().isAvailable
    }

    private var containerURL: URL? {
        if case .available(let url) = checkiCloudStatus() {
            return url
        }
        return nil
    }

    private var savesRootURL: URL? {
        containerURL?.appendingPathComponent("LutrisForMac/CloudSaves")
    }

    // MARK: - CloudSaveProvider

    func upload(snapshot: SaveSnapshot, files: [URL]) async throws {
        guard let root = savesRootURL else { throw CloudSaveError.noProvider }
        let snapshotDir = root.appendingPathComponent(snapshot.gameID.uuidString)
            .appendingPathComponent("backup_\(timestampString(snapshot.timestamp))")
        try FileManager.default.createDirectory(at: snapshotDir, withIntermediateDirectories: true)

        // Copy each file, preserving relative structure
        for fileURL in files {
            let dest = snapshotDir.appendingPathComponent(fileURL.lastPathComponent)
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: fileURL, to: dest)
        }

        // Write metadata
        let metaURL = snapshotDir.appendingPathComponent(".snapshot.json")
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: metaURL)
    }

    func download(snapshot: SaveSnapshot, to destination: URL) async throws {
        guard let root = savesRootURL else { throw CloudSaveError.noProvider }
        let snapshotDir = root.appendingPathComponent(snapshot.gameID.uuidString)
            .appendingPathComponent("backup_\(timestampString(snapshot.timestamp))")
        guard FileManager.default.fileExists(atPath: snapshotDir.path) else {
            throw CloudSaveError.snapshotNotFound
        }

        // Copy all files except .snapshot.json
        let contents = try FileManager.default.contentsOfDirectory(at: snapshotDir, includingPropertiesForKeys: nil)
        for url in contents {
            if url.lastPathComponent == ".snapshot.json" { continue }
            let dest = destination.appendingPathComponent(url.lastPathComponent)
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: url, to: dest)
        }
    }

    func listSnapshots(gameID: UUID) async throws -> [SaveSnapshot] {
        guard let root = savesRootURL else { return [] }
        let gameDir = root.appendingPathComponent(gameID.uuidString)
        guard FileManager.default.fileExists(atPath: gameDir.path) else { return [] }

        let contents = try FileManager.default.contentsOfDirectory(at: gameDir, includingPropertiesForKeys: nil)
        var snapshots: [SaveSnapshot] = []
        for url in contents {
            let metaURL = url.appendingPathComponent(".snapshot.json")
            guard FileManager.default.fileExists(atPath: metaURL.path),
                  let data = try? Data(contentsOf: metaURL),
                  let snapshot = try? JSONDecoder().decode(SaveSnapshot.self, from: data) else { continue }
            snapshots.append(snapshot)
        }
        return snapshots.sorted { $0.timestamp > $1.timestamp }
    }

    func delete(snapshot: SaveSnapshot) async throws {
        guard let root = savesRootURL else { throw CloudSaveError.noProvider }
        let snapshotDir = root.appendingPathComponent(snapshot.gameID.uuidString)
            .appendingPathComponent("backup_\(timestampString(snapshot.timestamp))")
        if FileManager.default.fileExists(atPath: snapshotDir.path) {
            try FileManager.default.removeItem(at: snapshotDir)
        }
    }

    // MARK: - Helpers

    private func timestampString(_ date: Date) -> String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        return fmt.string(from: date)
            .replacingOccurrences(of: ":", with: "-")
    }
}

// MARK: - Sign in with Apple Delegate

final class AppleSignInManager: NSObject, ASAuthorizationControllerDelegate {
    static let shared = AppleSignInManager()

    private var continuation: CheckedContinuation<(userID: String, displayName: String), any Error>?

    func signIn() async throws -> (userID: String, displayName: String) {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self

        return try await withCheckedThrowingContinuation { [weak self] continuation in
            guard let self else {
                continuation.resume(throwing: CloudSaveError.noProvider)
                return
            }
            self.continuation = continuation
            controller.performRequests()
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            continuation?.resume(throwing: CloudSaveError.uploadFailed("Ungültige Anmeldedaten"))
            continuation = nil
            return
        }

        let userID = appleIDCredential.user
        var displayName = userID
        if let fullName = appleIDCredential.fullName {
            let parts = [fullName.givenName, fullName.familyName].compactMap { $0 }
            if !parts.isEmpty {
                displayName = parts.joined(separator: " ")
            }
        }
        continuation?.resume(returning: (userID: userID, displayName: displayName))
        continuation = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
