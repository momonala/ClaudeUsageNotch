import Foundation

/// A complete snapshot from Claude at a moment in time.
/// The notch UI consumes one of these and binds compact + expanded views to it.
public struct ServiceUsageSnapshot: Codable, Hashable {
    public let sessionWindow: UsageWindow           // 5-hour rolling session
    public let weeklyWindow: UsageWindow?           // 7-day window
    public let weeklySonnetWindow: UsageWindow?     // 7-day Sonnet sub-window (Pro only)
    public let capturedAt: Date

    public init(
        sessionWindow: UsageWindow,
        weeklyWindow: UsageWindow? = nil,
        weeklySonnetWindow: UsageWindow? = nil,
        capturedAt: Date = Date()
    ) {
        self.sessionWindow = sessionWindow
        self.weeklyWindow = weeklyWindow
        self.weeklySonnetWindow = weeklySonnetWindow
        self.capturedAt = capturedAt
    }

    /// True when the provider authenticated successfully but exposes no usable
    /// quota/usage endpoint. The UI shows an "Active" indicator instead of a
    /// misleading 0% bar for these snapshots.
    public var isStatusOnly: Bool {
        sessionWindow.type == .connected
    }

    /// True when the provider reports a remaining credit balance instead of a percentage.
    public var isBalance: Bool {
        sessionWindow.type == .balance
    }

    /// True when this snapshot has a meaningful 0...1 usage percentage to chart.
    public var showsPercentBar: Bool {
        !isStatusOnly && !isBalance
    }

    /// Short text for compact spaces: "42%", a balance like "$110.00", or "Active".
    public var shortLabel: String {
        if isStatusOnly { return "Active" }
        if isBalance    { return sessionWindow.label ?? "—" }
        return "\(Int((sessionWindow.percentUsed * 100).rounded()))%"
    }

    /// Builds a status-only snapshot with no quota endpoint.
    public static func connected(capturedAt: Date = Date()) -> ServiceUsageSnapshot {
        let window = UsageWindow(
            type: .connected,
            percentUsed: 0,
            lastUpdated: capturedAt
        )
        return ServiceUsageSnapshot(sessionWindow: window, capturedAt: capturedAt)
    }

    /// Builds a balance snapshot. `label` is the pre-formatted amount, e.g. "$110.00".
    public static func balance(label: String, capturedAt: Date = Date()) -> ServiceUsageSnapshot {
        let window = UsageWindow(
            type: .balance,
            percentUsed: 0,
            lastUpdated: capturedAt,
            label: label
        )
        return ServiceUsageSnapshot(sessionWindow: window, capturedAt: capturedAt)
    }

    /// The worst status across windows, used for the top-level pill color.
    public var combinedStatus: UsageStatus {
        let candidates: [UsageStatus] = [
            sessionWindow.status,
            weeklyWindow?.status ?? .healthy,
            weeklySonnetWindow?.status ?? .healthy
        ]
        if candidates.contains(.critical) { return .critical }
        if candidates.contains(.warning)  { return .warning }
        return .healthy
    }
}
