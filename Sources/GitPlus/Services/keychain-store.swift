import Foundation
import Security

/// API keys for AI providers, stored as generic passwords in the login Keychain (one per provider).
enum KeychainStore {
    private static let service = "co.egohub.gitplus.ai"

    private static func query(_ provider: AIProvider) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: provider.rawValue]
    }

    static func apiKey(for provider: AIProvider) -> String? {
        var q = query(provider)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func hasKey(for provider: AIProvider) -> Bool { !(apiKey(for: provider) ?? "").isEmpty }

    /// Replaces the stored key; an empty key deletes it.
    static func setAPIKey(_ key: String, for provider: AIProvider) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return try deleteAPIKey(for: provider) }
        let data = Data(trimmed.utf8)
        let status = SecItemUpdate(query(provider) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query(provider)
            add[kSecValueData as String] = data
            add[kSecAttrLabel as String] = "Git Plus — \(provider.title) API key"
            add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            try check(SecItemAdd(add as CFDictionary, nil))
        } else {
            try check(status)
        }
    }

    static func deleteAPIKey(for provider: AIProvider) throws {
        let status = SecItemDelete(query(provider) as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }

    private static func check(_ status: OSStatus) throws {
        guard status != errSecSuccess else { return }
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
        throw AIError.keychain(message)
    }
}
