import Foundation
import Security

// MARK: - Cloud Sync Provider Type

enum CloudProviderType: String, Codable, CaseIterable, Sendable {
    case webdav = "WebDAV"
    case nextcloud = "Nextcloud"
    case s3 = "S3-kompatibel"
    case appleCloud = "Apple iCloud"

    var displayName: String { rawValue }
    var needsURL: Bool { self != .appleCloud }
    var needsUsername: Bool { self == .webdav || self == .nextcloud }
    var needsPassword: Bool { self != .appleCloud }
    var usesAppleSignIn: Bool { self == .appleCloud }
}

// MARK: - Settings

struct CloudSyncSettings: Codable, Equatable {
    var providerType: CloudProviderType = .webdav
    var serverURL: String = ""
    var username: String = ""
    var syncEnabled: Bool = false
    var autoSyncOnLaunch: Bool = true
    var remotePath: String = "/LutrisForMac/CloudSaves"
    var appleUserID: String = ""

    var isValid: Bool {
        guard syncEnabled else { return false }
        if providerType == .appleCloud { return true }
        guard let url = URL(string: serverURL), url.scheme != nil else { return false }
        if providerType.needsUsername && username.isEmpty { return false }
        return true
    }
}

// MARK: - Keychain Helper

enum KeychainHelper {
    static let service = "net.lutrisformac.cloudsync"

    static func storePassword(_ password: String, account: String) -> Bool {
        guard let data = password.data(using: .utf8) else { return false }

        // Delete existing first
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

    static func loadPassword(account: String) -> String? {
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

    static func deletePassword(account: String) {
        SecItemDelete([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ] as CFDictionary)
    }
}

// MARK: - Settings Manager

@MainActor
final class CloudSyncSettingsManager: ObservableObject {
    static let shared = CloudSyncSettingsManager()

    @Published var settings: CloudSyncSettings {
        didSet { save() }
    }

    @Published var savedPassword: String?
    @Published var appleSignedIn = false
    @Published var appleUserDisplayName: String = ""

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

    func savePassword(_ password: String) {
        guard KeychainHelper.storePassword(password, account: passwordAccount) else { return }
        savedPassword = password
    }

    func clearPassword() {
        KeychainHelper.deletePassword(account: passwordAccount)
        savedPassword = nil
    }

    func setAppleAuth(userID: String, displayName: String) {
        settings.appleUserID = userID
        appleUserDisplayName = displayName
        appleSignedIn = true
    }

    func clearAppleAuth() {
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
