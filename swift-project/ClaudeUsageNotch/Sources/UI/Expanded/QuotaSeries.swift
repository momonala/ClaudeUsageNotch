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
/// `quotaHistory` is provider-polled quota readings (the `quota_snapshots`
/// table) — ground truth. When present, `quotaPct` holds each reading forward
/// to the next one, which needs no reset-awareness: a reset shows up as a real
/// drop in the polled data.
///
/// It is empty until a client has been pushing readings (see `QuotaSyncService`)
/// for long enough to cover the requested span. In that case `quotaPct` falls
/// back to a *synthetic reconstruction* that scales each bucket's cumulative
/// token share by the current window percentage. That approximates "% quota
/// over time"; it is not real historical quota and shouldn't be read as such.
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
/// polled reading becomes its own point — and there's no synthetic fallback,
/// so the chart is simply empty until readings exist.
func creditSeries(quotaHistory: [RemoteAnalytics.QuotaPointDTO], span: DateInterval) -> QuotaSeries {
    QuotaSeries(
        buckets: quotaHistory.map { TimeBucket(id: $0.timestamp, tokens: 0, quotaPct: $0.percentUsed * 100.0) },
        resetTimes: pastResets(in: quotaHistory, within: span),
        nextReset: nextReset(in: quotaHistory)
    )
}

// MARK: - Reset boundaries

/// Most recent reading whose `resets_at` is still in the future.
private func nextReset(in history: [RemoteAnalytics.QuotaPointDTO]) -> Date? {
    let now = Date()
    return history.reversed().compactMap(\.resetsAt).first { $0 > now }
}

/// Unique `resets_at` values already inside `span` — one per reset that happened.
private func pastResets(in history: [RemoteAnalytics.QuotaPointDTO], within span: DateInterval) -> [Date] {
    let times = history.compactMap(\.resetsAt).filter { $0 > span.start && $0 <= span.end }
    return Array(Set(times)).sorted()
}

// MARK: - Quota percentage per bucket

/// Ground-truth path: hold each real reading forward until the next one (a step
/// function). Buckets before the first reading get 0 rather than a guess —
/// honest about there being no real data for that stretch. `quotaHistory` is
/// assumed chronological, as the server returns it.
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
        // The held reading's own reset time has passed by this bucket — its
        // window already rolled over, so show 0 rather than pinning to the
        // stale pre-reset value until a fresh poll lands.
        let rolledOver = heldResetAt.map { bucket.timestamp >= $0 } ?? false
        return TimeBucket(id: bucket.timestamp, tokens: bucket.tokens, quotaPct: rolledOver ? 0 : heldPct)
    }
}

/// Fallback when no polled readings cover the span: scale each bucket's running
/// token cumulative into a percentage.
///
/// Reset-aware when `resetAt` is known — the rolling window resets every
/// `windowDuration` ending at `resetAt`, so the cumulative zeroes at each
/// boundary instead of climbing monotonically across the whole span. Tokens
/// convert at a constant rate anchored so the *current* cycle ends at
/// `currentPct`; older cycles use the same rate, their true end percent being
/// unknown. `buckets` are assumed chronological, as the cumulative requires.
private func syntheticBuckets(
    _ buckets: [RemoteAnalytics.BucketDTO],
    currentPct: Double,
    resetAt: Date?,
    windowDuration: TimeInterval
) -> [TimeBucket] {
    guard let resetAt else {
        return unanchoredBuckets(buckets, currentPct: currentPct)
    }

    // Cycle 0 is the current window (the `windowDuration` ending at `resetAt`),
    // 1 the previous one, etc. The index decreases as time moves forward.
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

/// Percent points per token. The token limit is ~constant across cycles, so a
/// single rate keeps their relative magnitudes honest; calibrate it from the
/// current cycle, the only one whose end percent is actually known.
private func percentPerToken(cycleTotals: [Int: Int], currentPct: Double) -> Double {
    let currentCycleTokens = cycleTotals[0] ?? 0
    if currentPct > 0, currentCycleTokens > 0 {
        return (currentPct * 100.0) / Double(currentCycleTokens)
    }
    // The current cycle can't calibrate (just reset, or no tokens yet). Rather
    // than collapse every past cycle to a flat 0, map the busiest cycle's
    // cumulative to 100% so the history and its resets stay visible. Snaps back
    // to the anchored scale as soon as the current cycle records any usage.
    let maxCycleTokens = cycleTotals.values.max() ?? 0
    return maxCycleTokens > 0 ? 100.0 / Double(maxCycleTokens) : 0.0
}

/// Fallback when the reset boundary is unknown: one cumulative across the whole
/// span, normalized to end at `currentPct` — or at 100% when that's 0 (just
/// reset), so the curve's shape stays visible instead of going flat.
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
