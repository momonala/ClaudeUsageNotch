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
    let todayCost:         Double
    let weeklyCost:        Double
    let monthCost:         Double
    let lifetimeCost:      Double

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

    var averageDailyCost: Double {
        weeklyCost / 7
    }

    static let empty = AnalyticsData(
        sessionCost: 0, todayCost: 0, weeklyCost: 0, monthCost: 0, lifetimeCost: 0,
        cacheHitRate: 0, cacheSavingsUSD: 0,
        tokenTypes: TokenTypeBreakdown(inputFraction: 0, outputFraction: 0,
                                       cacheCreateFraction: 0, cacheReadFraction: 0,
                                       inputTokens: 0, outputTokens: 0,
                                       cacheCreateTokens: 0, cacheReadTokens: 0),
        modelBreakdown: [], projectBreakdown: [], skillBreakdown: [],
        dailyCost: [], dailySessions: [], totalWebSearches: 0, totalWebFetches: 0
    )

}
