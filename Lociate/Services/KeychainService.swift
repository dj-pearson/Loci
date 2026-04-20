import Foundation
import Security

enum KeychainService {
    // MARK: - Key Constants

    enum Key {
        static let authToken = "app.lociate.ios.authToken"
        static let refreshToken = "app.lociate.ios.refreshToken"
        static let userId = "app.lociate.ios.userId"
    }

    // MARK: - Errors

    enum KeychainError: Error, LocalizedError {
        case saveFailed(OSStatus)
        case loadFailed(OSStatus)
        case deleteFailed(OSStatus)
        case unexpectedData

        var errorDescription: String? {
            switch self {
            case .saveFailed(let status):
                "Keychain save failed: \(status)"
            case .loadFailed(let status):
                "Keychain load failed: \(status)"
            case .deleteFailed(let status):
                "Keychain delete failed: \(status)"
            case .unexpectedData:
                "Unexpected data format in Keychain"
            }
        }
    }

    // MARK: - Save

    /// Saves data to the Keychain with the most restrictive accessibility attributes:
    /// - kSecAttrAccessibleWhenUnlockedThisDeviceOnly: data is inaccessible while device is
    ///   locked and is never migrated to a new device on restore (unlike AfterFirstUnlock).
    /// - kSecAttrSynchronizable=false: never replicated to iCloud Keychain.
    static func save(key: String, data: Data) throws {
        try saveWithAccessibility(key: key, data: data, accessibility: kSecAttrAccessibleWhenUnlockedThisDeviceOnly)
    }

    /// Explicit accessibility override for callers that need a different class
    /// (e.g., background fetch tokens). Synchronizable is always forced to false.
    static func saveWithAccessibility(key: String, data: Data, accessibility: CFString) throws {
        // Delete existing item first to avoid duplicates
        try? delete(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: accessibility,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    // MARK: - Load

    static func load(key: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw KeychainError.unexpectedData
            }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.loadFailed(status)
        }
    }

    // MARK: - Delete

    static func delete(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    // MARK: - Convenience

    static func saveString(_ value: String, forKey key: String) throws {
        guard let data = value.data(using: .utf8) else { return }
        try save(key: key, data: data)
    }

    static func loadString(forKey key: String) throws -> String? {
        guard let data = try load(key: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
