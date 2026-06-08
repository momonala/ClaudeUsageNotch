import Foundation

enum LocalHistoryReader {
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func read(since: Date) -> [UsageRecord] {
        let claudeDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
        guard FileManager.default.fileExists(atPath: claudeDir.path) else { return [] }

        let jsonlFiles = findJSONLFiles(in: claudeDir)
        var seen = Set<String>()
        var records: [UsageRecord] = []

        for file in jsonlFiles {
            guard let lines = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for line in lines.components(separatedBy: .newlines) {
                guard let data = line.data(using: .utf8),
                      let record = parseAssistantLine(data, since: since) else { continue }
                let key = record.requestId ?? "\(record.timestamp.timeIntervalSince1970)"
                guard seen.insert(key).inserted else { continue }
                records.append(record)
            }
        }
        return records
    }

    private static func findJSONLFiles(in dir: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: dir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "jsonl" }
    }

    private static func parseAssistantLine(_ data: Data, since: Date) -> UsageRecord? {
        guard
            let obj       = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            obj["type"] as? String == "assistant",
            let tsStr     = obj["timestamp"] as? String,
            let timestamp = isoFormatter.date(from: tsStr),
            timestamp >= since,
            let message   = obj["message"] as? [String: Any],
            let usage     = message["usage"] as? [String: Any]
        else { return nil }

        return UsageRecord(
            timestamp:            timestamp,
            inputTokens:          usage["input_tokens"]                  as? Int ?? 0,
            outputTokens:         usage["output_tokens"]                 as? Int ?? 0,
            cacheCreationTokens:  usage["cache_creation_input_tokens"]   as? Int ?? 0,
            cacheReadTokens:      usage["cache_read_input_tokens"]       as? Int ?? 0,
            model:                message["model"]  as? String ?? "unknown",
            requestId:            obj["requestId"]  as? String
        )
    }
}
