import Foundation

/// A complete snapshot of Claude's quota windows at a moment in time.
/// The notch UI consumes one of these and binds compact + expanded views to it.
public struct ServiceUsageSnapshot: Codable, Hashable {
    public let sessionWindow: UsageWindow           // 5-hour rolling session
    public let weeklyWindow: UsageWindow?           // 7-day window
    public let weeklySonnetWindow: UsageWindow?     // 7-day Sonnet sub-window (Pro plans)
    public let weeklyFableWindow: UsageWindow?      // 7-day Fable sub-window
    public let creditWindow: UsageWindow?           // Monthly usage-credit pool (Team plans)
    public let capturedAt: Date

    public init(
        sessionWindow: UsageWindow,
        weeklyWindow: UsageWindow? = nil,
        weeklySonnetWindow: UsageWindow? = nil,
        weeklyFableWindow: UsageWindow? = nil,
        creditWindow: UsageWindow? = nil,
        capturedAt: Date = Date()
    ) {
        self.sessionWindow = sessionWindow
        self.weeklyWindow = weeklyWindow
        self.weeklySonnetWindow = weeklySonnetWindow
        self.weeklyFableWindow = weeklyFableWindow
        self.creditWindow = creditWindow
        self.capturedAt = capturedAt
    }

    /// Windows shown as extra rows beyond session and weekly: Fable and credits.
    public var extraWindowCount: Int {
        [weeklyFableWindow, creditWindow].compactMap { $0 }.count
    }

    /// Every window this snapshot carries, session first.
    public var allWindows: [UsageWindow] {
        [sessionWindow, weeklyWindow, weeklySonnetWindow, weeklyFableWindow, creditWindow].compactMap { $0 }
    }
}
