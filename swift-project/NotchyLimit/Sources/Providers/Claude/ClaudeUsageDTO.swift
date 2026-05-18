import Foundation

/// Raw DTOs for the claude.ai usage endpoint.
///
/// Sample response (see docs/samples/claude_usage.json):
/// ```json
/// {
///   "five_hour":         {"utilization": 42.5, "resets_at": "..."},
///   "seven_day":         {"utilization": 61.0, "resets_at": "..."},
///   "seven_day_sonnet":  {"utilization": 28.0, "resets_at": "..."}
/// }
/// ```
struct ClaudeUsageDTO: Decodable {
    let five_hour: Window?
    let seven_day: Window?
    let seven_day_sonnet: Window?

    struct Window: Decodable {
        let utilization: Double?
        let resets_at: String?
    }
}

struct ClaudeBootstrapDTO: Decodable {
    let account: Account?
    struct Account: Decodable {
        let lastActiveOrgId: String?
    }
}

/// Map raw DTOs to the unified domain types.
enum ClaudeUsageMapper {
    static func snapshot(from dto: ClaudeUsageDTO, capturedAt: Date = Date()) throws -> ServiceUsageSnapshot {
        guard let fiveHour = dto.five_hour, let utilization = fiveHour.utilization else {
            throw ProviderError.decoding("missing five_hour.utilization")
        }
        let session = UsageWindow(
            type: .session,
            percentUsed: utilization / 100.0,
            resetAt: parseISO(fiveHour.resets_at),
            lastUpdated: capturedAt
        )

        let weekly: UsageWindow? = dto.seven_day.map {
            UsageWindow(
                type: .weekly,
                percentUsed: ($0.utilization ?? 0) / 100.0,
                resetAt: parseISO($0.resets_at),
                lastUpdated: capturedAt
            )
        }

        let weeklySonnet: UsageWindow? = dto.seven_day_sonnet.map {
            UsageWindow(
                type: .weeklyModel,
                percentUsed: ($0.utilization ?? 0) / 100.0,
                resetAt: parseISO($0.resets_at),
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

    private static func parseISO(_ raw: String?) -> Date? {
        guard let raw = raw else { return nil }
        let withFrac = ISO8601DateFormatter()
        withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFrac.date(from: raw) { return d }
        let noFrac = ISO8601DateFormatter()
        noFrac.formatOptions = [.withInternetDateTime]
        return noFrac.date(from: raw)
    }
}
