import Foundation

/// Which window inside a provider this usage belongs to.
public enum UsageWindowType: String, Codable, Hashable {
    case session     // Claude's 5-hour rolling window
    case weekly      // Claude's 7-day window
    case weeklyModel // Claude Pro's 7-day Sonnet sub-window
    case monthly     // Calendar-month billing window (OpenAI spend vs limit)
    case daily       // Rolling daily quota (Gemini Code Assist per-model buckets)
    case connected   // Provider authenticated but exposes no quota endpoint (Gemini, Perplexity)
    case balance     // Provider reports a remaining credit balance, not a % (DeepSeek)
}

/// Health classification derived from percent used + reset proximity.
public enum UsageStatus: String, Codable, Hashable {
    case healthy   // under warning threshold
    case warning   // approaching limit
    case critical  // at or past hard threshold
    case unknown   // no data yet
}

/// A single rolling usage window inside a provider snapshot.
///
/// `percentUsed` is normalized to 0...1. `usedAmount` and `limitAmount` are
/// kept as optional `Double`s in case the provider only reports a percentage
/// (which is the case for Claude today — see ClaudeUsageBar reference).
public struct UsageWindow: Codable, Hashable {
    public let type: UsageWindowType
    public let percentUsed: Double          // 0.0 ... 1.0+
    public let usedAmount: Double?
    public let limitAmount: Double?
    public let resetAt: Date?
    public let lastUpdated: Date
    /// Pre-formatted short text for windows without a percentage (e.g. a
    /// `.balance` window's "$110.00"). Nil for percentage windows.
    public let label: String?

    public init(
        type: UsageWindowType,
        percentUsed: Double,
        usedAmount: Double? = nil,
        limitAmount: Double? = nil,
        resetAt: Date? = nil,
        lastUpdated: Date = Date(),
        label: String? = nil
    ) {
        self.type = type
        self.percentUsed = percentUsed
        self.usedAmount = usedAmount
        self.limitAmount = limitAmount
        self.resetAt = resetAt
        self.lastUpdated = lastUpdated
        self.label = label
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

    /// Known rolling-window length for this type. Nil when pace can't be inferred.
    public var windowDuration: TimeInterval? {
        switch type {
        case .session:              return 5 * 3600
        case .weekly, .weeklyModel: return 7 * 24 * 3600
        case .daily:                return 24 * 3600
        case .monthly:              return 30 * 24 * 3600
        case .connected, .balance:  return nil
        }
    }

    /// How far through the rolling window we are by elapsed time (0…1).
    /// E.g. 20% of a week elapsed → 0.2. Nil when reset time or duration is unknown.
    public func expectedProgress(now: Date = Date()) -> Double? {
        guard let resetAt, let duration = windowDuration, duration > 0 else { return nil }
        let remaining = resetAt.timeIntervalSince(now)
        let elapsed = duration - remaining
        return min(1, max(0, elapsed / duration))
    }

    /// Compact reset countdown for tight spaces, e.g. "1h 12m". Nil if no resetAt.
    public func timeToResetShortString(now: Date = Date()) -> String? {
        guard let resetAt else { return nil }
        let interval = resetAt.timeIntervalSince(now)
        if interval <= 0 { return "soon" }
        let (days, hours, minutes) = timeComponents(from: interval)
        if days > 0 { return hours > 0 ? "\(days)d \(hours)h" : "\(days)d" }
        if hours > 0 { return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h" }
        return "\(max(minutes, 1))m"
    }

    /// Coarsest useful reset countdown — at most three characters ("45m",
    /// "2h", "1d") — for the compact pill's fixed label slot.
    ///
    /// The pill is exactly as wide as the hardware cutout in every state, so a
    /// countdown shown there has to fit the same slot the "%" readout uses.
    /// `timeToResetShortString`'s "2h 58m" does not, and the pill used to grow
    /// 32 pt to make room for it — which pushed it out past the black housing
    /// on both sides for the whole time the session sat at its limit.
    ///
    /// Components are floored, matching `timeToResetShortString`: "2h" means at
    /// least two hours to go, never less.
    public func timeToResetCompactString(now: Date = Date()) -> String? {
        guard let resetAt else { return nil }
        let interval = resetAt.timeIntervalSince(now)
        if interval <= 0 { return "now" }
        let (days, hours, minutes) = timeComponents(from: interval)
        if days > 0  { return "\(days)d" }
        if hours > 0 { return "\(hours)h" }
        return "\(max(minutes, 1))m"
    }

    /// Human-readable countdown to reset, e.g. "Resets in 1h 12m".
    public func timeToResetString(now: Date = Date()) -> String? {
        guard let resetAt else { return nil }
        let interval = resetAt.timeIntervalSince(now)
        if interval <= 0 { return "Resetting…" }
        let (days, hours, minutes) = timeComponents(from: interval)
        if days > 0 { return hours > 0 ? "Resets in \(days)d \(hours)h" : "Resets in \(days)d" }
        if hours > 0 { return "Resets in \(hours)h \(minutes)m" }
        return "Resets in \(max(minutes, 1))m"
    }

    /// When the window resets — time for short windows (session/daily), date for longer ones.
    public func resetAtLabel() -> String? {
        guard let resetAt else { return nil }
        switch type {
        case .session, .daily:
            return Self.resetTimeFormatter.string(from: resetAt)
        case .weekly, .weeklyModel, .monthly:
            return Self.resetDateFormatter.string(from: resetAt)
        case .connected, .balance:
            return nil
        }
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

    private func timeComponents(from interval: TimeInterval) -> (days: Int, hours: Int, minutes: Int) {
        let totalMinutes = Int(interval / 60)
        let totalHours   = totalMinutes / 60
        return (days: totalHours / 24, hours: totalHours % 24, minutes: totalMinutes % 60)
    }
}
