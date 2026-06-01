import Foundation

/// OpenAI provider — connected-status only.
///
/// Auth: standard `sk-...` API key stored in Keychain.
///
/// Why status-only: OpenAI's old billing dashboard endpoints
/// (`/v1/dashboard/billing/subscription` + `/usage`) only ever accepted a
/// browser **session** token (`sess-...`), never a standard API key — and
/// OpenAI has since deprecated them. A regular `sk-...` key gets a 401 there,
/// which is exactly why the key would "validate" on format but then report
/// "Authentication expired" the moment usage was fetched. The Usage/Costs API
/// that replaced them requires an org **Admin** key (`sk-admin-...`), which we
/// can't assume users have.
///
/// So, like Gemini and Perplexity, Notchy verifies the key is live against an
/// endpoint that genuinely works with a standard key (`GET /v1/models`) and
/// surfaces a "Connected" status — not a misleading quota %.
final class OpenAIProvider: UsageProvider {
    let id: ProviderId = .openai
    let displayName: String = "OpenAI"
    let requiresCookie: Bool = false
    let isAvailable: Bool = true

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - UsageProvider

    func validateCredentials() async throws {
        try await probeKey()
    }

    func fetchUsage() async throws -> ServiceUsageSnapshot {
        try await probeKey()
        return .connected(providerId: .openai)
    }

    // MARK: - API

    /// Hits `GET /v1/models`, which authenticates with any valid `sk-...` key
    /// and returns no billable usage. Auth failures map to `.unauthorized`;
    /// any 2xx means the key is live and reachable.
    private func probeKey() async throws {
        let apiKey = try currentAPIKey()
        var request = URLRequest(
            url: OpenAIEndpoint.modelsURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 15
        )
        request.httpMethod = "GET"
        for (k, v) in OpenAIEndpoint.headers(apiKey: apiKey) {
            request.setValue(v, forHTTPHeaderField: k)
        }

        let response: URLResponse
        do {
            (_, response) = try await session.data(for: request)
        } catch {
            throw ProviderError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.unknown("non-HTTP response")
        }
        switch http.statusCode {
        case 200..<300: return
        case 401, 403:  throw ProviderError.unauthorized
        case 429:       throw ProviderError.rateLimited
        case 500...:    throw ProviderError.server(http.statusCode)
        default:        throw ProviderError.unknown("HTTP \(http.statusCode)")
        }
    }

    private func currentAPIKey() throws -> String {
        guard let cred: OpenAICredential = AuthService.shared.loadCredential(for: .openai),
              !cred.apiKey.isEmpty else {
            throw ProviderError.missingCredentials
        }
        return cred.apiKey
    }
}
