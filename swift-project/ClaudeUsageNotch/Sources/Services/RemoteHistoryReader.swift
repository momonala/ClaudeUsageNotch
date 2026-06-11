import Foundation

// MARK: - Response types

struct RemoteAnalytics: Decodable {
    struct TokenTypes: Decodable {
        let inputTokens:           Int
        let outputTokens:          Int
        let cacheCreationTokens:   Int
        let cacheReadTokens:       Int
        let inputFraction:         Double
        let outputFraction:        Double
        let cacheCreationFraction: Double
        let cacheReadFraction:     Double

        enum CodingKeys: String, CodingKey {
            case inputTokens           = "input_tokens"
            case outputTokens          = "output_tokens"
            case cacheCreationTokens   = "cache_creation_tokens"
            case cacheReadTokens       = "cache_read_tokens"
            case inputFraction         = "input_fraction"
            case outputFraction        = "output_fraction"
            case cacheCreationFraction = "cache_creation_fraction"
            case cacheReadFraction     = "cache_read_fraction"
        }
    }

    struct RankedItemDTO: Decodable {
        let label:    String
        let tokens:   Int
        let fraction: Double
    }

    struct DailyValueDTO: Decodable {
        let date:  String   // "YYYY-MM-DD"
        let value: Double
    }

    struct BucketDTO: Decodable {
        let timestamp: Date
        let tokens:    Int
    }

    let sessionCost:      Double
    let todayCost:        Double
    let weeklyCost:       Double
    let monthCost:        Double
    let lifetimeCost:     Double
    let cacheHitRate:     Double
    let cacheSavingsUSD:  Double
    let tokenTypes:       TokenTypes
    let modelBreakdown:   [RankedItemDTO]
    let projectBreakdown: [RankedItemDTO]
    let skillBreakdown:   [RankedItemDTO]
    let dailyCost:        [DailyValueDTO]
    let dailySessions:    [DailyValueDTO]
    let totalWebSearches: Int
    let totalWebFetches:  Int
    let sessionBuckets:   [BucketDTO]
    let weeklyBuckets:    [BucketDTO]

    enum CodingKeys: String, CodingKey {
        case sessionCost      = "session_cost"
        case todayCost        = "today_cost"
        case weeklyCost       = "weekly_cost"
        case monthCost        = "month_cost"
        case lifetimeCost     = "lifetime_cost"
        case cacheHitRate     = "cache_hit_rate"
        case cacheSavingsUSD  = "cache_savings_usd"
        case tokenTypes       = "token_types"
        case modelBreakdown   = "model_breakdown"
        case projectBreakdown = "project_breakdown"
        case skillBreakdown   = "skill_breakdown"
        case dailyCost        = "daily_cost"
        case dailySessions    = "daily_sessions"
        case totalWebSearches = "total_web_searches"
        case totalWebFetches  = "total_web_fetches"
        case sessionBuckets   = "session_buckets"
        case weeklyBuckets    = "weekly_buckets"
    }

    func toAnalyticsData() -> AnalyticsData {
        return AnalyticsData(
            sessionCost:     sessionCost,
            todayCost:       todayCost,
            weeklyCost:      weeklyCost,
            monthCost:       monthCost,
            lifetimeCost:    lifetimeCost,
            cacheHitRate:    cacheHitRate,
            cacheSavingsUSD: cacheSavingsUSD,
            tokenTypes: TokenTypeBreakdown(
                inputFraction:        tokenTypes.inputFraction,
                outputFraction:       tokenTypes.outputFraction,
                cacheCreateFraction:  tokenTypes.cacheCreationFraction,
                cacheReadFraction:    tokenTypes.cacheReadFraction,
                inputTokens:          tokenTypes.inputTokens,
                outputTokens:         tokenTypes.outputTokens,
                cacheCreateTokens:    tokenTypes.cacheCreationTokens,
                cacheReadTokens:      tokenTypes.cacheReadTokens
            ),
            modelBreakdown:   Self.toRankedItems(modelBreakdown),
            projectBreakdown: Self.toRankedItems(projectBreakdown),
            skillBreakdown:   Self.toRankedItems(skillBreakdown),
            dailyCost:        Self.toDailyValues(dailyCost),
            dailySessions:    Self.toDailyValues(dailySessions),
            totalWebSearches: totalWebSearches,
            totalWebFetches:  totalWebFetches
        )
    }

    private static let dailyDateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt
    }()

    private static func toDailyValues(_ dtos: [DailyValueDTO]) -> [DailyValue] {
        dtos.compactMap { dto in
            guard let date = dailyDateFormatter.date(from: dto.date) else { return nil }
            return DailyValue(date: date, value: dto.value)
        }
    }

    private static func toRankedItems(_ dtos: [RankedItemDTO]) -> [RankedItem] {
        dtos.map { RankedItem(id: $0.label, label: $0.label, tokens: $0.tokens, fraction: $0.fraction) }
    }
}

// MARK: - Errors

enum RemoteFetchError: LocalizedError {
    case http(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .http(let code, let msg):
            return msg.isEmpty ? "HTTP \(code)" : "HTTP \(code): \(msg)"
        }
    }
}

// MARK: - Remote reader

enum RemoteHistoryReader {
    /// GETs `/api/analytics` and decodes the pre-aggregated response.
    /// - Throws: on network error, non-200 status, or decode failure.
    static func fetchAnalytics(
        sessionSince: Date,
        weeklySince: Date,
        monthlySince: Date,
        baseURL: URL
    ) async throws -> RemoteAnalytics {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("api/analytics"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "session_since",  value: iso8601Millis.string(from: sessionSince)),
            URLQueryItem(name: "weekly_since",   value: iso8601Millis.string(from: weeklySince)),
            URLQueryItem(name: "monthly_since",  value: iso8601Millis.string(from: monthlySince)),
        ]
        guard let url = components?.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.timeoutInterval = 2

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard statusCode == 200 else {
            let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["error"] ?? ""
            throw RemoteFetchError.http(statusCode: statusCode, message: msg)
        }
        return try UsageRecord.apiDecoder.decode(RemoteAnalytics.self, from: data)
    }
}
