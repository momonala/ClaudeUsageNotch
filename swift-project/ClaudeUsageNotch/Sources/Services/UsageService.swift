import Foundation
import Combine

/// Owns the polling loop for one or more providers.
///
/// Each enabled provider gets its own independent `Task` so a slow or rate-limited
/// provider doesn't block others. Snapshots and errors are emitted via publishers
/// consumed by `UsageCoordinator`.
///
/// Failure backoff: consecutive errors double the wait interval (cap: 1 hour).
/// A 429 rate-limit forces at least 5-minute backoff regardless of the configured interval.
@MainActor
public final class UsageService {
    public static let shared = UsageService()
    private init() {}

    private let provider = ClaudeProvider()

    public let snapshotPublisher = PassthroughSubject<ServiceUsageSnapshot, Never>()
    public let errorPublisher    = PassthroughSubject<(ProviderId, ProviderError), Never>()

    private var pollTasks: [ProviderId: Task<Void, Never>] = [:]
    private var intervalSeconds: TimeInterval = 300
    private var consecutiveErrors: [ProviderId: Int] = [:]

    // MARK: - Lifecycle

    public func start(providers: [ProviderId], interval: TimeInterval) {
        stopAll()
        intervalSeconds = max(60, interval)
        for p in providers { startProvider(p) }
    }

    public func stopAll() {
        pollTasks.values.forEach { $0.cancel() }
        pollTasks.removeAll()
        consecutiveErrors.removeAll()
    }

    public func stop(providerId: ProviderId) {
        pollTasks[providerId]?.cancel()
        pollTasks.removeValue(forKey: providerId)
        consecutiveErrors.removeValue(forKey: providerId)
    }

    public func refreshNow(providerId: ProviderId? = nil) {
        if let id = providerId {
            Task { await fetchOnce(providerId: id) }
        } else {
            for id in pollTasks.keys { Task { await fetchOnce(providerId: id) } }
        }
    }

    public func updateInterval(_ seconds: TimeInterval) {
        intervalSeconds = max(60, seconds)
        let active = Array(pollTasks.keys)
        start(providers: active, interval: intervalSeconds)
    }

    // MARK: - Per-provider polling

    private func startProvider(_ providerId: ProviderId) {
        consecutiveErrors[providerId] = 0
        let task = Task { [weak self] in
            guard let self else { return }
            await self.fetchOnce(providerId: providerId)
            while !Task.isCancelled {
                let wait = self.backoffInterval(for: providerId)
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                if Task.isCancelled { break }
                await self.fetchOnce(providerId: providerId)
            }
        }
        pollTasks[providerId] = task
    }

    private func backoffInterval(for providerId: ProviderId) -> TimeInterval {
        let errs = consecutiveErrors[providerId] ?? 0
        guard errs > 0 else { return intervalSeconds }
        return min(intervalSeconds * pow(2.0, Double(min(errs, 6))), 3600)
    }

    private func fetchOnce(providerId: ProviderId) async {
        do {
            let snapshot = try await provider.fetchUsage()
            consecutiveErrors[providerId] = 0
            snapshotPublisher.send(snapshot)
        } catch let error as ProviderError {
            consecutiveErrors[providerId, default: 0] += 1
            if case .rateLimited = error {
                let minBackoffExponent = Int(ceil(log2(300 / intervalSeconds + 1)))
                consecutiveErrors[providerId] = max(
                    consecutiveErrors[providerId, default: 0],
                    minBackoffExponent
                )
            }
            errorPublisher.send((providerId, error))
        } catch {
            consecutiveErrors[providerId, default: 0] += 1
            errorPublisher.send((providerId, .unknown("unexpected")))
        }
    }
}
