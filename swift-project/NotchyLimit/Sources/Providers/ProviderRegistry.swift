import Foundation

/// Process-wide registry of available providers.
///
/// Today: Claude only. Tomorrow: append Gemini / ChatGPT / etc. in `bootstrap()`.
public final class ProviderRegistry {
    public static let shared = ProviderRegistry()
    private init() {}

    private var providers: [ProviderId: UsageProvider] = [:]

    public func bootstrap() {
        register(ClaudeProvider())
        // Future: register(GeminiProvider()) once implemented.
    }

    public func register(_ provider: UsageProvider) {
        providers[provider.id] = provider
    }

    public func provider(for id: ProviderId) -> UsageProvider? {
        providers[id]
    }

    public func availableProviders() -> [UsageProvider] {
        ProviderId.allCases.compactMap { providers[$0] }
    }
}
