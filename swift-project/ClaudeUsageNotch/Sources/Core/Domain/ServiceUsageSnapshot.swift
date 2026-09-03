import Foundation

/// A complete snapshot of Claude's quota windows at a moment in time.
/// The notch UI consumes one of these and binds compact + expanded views to it.
public struct ServiceUsageSnapshot: Codable, Hashable {
    public let sessionWindow: UsageWindow           // 5-hour rolling session
    public let weeklyWindow: UsageWindow?           // 7-day window
    public let weeklySonnetWindow: UsageWindow?     // 7-day Sonnet sub-window (Pro plans)
    public let creditWindow: UsageWindow?           // Monthly usage-credit pool (Team plans)
    public let capturedAt: Date

    public init(
        sessionWindow: UsageWindow,
        weeklyWindow: UsageWindow? = nil,
        weeklySonnetWindow: UsageWindow? = nil,
        creditWindow: UsageWindow? = nil,
        capturedAt: Date = Date()
    ) {
        self.sessionWindow = sessionWindow
        self.weeklyWindow = weeklyWindow
        self.weeklySonnetWindow = weeklySonnetWindow
        self.creditWindow = creditWindow
        self.capturedAt = capturedAt
    }

    /// Every window this snapshot carries, session first.
    public var allWindows: [UsageWindow] {
        [sessionWindow, weeklyWindow, weeklySonnetWindow, creditWindow].compactMap { $0 }
    }
}
