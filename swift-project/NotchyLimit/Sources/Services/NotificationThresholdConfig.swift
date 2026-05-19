import Foundation

/// Per-provider threshold configuration. Persisted in UserDefaults.
/// Cookie / secret material lives in Keychain only.
public struct NotificationThresholdConfig: Codable, Hashable {
    public var providerId: ProviderId
    public var windowType: UsageWindowType
    public var thresholds: [Double]

    public init(
        providerId: ProviderId,
        windowType: UsageWindowType,
        thresholds: [Double] = [0.25, 0.5, 0.75, 0.9]
    ) {
        self.providerId = providerId
        self.windowType = windowType
        self.thresholds = thresholds
    }

    var storageKey: String {
        "thresholds.\(providerId.rawValue).\(windowType.rawValue)"
    }
}
