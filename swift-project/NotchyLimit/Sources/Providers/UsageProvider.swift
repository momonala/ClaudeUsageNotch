import Foundation

/// Provider abstraction. Implement this to add a new AI service to Notchy Limit.
///
/// Contract:
/// - `validateCredentials` must throw `ProviderError.unauthorized` on a bad token.
/// - `fetchUsage` must return a `ServiceUsageSnapshot` mapped to the unified domain types,
///   not raw provider DTOs.
/// - Both methods must be safe to call concurrently from a single coordinator.
public protocol UsageProvider: AnyObject {
    var id: ProviderId { get }
    var displayName: String { get }
    var requiresCookie: Bool { get }

    func validateCredentials() async throws
    func fetchUsage() async throws -> ServiceUsageSnapshot
}
