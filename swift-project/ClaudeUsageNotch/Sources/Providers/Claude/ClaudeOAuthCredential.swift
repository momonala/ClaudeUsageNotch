import Foundation
import Security
import os.log

private let logger = Logger(subsystem: "com.claudeusagenotch.ClaudeUsageNotch", category: "OAuth")

/// The Claude CLI's OAuth credential, resolved from the CLI file, our own mirror of
/// it, or a refresh of the mirrored token — in that order, none of which prompt.
///
/// The CLI's `Claude Code-credentials` Keychain item is a last resort because reading
/// it cross-app costs a login-keychain password prompt every time Claude Code rotates
/// the token and resets the item's ACL and partition list. One read seeds the mirror;
/// after that the app refreshes the token itself. See the Auth section of the README.
struct ClaudeOAuthCredential {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date?
    let orgId: String?

    var isLikelyExpired: Bool {
        guard let exp = expiresAt else { return false }
        return exp < Date().addingTimeInterval(30)
    }

    // MARK: - Reading

    static func current(session: URLSession = .shared) async -> ClaudeOAuthCredential? {
        await Resolver.shared.current(session: session)
    }

    /// True if a credential exists without decrypting anything, so it never prompts.
    static func isAvailable() -> Bool {
        if FileManager.default.fileExists(atPath: filePath().path) { return true }
        return keychainItemExists()
    }

    /// An actor so two concurrent polls can't race and burn each other's rotated
    /// refresh token.
    private actor Resolver {
        static let shared = Resolver()

        func current(session: URLSession) async -> ClaudeOAuthCredential? {
            if let cred = unexpired(fileData()) { return cred }

            let mirrored = mirror.get(account: mirrorAccount)
            if let cred = unexpired(mirrored) { return cred }
            if let cred = await refreshed(mirrored, session: session) { return cred }

            return seededFromCLIKeychain()
        }

        private func unexpired(_ blob: Data?) -> ClaudeOAuthCredential? {
            guard let blob, let cred = parse(from: blob), !cred.isLikelyExpired else { return nil }
            return cred
        }

        /// Rotates the mirrored credential in place. Refresh tokens outlive access
        /// tokens by weeks, so this is the steady-state path.
        private func refreshed(_ blob: Data?, session: URLSession) async -> ClaudeOAuthCredential? {
            guard let blob,
                  let refreshToken = parse(from: blob)?.refreshToken else { return nil }
            do {
                let rotated = try await ClaudeOAuthRefresher.refresh(
                    previousBlob: blob, refreshToken: refreshToken, session: session)
                guard let cred = parse(from: rotated) else { return nil }
                mirror.set(account: mirrorAccount, data: rotated)
                return cred
            } catch {
                logger.error("OAuth refresh failed, re-seeding from the CLI item: \(String(describing: error), privacy: .public)")
                return nil
            }
        }

        /// The read that may prompt. Reached once, and after that only when a refresh
        /// is rejected and the credential has to be re-seeded.
        private func seededFromCLIKeychain() -> ClaudeOAuthCredential? {
            guard let blob = keychainData(), let cred = parse(from: blob) else { return nil }
            mirror.set(account: mirrorAccount, data: blob)
            return cred
        }
    }

    // MARK: - Parsing

    static func parse(from data: Data) -> ClaudeOAuthCredential? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        let oauth = (json["claudeAiOauth"] as? [String: Any]) ?? json
        let token = (oauth["accessToken"] as? String)
                 ?? (json["claudeAiOauthToken"] as? String)
                 ?? (json["accessToken"] as? String)
                 ?? (json["oauth_token"] as? String)
                 ?? (json["token"] as? String)
        guard let token, !token.isEmpty else { return nil }

        let refresh = (oauth["refreshToken"] as? String) ?? (json["refreshToken"] as? String)
        let org = (json["organizationUuid"] as? String)
               ?? (oauth["organizationUuid"] as? String)
        return ClaudeOAuthCredential(
            accessToken: token,
            refreshToken: (refresh?.isEmpty == false) ? refresh : nil,
            expiresAt: parseExpiry(from: oauth) ?? parseExpiry(from: json),
            orgId: (org.flatMap { UUID(uuidString: $0) != nil ? $0 : nil })
        )
    }

    static func parseExpiry(from json: [String: Any]) -> Date? {
        if let value = json["expiresAt"] as? TimeInterval {
            // Claude Code writes ms since epoch; older file formats used seconds. Any
            // plausible ms value is ~1e12, while a seconds value is ~1e9.
            return value > 1_000_000_000_000
                ? Date(timeIntervalSince1970: value / 1000)
                : Date(timeIntervalSince1970: value)
        }
        return parseISO8601(json["expiresAt"] as? String)
    }

    // MARK: - Sources

    /// Claude Code writes `.credentials.json`; the undotted name is the older CLI's.
    private static func filePath() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dotted = home.appendingPathComponent(".claude/.credentials.json")
        return FileManager.default.fileExists(atPath: dotted.path)
            ? dotted
            : home.appendingPathComponent(".claude/credentials.json")
    }

    private static func fileData() -> Data? {
        try? Data(contentsOf: filePath())
    }

    private static let keychainService = "Claude Code-credentials"

    /// Our own copy of the CLI blob. We created the item, so reads never prompt.
    private static let mirror = KeychainStore(service: "com.claudeusagenotch.oauth-mirror")
    private static let mirrorAccount = "claude-oauth"

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

    /// Attributes only, not the secret, so this never prompts.
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
