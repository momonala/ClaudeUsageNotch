import Foundation

/// Raw DTOs for the claude.ai usage endpoint.
///
/// Sample response (see docs/samples/claude_usage.json):
/// ```json
/// {
///   "five_hour":         {"utilization": 42.5, "resets_at": "2026-05-18T10:00:00Z"},
///   "seven_day":         {"utilization": 61.0, "resets_at": "2026-05-25T00:00:00Z"},
///   "seven_day_sonnet":  {"utilization": 28.0, "resets_at": "2026-05-25T00:00:00Z"}
/// }
/// ```
struct ClaudeUsageDTO: Decodable {
    let fiveHour:       Window?
    let sevenDay:       Window?
    let sevenDaySonnet: Window?
    let spend:          Spend?

    enum CodingKeys: String, CodingKey {
        case fiveHour       = "five_hour"
        case sevenDay       = "seven_day"
        case sevenDaySonnet = "seven_day_sonnet"
        case spend          = "spend"
    }

    struct Window: Decodable {
        let utilization: Double?
        let resetsAt: String?

        enum CodingKeys: String, CodingKey {
            case utilization
            case resetsAt = "resets_at"
        }
    }

    /// Org-wide monthly usage-credit pool (Team plans). Distinct from the
    /// five_hour/seven_day rate-limit windows above — this is a dollar budget,
    /// not a rolling percentage window.
    struct Spend: Decodable {
        let used: Money?
        let limit: Money?
        let percent: Double?
        let enabled: Bool?

        enum CodingKeys: String, CodingKey {
            case used, limit, percent, enabled
        }

        struct Money: Decodable {
            let amountMinor: Int?
            let exponent: Int?

            enum CodingKeys: String, CodingKey {
                case amountMinor = "amount_minor"
                case exponent
            }

            /// Minor units (cents) converted to a decimal dollar amount.
            var dollars: Double? {
                guard let amountMinor else { return nil }
                let places = exponent ?? 2
                return Double(amountMinor) / pow(10.0, Double(places))
            }
        }
    }
}

struct ClaudeBootstrapDTO: Decodable {
    let account: Account?

    struct Account: Decodable {
        let lastActiveOrgId: String?
        // lastActiveOrgId matches JSON key — no CodingKeys needed
    }
}

/// Map raw DTOs to the unified domain types.
enum ClaudeUsageMapper {
    static func snapshot(from dto: ClaudeUsageDTO, capturedAt: Date = Date()) throws -> ServiceUsageSnapshot {
        guard let fiveHour = dto.fiveHour, let utilization = fiveHour.utilization else {
            throw ProviderError.decoding("missing five_hour.utilization")
        }
        let session = UsageWindow(
            type: .session,
            percentUsed: utilization / 100.0,
            resetAt: parseISO8601(fiveHour.resetsAt),
            lastUpdated: capturedAt
        )

        let weekly: UsageWindow? = dto.sevenDay.map {
            UsageWindow(
                type: .weekly,
                percentUsed: ($0.utilization ?? 0) / 100.0,
                resetAt: parseISO8601($0.resetsAt),
                lastUpdated: capturedAt
            )
        }

        let weeklySonnet: UsageWindow? = dto.sevenDaySonnet.map {
            UsageWindow(
                type: .weeklyModel,
                percentUsed: ($0.utilization ?? 0) / 100.0,
                resetAt: parseISO8601($0.resetsAt),
                lastUpdated: capturedAt
            )
        }

        let credit: UsageWindow? = {
            guard let spend = dto.spend, spend.enabled == true,
                  let used = spend.used?.dollars, let limit = spend.limit?.dollars else { return nil }
            return UsageWindow(
                type: .monthly,
                percentUsed: (spend.percent ?? 0) / 100.0,
                usedAmount: used,
                limitAmount: limit,
                resetAt: startOfNextMonth(after: capturedAt),
                lastUpdated: capturedAt
            )
        }()

        return ServiceUsageSnapshot(
            sessionWindow: session,
            weeklyWindow: weekly,
            weeklySonnetWindow: weeklySonnet,
            creditWindow: credit,
            capturedAt: capturedAt
        )
    }

    /// The Claude usage-credit pool resets on the first of the next calendar
    /// month; the API doesn't report a `resets_at` for `spend`, unlike the
    /// five_hour/seven_day windows.
    private static func startOfNextMonth(after date: Date) -> Date? {
        let cal = Calendar.current
        guard let startOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: date)) else { return nil }
        return cal.date(byAdding: .month, value: 1, to: startOfMonth)
    }

}
