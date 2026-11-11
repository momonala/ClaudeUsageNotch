import Foundation

/// One assistant JSONL line parsed from local history, POSTed to the sync server.
///
/// Claude Code writes one line per content block of a response, each repeating the
/// request's usage; the server collapses them into one row per `request_id`.
/// Keys mirror the server's snake_case schema.
struct UsageRecord: Encodable {
    let requestId: String
    let sessionId: String?
    let timestamp: Date
    let cwd: String
    let gitBranch: String?
    let model: String
    let attributionSkill: String?
    let isSidechain: Bool
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
    let ephemeral1hTokens: Int

    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case sessionId = "session_id"
        case timestamp
        case cwd
        case gitBranch = "git_branch"
        case model
        case attributionSkill = "attribution_skill"
        case isSidechain = "is_sidechain"
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheCreationTokens = "cache_creation_tokens"
        case cacheReadTokens = "cache_read_tokens"
        case ephemeral1hTokens = "ephemeral_1h_tokens"
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
