import Foundation
import Security

// MARK: - Cloud Sync Provider Type

public enum CloudProviderType: String, Codable, CaseIterable, Sendable {
    case webdav = "WebDAV"
    case nextcloud = "Nextcloud"
    case s3 = "S3-kompatibel"
    case appleCloud = "Apple iCloud"

    public var displayName: String { rawValue }
    public var needsURL: Bool { self != .appleCloud }
    public var needsUsername: Bool { self == .webdav || self == .nextcloud }
    public var needsPassword: Bool { self != .appleCloud }
    public var usesAppleSignIn: Bool { self == .appleCloud }
}

// MARK: - Settings

public struct CloudSyncSettings: Codable, Equatable {
    public var providerType: CloudProviderType = .webdav
    public var serverURL: String = ""
    public var username: String = ""
    public var syncEnabled: Bool = false
    public var autoSyncOnLaunch: Bool = true
    public var remotePath: String = "/LutrisForMac/CloudSaves"
    public var appleUserID: String = ""

    public var isValid: Bool {
        guard syncEnabled else { return false }
        if providerType == .appleCloud { return true }
        guard let url = URL(string: serverURL), url.scheme != nil else { return false }
        if providerType.needsUsername && username.isEmpty { return false }
        return true
    }
}

// MARK: - Keychain Helper

public enum KeychainHelper {
    public static let service = "net.lutrisformac.cloudsync"

    public static func storePassword(_ password: String, account: String) -> Bool {
        guard let data = password.data(using: .utf8) else { return false }

        SecItemDelete([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ] as CFDictionary)

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock,
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    public static func loadPassword(account: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else { return nil }
        return password
    }

    public static func deletePassword(account: String) {
        SecItemDelete([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ] as CFDictionary)
    }
}

// MARK: - Settings Manager

@MainActor
public final class CloudSyncSettingsManager: ObservableObject {
    public static let shared = CloudSyncSettingsManager()

    @Published public var settings: CloudSyncSettings {
        didSet { save() }
    }

    @Published public var savedPassword: String?
    @Published public var appleSignedIn = false
    @Published public var appleUserDisplayName: String = ""

    private let userDefaultsKey = "cloudSyncSettings"
    private let passwordAccount = "cloudsync"

    private init() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode(CloudSyncSettings.self, from: data) {
            settings = decoded
        } else {
            settings = CloudSyncSettings()
        }
        savedPassword = KeychainHelper.loadPassword(account: passwordAccount)
        checkAppleAuth()
    }

    public func savePassword(_ password: String) {
        guard KeychainHelper.storePassword(password, account: passwordAccount) else { return }
        savedPassword = password
    }

    public func clearPassword() {
        KeychainHelper.deletePassword(account: passwordAccount)
        savedPassword = nil
    }

    public func setAppleAuth(userID: String, displayName: String) {
        settings.appleUserID = userID
        appleUserDisplayName = displayName
        appleSignedIn = true
    }

    public func clearAppleAuth() {
        settings.appleUserID = ""
        appleUserDisplayName = ""
        appleSignedIn = false
    }

    private func checkAppleAuth() {
        if !settings.appleUserID.isEmpty {
            appleSignedIn = true
            appleUserDisplayName = settings.appleUserID
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
    }
}
