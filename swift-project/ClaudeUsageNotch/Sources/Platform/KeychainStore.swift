import Foundation
import Security
import os.log

private let logger = Logger(subsystem: "com.claudeusagenotch.ClaudeUsageNotch", category: "Keychain")

/// Keychain wrapper for the `kSecClassGenericPassword` items holding provider
/// credentials.
///
/// Items are `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, so they never
/// leave the device. macOS keys access to the app's code-signing identity: a
/// signed build reads its own items silently, while unsigned dev builds present
/// a changing identity and may prompt.
public final class KeychainStore {
    private let service: String

    /// Serves every read after the first from memory, so the usage poll can't
    /// re-trigger a Keychain prompt on an unsigned build.
    private var cache: [String: Data] = [:]
    private let lock = NSLock()

    public init(service: String) { self.service = service }

    public func set(account: String, data: Data) {
        let label = "\(service) — \(account)"
        let searchQuery: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let updateAttrs: [String: Any] = [
            kSecValueData as String:      data,
            kSecAttrLabel as String:      label,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        // Try update first (avoids TOCTOU between delete + add).
        var status = SecItemUpdate(searchQuery as CFDictionary, updateAttrs as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = searchQuery
            addQuery[kSecValueData as String]      = data
            addQuery[kSecAttrLabel as String]      = label
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(addQuery as CFDictionary, nil)
        }

        if status == errSecSuccess {
            lock.withLock { cache[account] = data }
        } else {
            logger.error("Keychain write failed: OSStatus \(status, privacy: .public)")
        }
    }

    public func get(account: String) -> Data? {
        if let cached = lock.withLock({ cache[account] }) { return cached }

        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne,
        ]
        var item: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }

        lock.withLock { cache[account] = data }
        return data
    }

    @discardableResult
    public func delete(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        lock.withLock { cache[account] = nil }
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
