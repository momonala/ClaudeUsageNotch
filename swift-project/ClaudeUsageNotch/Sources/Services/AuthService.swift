import Foundation

/// Credential storage for Claude. Backed by macOS Keychain.
public final class AuthService {
    public static let shared = AuthService()
    private init() {}

    private let store = KeychainStore(service: "com.claudeusagenotch.ClaudeUsageNotch")
    private static let account = "claude"

    public func hasCredential() -> Bool {
        store.get(account: Self.account) != nil
    }

    public func hasAnyConfiguredProvider() -> Bool {
        cliOAuthAvailable() || hasCredential()
    }

    public func cliOAuthAvailable() -> Bool {
        ClaudeOAuthCredential.isAvailable()
    }

    // MARK: - Claude

    /// Trims, validates, then stores a pasted Claude session cookie.
    /// Returns a user-facing error string if validation fails, nil on success.
    @discardableResult
    public func saveClaudeCookie(_ rawCookie: String) -> String? {
        let cookie = rawCookie.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cookie.isEmpty else { return "Cookie cannot be empty." }
        guard cookie.count >= 32 else {
            return "Cookie looks too short. Paste the full Cookie header from DevTools."
        }
        guard cookie.count <= 65_536 else {
            return "That doesn't look right — it's too long. Copy only the Cookie header value."
        }
        guard let data = try? JSONEncoder().encode(ClaudeCredential(cookie: cookie)) else {
            return "Failed to encode credential."
        }
        store.set(account: Self.account, data: data)
        return nil
    }

    public func loadCredential<T: Decodable>() -> T? {
        guard let data = store.get(account: Self.account) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
