import Foundation
import os.log

private let logger = Logger(subsystem: "com.claudeusagenotch.ClaudeUsageNotch", category: "OAuthRefresh")

/// Exchanges a Claude Code refresh token for a fresh access token.
///
/// Claude Code rewrites its Keychain item on every rotation, which resets the item's
/// ACL and partition list — and re-granting a partition entry is what makes macOS ask
/// for the login-keychain password. Refreshing here means that item is read once to
/// seed the mirror and then never again.
enum ClaudeOAuthRefresher {

    /// Returns a credential blob in Claude Code's own shape, so the mirror stays
    /// format-compatible with whatever the CLI wrote.
    static func refresh(previousBlob: Data,
                        refreshToken: String,
                        session: URLSession = .shared) async throws -> Data {
        var request = URLRequest(url: ClaudeEndpoint.oauthToken,
                                 cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "grant_type":    "refresh_token",
            "refresh_token": refreshToken,
            "client_id":     ClaudeEndpoint.oauthClientID,
        ])

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ProviderError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.unknown("non-HTTP response")
        }
        switch http.statusCode {
        case 200..<300: break
        case 400, 401, 403: throw ProviderError.unauthorized   // revoked, or rotated away by the CLI
        case 429:           throw ProviderError.rateLimited
        case 500...:        throw ProviderError.server(http.statusCode)
        default:            throw ProviderError.unknown("HTTP \(http.statusCode)")
        }

        guard let merged = mergedBlob(previous: previousBlob, tokenResponse: data) else {
            throw ProviderError.decoding("unusable token response")
        }
        logger.info("Refreshed Claude OAuth token in-process")
        return merged
    }

    /// Folds a token response into the previous blob, carrying over the fields the
    /// endpoint doesn't return. Nil if either side is unusable.
    static func mergedBlob(previous: Data, tokenResponse: Data) -> Data? {
        guard let json = try? JSONSerialization.jsonObject(with: tokenResponse) as? [String: Any],
              let accessToken = json["access_token"] as? String, !accessToken.isEmpty,
              var blob = try? JSONSerialization.jsonObject(with: previous) as? [String: Any]
        else { return nil }

        var oauth = (blob["claudeAiOauth"] as? [String: Any]) ?? [:]
        oauth["accessToken"] = accessToken
        if let rotated = json["refresh_token"] as? String, !rotated.isEmpty {
            oauth["refreshToken"] = rotated
        }
        // `expires_in` is seconds from now; the blob stores absolute ms since epoch.
        if let ttl = json["expires_in"] as? TimeInterval {
            oauth["expiresAt"] = Date().addingTimeInterval(ttl).timeIntervalSince1970 * 1000
        }
        if let scope = json["scope"] as? String {
            oauth["scopes"] = scope.split(separator: " ").map(String.init)
        }
        blob["claudeAiOauth"] = oauth

        if let org = (json["organization"] as? [String: Any])?["uuid"] as? String {
            blob["organizationUuid"] = org
        }
        return try? JSONSerialization.data(withJSONObject: blob)
    }
}
