import Foundation

/// Reads Claude's usage endpoints, resolving auth fresh on every fetch:
///
///   1. `~/.claude/credentials.json` → Bearer token against
///      `api.anthropic.com/api/oauth/usage` (scoped, short-lived, preferred)
///   2. Keychain session cookie → `claude.ai/api/organizations/{org}/usage`
///      (full account access, fallback)
///
/// When OAuth succeeds the cookie is never read from the keychain at all.
final class ClaudeProvider {
    private let session: URLSession
    private let authService: AuthService

    init(session: URLSession = .shared, authService: AuthService = .shared) {
        self.session = session
        self.authService = authService
    }

    func fetchUsage() async throws -> ServiceUsageSnapshot {
        let ctx = try await resolveAuthContext()

        // Both endpoints return the same five_hour / seven_day / seven_day_sonnet shape.
        let url = switch ctx.auth {
        case .bearer: ClaudeEndpoint.oauthUsage
        case .cookie: ClaudeEndpoint.usage(orgId: ctx.orgId)
        }
        let data = try await get(url: url, auth: ctx.auth)

        do {
            let dto = try JSONDecoder().decode(ClaudeUsageDTO.self, from: data)
            return try ClaudeUsageMapper.snapshot(from: dto)
        } catch let e as ProviderError { throw e }
        catch { throw ProviderError.decoding(error.localizedDescription) }
    }

    // MARK: - Auth resolution

    private enum Auth {
        case bearer(String)
        case cookie(String)
    }

    private struct AuthContext {
        let auth: Auth
        let orgId: String
    }

    /// Tries OAuth, falls back to cookie. Throws `missingCredentials` if neither
    /// is available, or the specific auth error from whichever tier was attempted.
    private func resolveAuthContext() async throws -> AuthContext {
        // ── Tier 1: OAuth ──────────────────────────────────────────────────
        if let oauthCred = ClaudeOAuthCredential.readFromDisk(),
           !oauthCred.isLikelyExpired {
            // The OAuth usage endpoint (api.anthropic.com/api/oauth/usage) is
            // org-agnostic — fetchUsage's .bearer branch never reads orgId. So we
            // skip the claude.ai/api/bootstrap round-trip entirely: it exists only
            // to populate an org id the bearer path doesn't use, and it's now
            // Cloudflare-gated (returns 403 to non-browser clients), which would
            // otherwise look like a rejected token and drop us to the cookie tier.
            return AuthContext(auth: .bearer(oauthCred.accessToken), orgId: oauthCred.orgId ?? "")
        }

        // ── Tier 2: Session cookie ─────────────────────────────────────────
        let cookie = try currentCookie()
        if let orgFromCookie = ClaudeCredential(cookie: cookie).orgIdFromCookie {
            return AuthContext(auth: .cookie(cookie), orgId: orgFromCookie)
        }
        let orgId = try await bootstrapOrgId(auth: .cookie(cookie))
        return AuthContext(auth: .cookie(cookie), orgId: orgId)
    }

    private func bootstrapOrgId(auth: Auth) async throws -> String {
        let data = try await get(url: ClaudeEndpoint.bootstrap, auth: auth)
        do {
            let dto = try JSONDecoder().decode(ClaudeBootstrapDTO.self, from: data)
            guard let orgId = dto.account?.lastActiveOrgId,
                  UUID(uuidString: orgId) != nil else {
                throw ProviderError.decoding("bootstrap missing or invalid lastActiveOrgId")
            }
            return orgId
        } catch let e as ProviderError { throw e }
        catch { throw ProviderError.decoding("bootstrap parse: \(error.localizedDescription)") }
    }

    private func currentCookie() throws -> String {
        guard let cred: ClaudeCredential = authService.loadCredential(),
              !cred.cookie.isEmpty else {
            throw ProviderError.missingCredentials
        }
        return cred.cookie
    }

    // MARK: - HTTP

    private func get(url: URL, auth: Auth) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = "GET"

        switch auth {
        case .cookie(let c):
            for (k, v) in ClaudeEndpoint.headers(cookie: c) { request.setValue(v, forHTTPHeaderField: k) }
        case .bearer(let t):
            for (k, v) in ClaudeEndpoint.oauthUsageHeaders(token: t) { request.setValue(v, forHTTPHeaderField: k) }
        }

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
        case 200..<300: return data
        case 401, 403:  throw ProviderError.unauthorized
        case 429:       throw ProviderError.rateLimited
        case 500...:    throw ProviderError.server(http.statusCode)
        default:        throw ProviderError.unknown("HTTP \(http.statusCode)")
        }
    }
}
