import Foundation

/// Placeholder Gemini provider. Surfaces "coming soon" in the UI; never
/// returns a snapshot. Replace the body when Google ships a usage endpoint
/// (or community discovers one).
final class GeminiProvider: UsageProvider {
    let id: ProviderId = .gemini
    let displayName: String = "Gemini"
    let requiresCookie: Bool = true
    let isAvailable: Bool = false

    func validateCredentials() async throws {
        throw ProviderError.unknown("Gemini provider is not implemented yet.")
    }

    func fetchUsage() async throws -> ServiceUsageSnapshot {
        throw ProviderError.unknown("Gemini provider is not implemented yet.")
    }
}
