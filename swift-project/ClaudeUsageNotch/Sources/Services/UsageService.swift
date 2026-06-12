import Foundation
import Combine

/// Owns the polling loop for Claude.
///
/// Failure backoff: consecutive errors double the wait interval (cap: 1 hour).
/// A 429 rate-limit forces at least 5-minute backoff regardless of the configured interval.
@MainActor
public final class UsageService {
    public static let shared = UsageService()
    private init() {}

    private let provider = ClaudeProvider()

    public let snapshotPublisher = PassthroughSubject<ServiceUsageSnapshot, Never>()
    public let errorPublisher    = PassthroughSubject<ProviderError, Never>()

    private var pollTask: Task<Void, Never>?
    private var intervalSeconds: TimeInterval = 300
    private var consecutiveErrors: Int = 0

    // MARK: - Lifecycle

    public func start(interval: TimeInterval) {
        stopAll()
        intervalSeconds = max(60, interval)
        startPolling()
    }

    public func stopAll() {
        pollTask?.cancel()
        pollTask = nil
        consecutiveErrors = 0
    }

    public func refreshNow() {
        consecutiveErrors = 0
        Task { await fetchOnce() }
    }

    public func updateInterval(_ seconds: TimeInterval) {
        intervalSeconds = max(60, seconds)
        start(interval: intervalSeconds)
    }

    // MARK: - Polling

    private func startPolling() {
        consecutiveErrors = 0
        pollTask = Task { [weak self] in
            guard let self else { return }
            await self.fetchOnce()
            while !Task.isCancelled {
                let wait = self.backoffInterval()
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                if Task.isCancelled { break }
                await self.fetchOnce()
            }
        }
    }

    private func backoffInterval() -> TimeInterval {
        guard consecutiveErrors > 0 else { return intervalSeconds }
        return min(intervalSeconds * pow(2.0, Double(min(consecutiveErrors, 6))), 3600)
    }

    private func fetchOnce() async {
        do {
            let snapshot = try await provider.fetchUsage()
            consecutiveErrors = 0
            snapshotPublisher.send(snapshot)
        } catch let error as ProviderError {
            consecutiveErrors += 1
            if case .rateLimited = error {
                let minBackoffExponent = Int(ceil(log2(300 / intervalSeconds + 1)))
                consecutiveErrors = max(consecutiveErrors, minBackoffExponent)
            }
            errorPublisher.send(error)
        } catch {
            consecutiveErrors += 1
            errorPublisher.send(.unknown("unexpected"))
        }
    }
}
