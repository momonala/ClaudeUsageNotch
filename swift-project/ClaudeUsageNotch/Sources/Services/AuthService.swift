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

    public func clearCredential() {
        store.delete(account: Self.account)
    }

    // MARK: - Claude

    public var claudeHasOAuthAvailable: Bool {
        ClaudeOAuthCredential.isAvailable()
    }

    /// Sanitizes, validates, then stores the Claude session cookie.
    /// Returns a user-facing error string if validation fails, nil on success.
    @discardableResult
    public func saveClaudeCredential(_ credential: ClaudeCredential) -> String? {
        let trimmed = credential.cookie.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Cookie cannot be empty." }
        guard trimmed.count >= 32 else {
            return "Cookie looks too short. Paste the full Cookie header from DevTools."
        }
        guard trimmed.count <= 65_536 else {
            return "That doesn't look right — it's too long. Copy only the Cookie header value."
        }
        let sanitized = ClaudeCredential(
            cookie: trimmed,
            storedAt: credential.storedAt,
            lastValidatedAt: credential.lastValidatedAt
        )
        guard let data = try? JSONEncoder().encode(sanitized) else {
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
