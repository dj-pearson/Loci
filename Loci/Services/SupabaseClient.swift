import Foundation
import Supabase

enum SupabaseConfig {
    #if DEBUG
    /// In DEBUG builds, allow overriding the Supabase URL via the
    /// LOCI_SUPABASE_URL environment variable (e.g., set in the Xcode scheme)
    /// so developers can point at a local or staging instance without
    /// modifying BuildSecrets.
    static let url: URL = {
        if let override = ProcessInfo.processInfo.environment["LOCI_SUPABASE_URL"],
           !override.isEmpty,
           let overrideURL = URL(string: override) {
            return overrideURL
        }
        return URL(string: BuildSecrets.supabaseURL)!
    }()
    #else
    static let url = URL(string: BuildSecrets.supabaseURL)!
    #endif

    static let anonKey = BuildSecrets.supabaseAnonKey
}

enum SupabaseClientProvider {
    /// Certificate pinning delegate for securing API connections.
    static let certificatePinningDelegate = CertificatePinningDelegate()

    static let shared: SupabaseClient = {
        let configuration = URLSessionConfiguration.default
        let session = URLSession(
            configuration: configuration,
            delegate: certificatePinningDelegate,
            delegateQueue: nil
        )

        return SupabaseClient(
            supabaseURL: SupabaseConfig.url,
            supabaseKey: SupabaseConfig.anonKey,
            options: .init(
                auth: .init(
                    storage: KeychainAuthStorage(),
                    flowType: .pkce
                ),
                global: .init(
                    session: session
                )
            )
        )
    }()
}

// MARK: - Keychain Auth Storage

private struct KeychainAuthStorage: AuthLocalStorage {
    private let service = "com.pearsonmedia.loci.auth"

    func store(key: String, value: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]

        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = value

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    func retrieve(key: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }

        return result as? Data
    }

    func remove(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
