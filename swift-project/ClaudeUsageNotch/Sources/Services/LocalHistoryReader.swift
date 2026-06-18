import Foundation

enum LocalHistoryReader {
    static func read(since: Date) -> [UsageRecord] {
        let claudeDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
        guard FileManager.default.fileExists(atPath: claudeDir.path) else { return [] }

        let jsonlFiles = findJSONLFiles(in: claudeDir)
        var seen = Set<String>()
        var records: [UsageRecord] = []

        for file in jsonlFiles {
            guard let lines = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for line in lines.split(separator: "\n", omittingEmptySubsequences: true) {
                guard let record = parseAssistantLine(Data(line.utf8), since: since) else { continue }
                guard seen.insert(record.uuid).inserted else { continue }
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
            obj["isApiErrorMessage"] as? Bool != true,
            let uuid      = obj["uuid"] as? String,
            let tsStr     = obj["timestamp"] as? String,
            let timestamp = iso8601Millis.date(from: tsStr),
            timestamp >= since,
            let message   = obj["message"] as? [String: Any],
            let usage     = message["usage"] as? [String: Any]
        else { return nil }

        let serverToolUse  = usage["server_tool_use"] as? [String: Any]
        let cacheCreation  = usage["cache_creation"]  as? [String: Any]
        let cwdPath        = obj["cwd"] as? String ?? ""
        let project        = (cwdPath as NSString).lastPathComponent

        return UsageRecord(
            uuid:                 uuid,
            requestId:            obj["requestId"]  as? String,
            sessionId:            obj["sessionId"]  as? String,
            parentUuid:           obj["parentUuid"] as? String,
            timestamp:            timestamp,
            cwd:                  cwdPath,
            project:              project.isEmpty ? "unknown" : project,
            gitBranch:            obj["gitBranch"]  as? String,
            model:                message["model"]  as? String ?? "unknown",
            version:              obj["version"]    as? String,
            entrypoint:           obj["entrypoint"] as? String,
            attributionSkill:     obj["attributionSkill"] as? String,
            isSidechain:          obj["isSidechain"] as? Bool ?? false,
            stopReason:           message["stop_reason"] as? String,
            serviceTier:          usage["service_tier"]  as? String,
            inputTokens:          usage["input_tokens"]                as? Int ?? 0,
            outputTokens:         usage["output_tokens"]               as? Int ?? 0,
            cacheCreationTokens:  usage["cache_creation_input_tokens"] as? Int ?? 0,
            cacheReadTokens:      usage["cache_read_input_tokens"]     as? Int ?? 0,
            ephemeral1hTokens:    cacheCreation?["ephemeral_1h_input_tokens"] as? Int ?? 0,
            ephemeral5mTokens:    cacheCreation?["ephemeral_5m_input_tokens"] as? Int ?? 0,
            webSearches:          serverToolUse?["web_search_requests"] as? Int ?? 0,
            webFetches:           serverToolUse?["web_fetch_requests"]  as? Int ?? 0
        )
    }
}
