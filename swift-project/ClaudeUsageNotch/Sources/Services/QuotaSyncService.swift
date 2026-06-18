import Foundation

/// Pushes the real, provider-reported quota percentages to the sync server on
/// every poll — the ground truth the chart's "% Quota" view prefers over its
/// token-based estimate (see `UsageChartView.toTimeBuckets`).
///
/// Stateless and fire-and-forget: each snapshot is a complete, self-contained
/// reading, so a dropped POST just loses that one sample — the next poll produces
/// a fresh one. No retry cursor needed, unlike `HistorySyncService`, which must
/// not drop a token record permanently.
///
/// Disabled entirely when `apiBaseURL` is empty, same as `HistorySyncService`.
@MainActor
enum QuotaSyncService {
    private static let hostName = ProcessInfo.processInfo.hostName

    static func push(_ snapshot: ServiceUsageSnapshot, settings: AppSettings) {
        // Status-only (e.g. Gemini) and balance (e.g. DeepSeek) providers have no
        // meaningful percentage to record.
        guard snapshot.showsPercentBar, let url = quotaURL(settings) else { return }

        var payloads = [payload(for: snapshot.sessionWindow, capturedAt: snapshot.capturedAt)]
        if let weekly = snapshot.weeklyWindow {
            payloads.append(payload(for: weekly, capturedAt: snapshot.capturedAt))
        }
        if let weeklySonnet = snapshot.weeklySonnetWindow {
            payloads.append(payload(for: weeklySonnet, capturedAt: snapshot.capturedAt))
        }

        Task { await post(payloads, to: url) }
    }

    private static func payload(for window: UsageWindow, capturedAt: Date) -> QuotaSnapshotPayload {
        QuotaSnapshotPayload(
            windowType:  window.type.rawValue,
            timestamp:   capturedAt,
            percentUsed: window.percentUsed,
            resetsAt:    window.resetAt,
            source:      hostName
        )
    }

    private static func post(_ payloads: [QuotaSnapshotPayload], to url: URL) async {
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try UsageRecord.apiEncoder.encode(payloads)

            let (_, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                NSLog("[ClaudeUsageNotch] quota sync POST non-200")
                return
            }
        } catch {
            NSLog("[ClaudeUsageNotch] quota sync POST failed: \(error.localizedDescription)")
        }
    }

    private static func quotaURL(_ settings: AppSettings) -> URL? {
        let base = settings.apiBaseURL.trimmingCharacters(in: .whitespaces)
        guard !base.isEmpty, let url = URL(string: base) else { return nil }
        return url.appendingPathComponent("api/quota_snapshots")
    }
}
