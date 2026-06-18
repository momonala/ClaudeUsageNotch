import Foundation
import Combine

/// Pushes locally-parsed `UsageRecord`s to the sync server on a timer.
///
/// Disabled entirely when `apiBaseURL` is empty. The `lastSyncedAt` cursor only
/// advances on a 200 response, so a failed POST is retried on the next tick; the
/// server dedupes by `uuid`, making retries safe.
@MainActor
final class HistorySyncService {
    private let settings: AppSettings
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var isSyncing = false

    private static let lastSyncedKey = "claudeusagenotch.lastSyncedAt"

    init(settings: AppSettings) {
        self.settings = settings
    }

    func start() {
        // Reschedule when the interval changes, or the URL settles (debounced so we
        // don't fire a sync on every keystroke while the user types the URL).
        let urlChanges = settings.$apiBaseURL.dropFirst()
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .map { _ in () }
        let intervalChanges = settings.$syncIntervalSeconds.dropFirst().map { _ in () }

        urlChanges.merge(with: intervalChanges)
            .sink { [weak self] in self?.reschedule() }
            .store(in: &cancellables)

        reschedule()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func reschedule() {
        timer?.invalidate()
        guard !settings.apiBaseURL.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        timer = Timer.scheduledTimer(
            withTimeInterval: settings.syncIntervalSeconds, repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.syncNow() }
        }
        Task { await syncNow() }
    }

    private var lastSyncedAt: Date {
        get {
            let t = UserDefaults.standard.double(forKey: Self.lastSyncedKey)
            return t > 0 ? Date(timeIntervalSince1970: t) : .distantPast
        }
        set { UserDefaults.standard.set(newValue.timeIntervalSince1970, forKey: Self.lastSyncedKey) }
    }

    private func syncNow() async {
        guard let url = recordsURL() else { return }
        // A slow scan/POST can overlap the next timer tick (or a settings-change
        // reschedule); both would read the same cursor and push overlapping batches.
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        let since = lastSyncedAt
        let syncStart = Date()
        let records = await Task.detached(priority: .utility) {
            LocalHistoryReader.read(since: since)
        }.value

        guard !records.isEmpty else {
            lastSyncedAt = syncStart
            return
        }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try UsageRecord.apiEncoder.encode(records)

            let (_, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                NSLog("[ClaudeUsageNotch] sync POST non-200; will retry next tick")
                return
            }
            lastSyncedAt = syncStart
        } catch {
            NSLog("[ClaudeUsageNotch] sync POST failed: \(error.localizedDescription)")
        }
    }

    private func recordsURL() -> URL? {
        let base = settings.apiBaseURL.trimmingCharacters(in: .whitespaces)
        guard !base.isEmpty, let url = URL(string: base) else { return nil }
        return url.appendingPathComponent("api/records")
    }
}
