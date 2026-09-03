import Foundation

/// Which of Claude's quota windows a usage reading belongs to.
public enum UsageWindowType: String, Codable, Hashable {
    case session     // 5-hour rolling window
    case weekly      // 7-day window
    case weeklyModel // 7-day Sonnet sub-window (Pro plans)
    case monthly     // Monthly usage-credit pool (Team plans)
}

/// Health classification derived from percent used + reset proximity.
public enum UsageStatus: String, Codable, Hashable {
    case healthy   // under warning threshold
    case warning   // approaching limit
    case critical  // at or past hard threshold
    case unknown   // no data yet
}

/// One rolling usage window inside a snapshot.
///
/// `percentUsed` is normalized to 0...1. `usedAmount`/`limitAmount` are only
/// reported for the dollar-denominated `.monthly` credit pool.
public struct UsageWindow: Codable, Hashable {
    public let type: UsageWindowType
    public let percentUsed: Double          // 0.0 ... 1.0+
    public let usedAmount: Double?
    public let limitAmount: Double?
    public let resetAt: Date?
    public let lastUpdated: Date

    public init(
        type: UsageWindowType,
        percentUsed: Double,
        usedAmount: Double? = nil,
        limitAmount: Double? = nil,
        resetAt: Date? = nil,
        lastUpdated: Date = Date()
    ) {
        self.type = type
        self.percentUsed = percentUsed
        self.usedAmount = usedAmount
        self.limitAmount = limitAmount
        self.resetAt = resetAt
        self.lastUpdated = lastUpdated
    }

    /// Percent-used cutoffs for the color/health classification (distinct from
    /// `AppSettings.thresholds`, which drives *notifications*). Bar colors live here.
    public static let warningThreshold  = 0.7
    public static let criticalThreshold = 0.9

    /// Derive a health classification from percent used.
    public var status: UsageStatus {
        if percentUsed >= Self.criticalThreshold { return .critical }
        if percentUsed >= Self.warningThreshold  { return .warning }
        return .healthy
    }

    /// Whether the window is at or past its limit.
    public var isAtLimit: Bool { percentUsed >= 1.0 }

    /// Whether `resetAt` has passed, meaning a fresh cycle should already be
    /// underway even if the last poll hasn't confirmed it yet.
    public func hasResetPassed(now: Date = Date()) -> Bool {
        guard let resetAt else { return false }
        return now >= resetAt
    }

    /// Usage percent to display: the last polled value, optimistically zeroed
    /// once `resetAt` has passed. A poll always lands within moments of a
    /// reset, so the UI shouldn't stay pinned to the stale pre-reset value
    /// in the meantime.
    public func effectivePercentUsed(now: Date = Date()) -> Double {
        hasResetPassed(now: now) ? 0 : percentUsed
    }

    /// Health classification for `effectivePercentUsed`.
    public func effectiveStatus(now: Date = Date()) -> UsageStatus {
        hasResetPassed(now: now) ? .healthy : status
    }

    /// Rolling-window length for this type.
    public var windowDuration: TimeInterval {
        switch type {
        case .session:              return 5 * 3600
        case .weekly, .weeklyModel: return 7 * 24 * 3600
        case .monthly:              return 30 * 24 * 3600
        }
    }

    /// How far through the rolling window we are by elapsed time (0…1).
    /// E.g. 20% of a week elapsed → 0.2. Nil when reset time or duration is unknown.
    public func expectedProgress(now: Date = Date()) -> Double? {
        guard let resetAt else { return nil }
        let elapsed = windowDuration - resetAt.timeIntervalSince(now)
        return min(1, max(0, elapsed / windowDuration))
    }

    /// Reset countdown at two useful widths, plus the sentence form.
    ///
    /// `.compact` is at most three characters ("45m", "2h", "1d") because the
    /// pill is exactly as wide as the hardware cutout and a countdown shown
    /// there has to fit the same slot the "%" readout uses. Components are
    /// floored in both widths: "2h" means at least two hours to go, never less.
    public enum CountdownWidth {
        /// Two units where they help: "1h 12m", "3d 4h".
        case short
        /// Largest unit only: "45m", "2h", "1d".
        case compact
    }

    public func timeToReset(_ width: CountdownWidth, now: Date = Date()) -> String? {
        guard let resetAt else { return nil }
        let interval = resetAt.timeIntervalSince(now)
        guard interval > 0 else { return width == .compact ? "now" : "soon" }

        let totalMinutes = Int(interval / 60)
        let totalHours   = totalMinutes / 60
        let (days, hours, minutes) = (totalHours / 24, totalHours % 24, totalMinutes % 60)

        if days > 0  { return width == .compact || hours == 0 ? "\(days)d" : "\(days)d \(hours)h" }
        if hours > 0 { return width == .compact || minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m" }
        return "\(max(minutes, 1))m"
    }

    /// Sentence form for roomier spots, e.g. "Resets in 1h 12m".
    public func timeToResetString(now: Date = Date()) -> String? {
        guard let resetAt else { return nil }
        guard resetAt > now else { return "Resetting…" }
        return timeToReset(.short, now: now).map { "Resets in \($0)" }
    }

    /// When the window resets — time of day for the 5h session, date for longer windows.
    public func resetAtLabel() -> String? {
        guard let resetAt else { return nil }
        return type == .session
            ? Self.resetTimeFormatter.string(from: resetAt)
            : Self.resetDateFormatter.string(from: resetAt)
    }

    private static let resetTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    private static let resetDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE d MMM, h:mm a"
        return f
    }()
}
