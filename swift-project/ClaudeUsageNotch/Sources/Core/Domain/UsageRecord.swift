import Foundation

/// One assistant turn parsed from local JSONL history or fetched from the sync server.
///
/// `Codable` mirrors the server's JSON schema (snake_case keys) so the same type both
/// POSTs to and decodes from `claude-usage-notch-server`. Local JSONL parsing is manual
/// (see `LocalHistoryReader`) because the on-disk keys differ from the API's.
struct UsageRecord: Codable {
    let uuid: String
    let requestId: String?
    let sessionId: String?
    let parentUuid: String?
    let timestamp: Date
    let cwd: String                 // full working-directory path
    let project: String             // last path component of cwd
    let gitBranch: String?
    let model: String
    let version: String?
    let entrypoint: String?
    let attributionSkill: String?
    let isSidechain: Bool
    let stopReason: String?
    let serviceTier: String?
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
    let ephemeral1hTokens: Int
    let ephemeral5mTokens: Int
    let webSearches: Int
    let webFetches: Int

    enum CodingKeys: String, CodingKey {
        case uuid
        case requestId = "request_id"
        case sessionId = "session_id"
        case parentUuid = "parent_uuid"
        case timestamp
        case cwd
        case project
        case gitBranch = "git_branch"
        case model
        case version
        case entrypoint
        case attributionSkill = "attribution_skill"
        case isSidechain = "is_sidechain"
        case stopReason = "stop_reason"
        case serviceTier = "service_tier"
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheCreationTokens = "cache_creation_tokens"
        case cacheReadTokens = "cache_read_tokens"
        case ephemeral1hTokens = "ephemeral_1h_tokens"
        case ephemeral5mTokens = "ephemeral_5m_tokens"
        case webSearches = "web_searches"
        case webFetches = "web_fetches"
    }

    var totalTokens: Int { inputTokens + outputTokens + cacheCreationTokens }

    var estimatedCostUSD: Double {
        ModelPricing.cost(
            input: inputTokens, output: outputTokens,
            cacheCreate: cacheCreationTokens, cacheRead: cacheReadTokens,
            model: model
        )
    }
}

// MARK: - API JSON coders

extension UsageRecord {
    /// Encoder/decoder for the sync server. Timestamps are ISO8601 with a trailing `Z`.
    static let apiEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(iso8601Millis.string(from: date))
        }
        return encoder
    }()

    static let apiDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = iso8601Millis.date(from: raw) ?? iso8601Plain.date(from: raw) else {
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "Unrecognised timestamp: \(raw)"
                )
            }
            return date
        }
        return decoder
    }()
}

/// ISO8601 with millisecond precision and a trailing `Z` — the wire format shared by
/// the sync server, the API coders, and local JSONL parsing.
let iso8601Millis: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

/// Fallback for decoding timestamps that arrive without fractional seconds.
private let iso8601Plain: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
}()

enum ModelPricing {
    static func cost(input: Int, output: Int, cacheCreate: Int, cacheRead: Int, model: String) -> Double {
        let (inputRate, outputRate) = rates(for: model)
        let inputCost       = Double(input)       * inputRate          / 1_000_000
        let cacheCreateCost = Double(cacheCreate) * inputRate  * 1.25  / 1_000_000
        let outputCost      = Double(output)      * outputRate         / 1_000_000
        let cacheReadCost   = Double(cacheRead)   * inputRate  * 0.1   / 1_000_000
        return inputCost + cacheCreateCost + outputCost + cacheReadCost
    }

    private static func rates(for model: String) -> (input: Double, output: Double) {
        if model.contains("fable")  { return (10.0, 50.0) }
        if model.contains("mythos") { return (10.0, 50.0) }
        if model.contains("opus")   { return (5.0,  25.0) }
        if model.contains("haiku")  { return (1.0,   5.0) }
        return (3.0, 15.0)  // sonnet default
    }
}
