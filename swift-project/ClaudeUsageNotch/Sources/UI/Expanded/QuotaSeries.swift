import Foundation

/// One point on a usage chart: tokens in the bucket, and the quota percentage
/// in force at that moment.
struct TimeBucket: Identifiable {
    let id: Date
    let tokens: Int
    let quotaPct: Double
}

/// A window's chart data: the plotted points plus the reset boundaries drawn
/// over them.
struct QuotaSeries {
    var buckets: [TimeBucket] = []
    /// Past resets inside the charted span, one per reset event.
    var resetTimes: [Date] = []
    /// The next projected reset, if a reading still carries a future one.
    var nextReset: Date?

    var allResets: [Date] { resetTimes + (nextReset.map { [$0] } ?? []) }
}

/// Session and weekly series, built from token buckets plus real quota readings.
///
/// `quotaHistory` is provider-polled ground truth, empty until a client has pushed
/// readings covering the span (see `QuotaSyncService`). Without it, `quotaPct`
/// falls back to a synthetic reconstruction, not real history.
func quotaSeries(
    buckets: [RemoteAnalytics.BucketDTO],
    quotaHistory: [RemoteAnalytics.QuotaPointDTO],
    currentPct: Double,
    resetAt: Date?,
    windowDuration: TimeInterval,
    span: DateInterval
) -> QuotaSeries {
    QuotaSeries(
        buckets: quotaHistory.isEmpty
            ? syntheticBuckets(buckets, currentPct: currentPct, resetAt: resetAt, windowDuration: windowDuration)
            : polledBuckets(buckets, quotaHistory: quotaHistory),
        resetTimes: pastResets(in: quotaHistory, within: span),
        nextReset: nextReset(in: quotaHistory)
    )
}

/// Credit history has no per-request token analog to bucket against, so each
/// polled reading becomes its own point, with no synthetic fallback.
func creditSeries(quotaHistory: [RemoteAnalytics.QuotaPointDTO], span: DateInterval) -> QuotaSeries {
    QuotaSeries(
        buckets: quotaHistory.map { TimeBucket(id: $0.timestamp, tokens: 0, quotaPct: $0.percentUsed * 100.0) },
        resetTimes: pastResets(in: quotaHistory, within: span),
        nextReset: nextReset(in: quotaHistory)
    )
}

// MARK: - Reset boundaries

private func nextReset(in history: [RemoteAnalytics.QuotaPointDTO]) -> Date? {
    let now = Date()
    return history.reversed().compactMap(\.resetsAt).first { $0 > now }
}

/// Deduped, since consecutive readings repeat the same `resets_at`.
private func pastResets(in history: [RemoteAnalytics.QuotaPointDTO], within span: DateInterval) -> [Date] {
    let times = history.compactMap(\.resetsAt).filter { $0 > span.start && $0 <= span.end }
    return Array(Set(times)).sorted()
}

// MARK: - Quota percentage per bucket

/// Hold each real reading forward until the next one. Buckets before the first
/// reading get 0 rather than a guess. `quotaHistory` is assumed chronological,
/// as the server returns it.
private func polledBuckets(
    _ buckets: [RemoteAnalytics.BucketDTO],
    quotaHistory: [RemoteAnalytics.QuotaPointDTO]
) -> [TimeBucket] {
    var nextReading = 0
    var heldPct: Double = 0
    var heldResetAt: Date?
    return buckets.map { bucket in
        while nextReading < quotaHistory.count, quotaHistory[nextReading].timestamp <= bucket.timestamp {
            heldPct = quotaHistory[nextReading].percentUsed * 100.0
            heldResetAt = quotaHistory[nextReading].resetsAt
            nextReading += 1
        }
        // The held reading's window has rolled over by this bucket: show 0
        // rather than the stale pre-reset value until a fresh poll lands.
        let rolledOver = heldResetAt.map { bucket.timestamp >= $0 } ?? false
        return TimeBucket(id: bucket.timestamp, tokens: bucket.tokens, quotaPct: rolledOver ? 0 : heldPct)
    }
}

/// Fallback when no polled readings cover the span: each bucket's running token
/// cumulative, scaled into a percentage and zeroed at every known reset boundary.
private func syntheticBuckets(
    _ buckets: [RemoteAnalytics.BucketDTO],
    currentPct: Double,
    resetAt: Date?,
    windowDuration: TimeInterval
) -> [TimeBucket] {
    guard let resetAt else {
        return unanchoredBuckets(buckets, currentPct: currentPct)
    }

    // Cycle 0 is the current window, 1 the previous one, and so on.
    func cycleIndex(of timestamp: Date) -> Int {
        Int(floor(resetAt.timeIntervalSince(timestamp) / windowDuration))
    }

    let cycleTotals = Dictionary(grouping: buckets, by: { cycleIndex(of: $0.timestamp) })
        .mapValues { $0.reduce(0) { $0 + $1.tokens } }
    let pctPerToken = percentPerToken(cycleTotals: cycleTotals, currentPct: currentPct)

    var cumulative = 0
    var activeCycle: Int?
    return buckets.map { bucket in
        let cycle = cycleIndex(of: bucket.timestamp)
        if cycle != activeCycle {
            cumulative = 0
            activeCycle = cycle
        }
        cumulative += bucket.tokens
        return TimeBucket(id: bucket.timestamp, tokens: bucket.tokens,
                          quotaPct: Double(cumulative) * pctPerToken)
    }
}

/// The token limit is ~constant across cycles, so one rate serves all of them,
/// calibrated from the current cycle — the only one whose end percent is known.
private func percentPerToken(cycleTotals: [Int: Int], currentPct: Double) -> Double {
    let currentCycleTokens = cycleTotals[0] ?? 0
    if currentPct > 0, currentCycleTokens > 0 {
        return (currentPct * 100.0) / Double(currentCycleTokens)
    }
    // Nothing to calibrate from (just reset, or no tokens yet): map the busiest
    // cycle to 100% so history stays visible instead of flat at 0.
    let maxCycleTokens = cycleTotals.values.max() ?? 0
    return maxCycleTokens > 0 ? 100.0 / Double(maxCycleTokens) : 0.0
}

/// Reset boundary unknown: one cumulative across the whole span, ending at
/// `currentPct` — or at 100% when that's 0, so the shape stays visible.
private func unanchoredBuckets(_ buckets: [RemoteAnalytics.BucketDTO], currentPct: Double) -> [TimeBucket] {
    let totalTokens = buckets.reduce(0) { $0 + $1.tokens }
    guard totalTokens > 0 else {
        return buckets.map { TimeBucket(id: $0.timestamp, tokens: $0.tokens, quotaPct: 0) }
    }
    let endPct = currentPct > 0 ? currentPct * 100.0 : 100.0
    var cumulative = 0
    return buckets.map { bucket in
        cumulative += bucket.tokens
        return TimeBucket(id: bucket.timestamp, tokens: bucket.tokens,
                          quotaPct: Double(cumulative) / Double(totalTokens) * endPct)
    }
}
