import Foundation
import Security

/// Reads Claude OAuth credentials, preferring the Claude CLI / Claude Code login.
///
/// Sources, in order:
///   1. `~/.claude/credentials.json` (older Claude CLI file format)
///   2. App-owned mirror (`mirror`) — our own copy of the CLI blob, read silently
///   3. macOS Keychain item `Claude Code-credentials` (current Claude Code) —
///      a JSON blob with `claudeAiOauth.accessToken` + top-level `organizationUuid`.
///
/// The CLI item (3) is owned by the Claude CLI, so reading it cross-app prompts for
/// access whenever the CLI rewrites the item on token refresh (which resets its ACL).
/// To avoid prompting on every poll/launch, a successful read is copied into an
/// app-owned Keychain item (2); since we own that item, reads are silent. We only
/// fall back to the CLI item — and risk a prompt — once the mirrored token expires,
/// i.e. roughly once per token rotation rather than on every read.
///
/// Using this scoped, auto-refreshed OAuth token avoids the full browser session
/// cookie. When the org id is known (Keychain case) the provider can skip the
/// bootstrap round-trip entirely.
struct ClaudeOAuthCredential {
    let accessToken: String
    let expiresAt: Date?
    let orgId: String?

    var isLikelyExpired: Bool {
        guard let exp = expiresAt else { return false }
        return exp < Date().addingTimeInterval(30)
    }

    // MARK: - Reading

    static func readFromDisk() -> ClaudeOAuthCredential? {
        // 1. Legacy file format (older Claude CLI). Never prompts.
        if let data = fileData(), let cred = parse(from: data) { return cred }

        // 2. App-owned mirror — a copy of the CLI blob this app wrote itself, so
        //    reads are silent (no ACL prompt). Use it while the token is unexpired.
        if let data = mirror.get(account: mirrorAccount),
           let cred = parse(from: data), !cred.isLikelyExpired {
            return cred
        }

        // 3. Cross-app CLI Keychain item. This is the read that may prompt, because
        //    the item is owned by the Claude CLI and its ACL drops us whenever the
        //    CLI rewrites it on token refresh. Re-mirror on success so subsequent
        //    reads stay silent until the token next rotates.
        if let data = keychainData(), let cred = parse(from: data) {
            mirror.set(account: mirrorAccount, data: data)
            return cred
        }
        return nil
    }

    /// Existence check that does NOT decrypt the Keychain secret (so it never
    /// triggers an ACL prompt): file present, or a matching Keychain item exists.
    static func isAvailable() -> Bool {
        if FileManager.default.fileExists(atPath: filePath().path) { return true }
        return keychainItemExists()
    }

    // MARK: - Parsing

    static func parse(from data: Data) -> ClaudeOAuthCredential? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        // Claude Code Keychain shape: { "claudeAiOauth": {...}, "organizationUuid": "..." }
        let oauth = (json["claudeAiOauth"] as? [String: Any]) ?? json
        let token = (oauth["accessToken"] as? String)
                 ?? (json["claudeAiOauthToken"] as? String)
                 ?? (json["accessToken"] as? String)
                 ?? (json["oauth_token"] as? String)
                 ?? (json["token"] as? String)
        guard let token, !token.isEmpty else { return nil }

        let org = (json["organizationUuid"] as? String)
               ?? (oauth["organizationUuid"] as? String)
        return ClaudeOAuthCredential(
            accessToken: token,
            expiresAt: parseExpiry(from: oauth) ?? parseExpiry(from: json),
            orgId: (org.flatMap { UUID(uuidString: $0) != nil ? $0 : nil })
        )
    }

    static func parseExpiry(from json: [String: Any]) -> Date? {
        if let value = json["expiresAt"] as? TimeInterval {
            // The Claude Code Keychain blob stores ms since epoch; older file
            // formats may use seconds. A 2001-era seconds value is ~1e9, while
            // any plausible ms value is ~1e12, so the magnitude disambiguates.
            return value > 1_000_000_000_000
                ? Date(timeIntervalSince1970: value / 1000)
                : Date(timeIntervalSince1970: value)
        }
        if let str = json["expiresAt"] as? String {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f.date(from: str) ?? ISO8601DateFormatter().date(from: str)
        }
        return nil
    }

    // MARK: - Sources

    private static func filePath() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/credentials.json")
    }

    private static func fileData() -> Data? {
        try? Data(contentsOf: filePath())
    }

    private static let keychainService = "Claude Code-credentials"

    /// App-owned mirror of the CLI OAuth blob. Reads are silent (we created the
    /// item), so polling never re-triggers the cross-app ACL prompt while the
    /// mirrored token is still valid.
    private static let mirror = KeychainStore(service: "com.claudeusagenotch.oauth-mirror")
    private static let mirrorAccount = "claude-oauth"

    /// Decrypts the Keychain blob (may prompt for access on first read).
    private static func keychainData() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return data
    }

    /// Existence only — returns attributes, not the secret, so no ACL prompt.
    private static func keychainItemExists() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        return SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess
    }
}
