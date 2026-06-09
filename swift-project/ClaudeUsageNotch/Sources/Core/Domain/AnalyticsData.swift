import Foundation

struct RankedItem: Identifiable {
    let id: String
    let label: String
    let tokens: Int
    let fraction: Double
}

struct TokenTypeBreakdown {
    let inputFraction:       Double
    let outputFraction:      Double
    let cacheCreateFraction: Double
    let cacheReadFraction:   Double

    var inputTokens:       Int
    var outputTokens:      Int
    var cacheCreateTokens: Int
    var cacheReadTokens:   Int
}

struct DailyValue: Identifiable {
    let date:  Date
    let value: Double
    var id: Date { date }
}

struct AnalyticsData {
    let sessionCost:       Double
    let weeklyCost:        Double

    let cacheHitRate:      Double   // cacheRead / (input + cacheRead + cacheCreate), 0–1
    let cacheSavingsUSD:   Double

    let tokenTypes:        TokenTypeBreakdown

    let modelBreakdown:    [RankedItem]   // top 3
    let projectBreakdown:  [RankedItem]   // top 5
    let skillBreakdown:    [RankedItem]   // top 5, nil skills excluded

    let dailyCost:         [DailyValue]   // 7 days
    let dailySessions:     [DailyValue]   // 7 days (count of distinct sessionIds)

    let totalWebSearches:  Int
    let totalWebFetches:   Int

    static let empty = AnalyticsData(
        sessionCost: 0, weeklyCost: 0,
        cacheHitRate: 0, cacheSavingsUSD: 0,
        tokenTypes: TokenTypeBreakdown(inputFraction: 0, outputFraction: 0,
                                       cacheCreateFraction: 0, cacheReadFraction: 0,
                                       inputTokens: 0, outputTokens: 0,
                                       cacheCreateTokens: 0, cacheReadTokens: 0),
        modelBreakdown: [], projectBreakdown: [], skillBreakdown: [],
        dailyCost: [], dailySessions: [], totalWebSearches: 0, totalWebFetches: 0
    )

    static func compute(sessionRecords: [UsageRecord], weeklyRecords: [UsageRecord]) -> AnalyticsData {
        let sessionCost = sessionRecords.reduce(0.0) { $0 + $1.estimatedCostUSD }

        let cal = Calendar.current
        var weeklyCost       = 0.0
        var totalInput       = 0
        var totalCacheCreate = 0
        var totalCacheRead   = 0
        var totalOutput      = 0
        var totalWebSearches = 0
        var totalWebFetches  = 0
        var costByDay:     [Date: Double]      = [:]
        var sessionsByDay: [Date: Set<String>] = [:]
        var modelTokens:   [String: Int]       = [:]
        var projectTokens: [String: Int]       = [:]
        var skillTokens:   [String: Int]       = [:]

        for r in weeklyRecords {
            weeklyCost       += r.estimatedCostUSD
            totalInput       += r.inputTokens
            totalCacheCreate += r.cacheCreationTokens
            totalCacheRead   += r.cacheReadTokens
            totalOutput      += r.outputTokens
            totalWebSearches += r.webSearches
            totalWebFetches  += r.webFetches

            let day = cal.startOfDay(for: r.timestamp)
            costByDay[day, default: 0]    += r.estimatedCostUSD
            if let sid = r.sessionId { sessionsByDay[day, default: []].insert(sid) }

            modelTokens[r.model, default: 0]     += r.totalTokens
            projectTokens[r.project, default: 0] += r.totalTokens
            if let skill = r.attributionSkill, !skill.isEmpty {
                skillTokens[skill, default: 0] += r.totalTokens
            }
        }

        let cacheableDenom = totalInput + totalCacheRead + totalCacheCreate
        let cacheHitRate   = cacheableDenom > 0 ? Double(totalCacheRead) / Double(cacheableDenom) : 0

        // Savings: cache reads billed at ~10% of input rate — approximate as 90% discount vs full input cost
        let avgInputRate = weeklyRecords.isEmpty ? 3.0 : weeklyCost / Double(max(1, cacheableDenom)) * 1_000_000
        let cacheSavings = Double(totalCacheRead) * avgInputRate * 0.9 / 1_000_000

        let allTokens = Double(max(1, totalInput + totalOutput + totalCacheCreate + totalCacheRead))
        let tokenTypes = TokenTypeBreakdown(
            inputFraction:       Double(totalInput)       / allTokens,
            outputFraction:      Double(totalOutput)      / allTokens,
            cacheCreateFraction: Double(totalCacheCreate) / allTokens,
            cacheReadFraction:   Double(totalCacheRead)   / allTokens,
            inputTokens:       totalInput,
            outputTokens:      totalOutput,
            cacheCreateTokens: totalCacheCreate,
            cacheReadTokens:   totalCacheRead
        )

        let now  = Date()
        let days = (0..<7).map { i -> Date in
            cal.startOfDay(for: cal.date(byAdding: .day, value: -(6 - i), to: now)!)
        }
        let dailyCost     = days.map { DailyValue(date: $0, value: costByDay[$0] ?? 0) }
        let dailySessions = days.map { DailyValue(date: $0, value: Double(sessionsByDay[$0]?.count ?? 0)) }

        return AnalyticsData(
            sessionCost:      sessionCost,
            weeklyCost:       weeklyCost,
            cacheHitRate:     cacheHitRate,
            cacheSavingsUSD:  cacheSavings,
            tokenTypes:       tokenTypes,
            modelBreakdown:   toRanked(modelTokens,   top: 3),
            projectBreakdown: toRanked(projectTokens, top: 5),
            skillBreakdown:   toRanked(skillTokens,   top: 5),
            dailyCost:        dailyCost,
            dailySessions:    dailySessions,
            totalWebSearches: totalWebSearches,
            totalWebFetches:  totalWebFetches
        )
    }

    // MARK: - Helpers

    private static func toRanked(_ grouped: [String: Int], top: Int) -> [RankedItem] {
        let total = grouped.values.reduce(0, +)
        guard total > 0 else { return [] }
        return grouped
            .sorted { $0.value > $1.value }
            .prefix(top)
            .map { RankedItem(id: $0.key, label: $0.key, tokens: $0.value,
                              fraction: Double($0.value) / Double(total)) }
    }
}
