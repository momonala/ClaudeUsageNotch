import Foundation

/// One polled quota reading, POSTed to the sync server's `quota_snapshots` table.
/// Mirrors the server's snake_case schema — see claude-usage-notch-server's
/// `QuotaSnapshot` model and `POST /api/quota_snapshots`.
struct QuotaSnapshotPayload: Encodable {
    let windowType:   String
    let timestamp:    Date
    let percentUsed:  Double
    let resetsAt:     Date?
    let source:       String?

    enum CodingKeys: String, CodingKey {
        case windowType  = "window_type"
        case timestamp
        case percentUsed = "percent_used"
        case resetsAt    = "resets_at"
        case source
    }
}
