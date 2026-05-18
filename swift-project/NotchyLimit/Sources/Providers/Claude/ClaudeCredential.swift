import Foundation

/// Credential bundle for Claude. Currently just the raw browser cookie.
///
/// We store the entire cookie string (not just `sessionKey=...`) because
/// `claude.ai`'s usage endpoint also reads `lastActiveOrg` and other
/// hardening cookies. Treat this value as a secret — it is keychain-only.
public struct ClaudeCredential: Codable, Hashable {
    public var cookie: String
    public var storedAt: Date
    public var lastValidatedAt: Date?

    public init(cookie: String, storedAt: Date = Date(), lastValidatedAt: Date? = nil) {
        self.cookie = cookie
        self.storedAt = storedAt
        self.lastValidatedAt = lastValidatedAt
    }

    /// Extract `lastActiveOrg` value from the cookie string if present.
    public var orgIdFromCookie: String? {
        for part in cookie.split(separator: ";") {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("lastActiveOrg=") {
                return String(trimmed.dropFirst("lastActiveOrg=".count))
            }
        }
        return nil
    }
}
