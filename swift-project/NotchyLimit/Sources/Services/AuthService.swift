import Foundation

/// Provider-credential storage. Backed by macOS Keychain.
public final class AuthService {
    public static let shared = AuthService()
    private init() {}

    private let store = KeychainStore(service: "com.notchylimit.NotchyLimit")

    // MARK: - Generic

    public func hasCredential(for providerId: ProviderId) -> Bool {
        store.get(account: providerId.rawValue) != nil
    }

    public func hasAnyConfiguredProvider() -> Bool {
        ProviderId.allCases.contains { hasCredential(for: $0) }
    }

    public func clearCredential(for providerId: ProviderId) {
        store.delete(account: providerId.rawValue)
    }

    // MARK: - Claude-specific helpers

    public func saveClaudeCredential(_ credential: ClaudeCredential) {
        guard let data = try? JSONEncoder().encode(credential) else { return }
        store.set(account: ProviderId.claude.rawValue, data: data)
    }

    /// Generic load. Returns the decoded credential of type `T` if present.
    public func loadCredential<T: Decodable>(for providerId: ProviderId) -> T? {
        guard let data = store.get(account: providerId.rawValue) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
