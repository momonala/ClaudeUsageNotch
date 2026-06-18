import Foundation
import Security
import os.log

private let logger = Logger(subsystem: "com.claudeusagenotch.ClaudeUsageNotch", category: "Keychain")

/// Tiny Keychain wrapper for `kSecClassGenericPassword` items.
/// Used to store provider credentials (e.g. Claude session cookie).
///
/// Security posture:
///  - `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — readable only while
///    the screen is unlocked; never leaves the device via iCloud backup.
///  - Access is governed by the default ACL: the app that created an item can
///    read it back without a prompt **once it has a stable code signature**.
///
/// Prompt behaviour: macOS keys keychain access to the app's code-signing
/// identity. A signed + notarized build reads its own items silently (and any
/// one-time "Always Allow" sticks). Unsigned/ad-hoc dev builds present a
/// changing identity, so macOS may still prompt — but the in-memory cache below
/// collapses that to at most one prompt per credential per launch instead of
/// one on every usage poll.
public final class KeychainStore {
    private let service: String

    /// In-memory cache of decrypted items, keyed by account. The first read of
    /// each credential hits the Keychain (and may prompt on unsigned builds);
    /// every subsequent read in the same launch is served from memory, so the
    /// 5-minute usage poll never re-triggers a Keychain prompt. Writes/deletes
    /// keep the cache coherent.
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
