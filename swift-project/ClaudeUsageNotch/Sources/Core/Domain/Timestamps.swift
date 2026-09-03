import Foundation

/// ISO8601 with millisecond precision and a trailing `Z` — the wire format
/// shared by the sync server, Claude's usage endpoint, and local JSONL history.
let iso8601Millis: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

/// Fallback for timestamps that arrive without fractional seconds.
let iso8601Plain: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
}()

/// Either wire shape, or nil for absent or unparseable input.
func parseISO8601(_ raw: String?) -> Date? {
    guard let raw else { return nil }
    return iso8601Millis.date(from: raw) ?? iso8601Plain.date(from: raw)
}
