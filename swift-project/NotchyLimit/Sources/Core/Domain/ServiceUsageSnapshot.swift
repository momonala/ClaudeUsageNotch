import Foundation

/// A complete snapshot from a provider at a moment in time.
/// The notch UI consumes one of these and binds compact + expanded views to it.
public struct ServiceUsageSnapshot: Codable, Hashable {
    public let providerId: ProviderId
    public let primaryWindow: UsageWindow          // session
    public let secondaryWindow: UsageWindow?       // weekly
    public let tertiaryWindow: UsageWindow?        // weekly Sonnet (Pro only)
    public let capturedAt: Date

    public init(
        providerId: ProviderId,
        primaryWindow: UsageWindow,
        secondaryWindow: UsageWindow? = nil,
        tertiaryWindow: UsageWindow? = nil,
        capturedAt: Date = Date()
    ) {
        self.providerId = providerId
        self.primaryWindow = primaryWindow
        self.secondaryWindow = secondaryWindow
        self.tertiaryWindow = tertiaryWindow
        self.capturedAt = capturedAt
    }

    /// The worst status across windows, used for the top-level pill color.
    public var combinedStatus: UsageStatus {
        let candidates: [UsageStatus] = [
            primaryWindow.status,
            secondaryWindow?.status ?? .healthy,
            tertiaryWindow?.status ?? .healthy
        ]
        if candidates.contains(.critical) { return .critical }
        if candidates.contains(.warning)  { return .warning }
        return .healthy
    }
}
