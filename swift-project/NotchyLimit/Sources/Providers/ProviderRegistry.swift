import Foundation

public final class ProviderRegistry {
    public static let shared = ProviderRegistry()
    private init() {}

    private var providers: [ProviderId: UsageProvider] = [:]

    public func bootstrap() {
        register(ClaudeProvider())
    }

    public func register(_ provider: UsageProvider) {
        providers[provider.id] = provider
    }

    public func provider(for id: ProviderId) -> UsageProvider? {
        providers[id]
    }

    public func availableProviders() -> [UsageProvider] {
        ProviderId.allCases.compactMap { providers[$0] }.filter { $0.isAvailable }
    }
}
