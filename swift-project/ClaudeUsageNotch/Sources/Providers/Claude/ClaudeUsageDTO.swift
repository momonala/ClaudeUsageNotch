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

    enum CodingKeys: String, CodingKey {
        case fiveHour       = "five_hour"
        case sevenDay       = "seven_day"
        case sevenDaySonnet = "seven_day_sonnet"
    }

    struct Window: Decodable {
        let utilization: Double?
        let resetsAt: String?

        enum CodingKeys: String, CodingKey {
            case utilization = "utilization"
            case resetsAt    = "resets_at"
        }
    }
}

struct ClaudeBootstrapDTO: Decodable {
    let account: Account?

    struct Account: Decodable {
        let lastActiveOrgId: String?

        enum CodingKeys: String, CodingKey {
            case lastActiveOrgId = "lastActiveOrgId"
        }
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
            resetAt: parseISO(fiveHour.resetsAt),
            lastUpdated: capturedAt
        )

        let weekly: UsageWindow? = dto.sevenDay.map {
            UsageWindow(
                type: .weekly,
                percentUsed: ($0.utilization ?? 0) / 100.0,
                resetAt: parseISO($0.resetsAt),
                lastUpdated: capturedAt
            )
        }

        let weeklySonnet: UsageWindow? = dto.sevenDaySonnet.map {
            UsageWindow(
                type: .weeklyModel,
                percentUsed: ($0.utilization ?? 0) / 100.0,
                resetAt: parseISO($0.resetsAt),
                lastUpdated: capturedAt
            )
        }

        return ServiceUsageSnapshot(
            providerId: .claude,
            primaryWindow: session,
            secondaryWindow: weekly,
            tertiaryWindow: weeklySonnet,
            capturedAt: capturedAt
        )
    }

    private static let isoWithFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoNoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func parseISO(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        return isoWithFrac.date(from: raw) ?? isoNoFrac.date(from: raw)
    }
}
