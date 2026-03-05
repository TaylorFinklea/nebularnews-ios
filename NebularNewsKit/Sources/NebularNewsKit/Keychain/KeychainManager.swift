import Foundation
import Security

/// Thin wrapper around the iOS Keychain for storing sensitive data (API keys, credentials).
///
/// Keys are stored per-device and do NOT sync via iCloud. This is intentional —
/// API keys are security-sensitive and should not travel through CloudKit.
public final class KeychainManager: Sendable {
    private let service: String

    public init(service: String = "com.nebularnews.ios") {
        self.service = service
    }

    // MARK: - Public API

    public func set(_ value: String, forKey key: String) throws {
        let data = Data(value.utf8)

        // Delete any existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unableToStore(status)
        }
    }

    public func get(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    public func delete(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }

    public func has(key: String) -> Bool {
        get(forKey: key) != nil
    }
}

// MARK: - Well-Known Keys

extension KeychainManager {
    public enum Key {
        public static let anthropicApiKey = "anthropic_api_key"
        public static let openaiApiKey = "openai_api_key"

        // v2: backend sync credentials
        public static let syncAccessToken = "sync_access_token"
        public static let syncRefreshToken = "sync_refresh_token"
        public static let syncServerUrl = "sync_server_url"
    }
}

// MARK: - Errors

public enum KeychainError: LocalizedError {
    case unableToStore(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .unableToStore(let status):
            return "Keychain store failed with status \(status)"
        }
    }
}
