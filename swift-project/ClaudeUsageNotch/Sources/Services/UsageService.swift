import Foundation
import Combine

/// Owns the polling loop for Claude.
///
/// Failure backoff: consecutive errors double the wait interval (cap: 5 minutes).
/// A 429 rate-limit forces at least 5-minute backoff regardless of the configured interval.
/// Auth failures (missing credentials / unauthorized) skip the exponential ramp and
/// retry on a short fixed interval — waiting doesn't fix them, but a quick retry lets
/// the Keychain access prompt re-surface in seconds rather than minutes.
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
    private var lastErrorWasAuth: Bool = false

    /// Short fixed retry for auth failures, so the Keychain prompt re-fires quickly.
    private let authRetryInterval: TimeInterval = 15

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
        lastErrorWasAuth = false
    }

    public func refreshNow() {
        consecutiveErrors = 0
        lastErrorWasAuth = false
        Task { await fetchOnce() }
    }

    public func updateInterval(_ seconds: TimeInterval) {
        intervalSeconds = max(60, seconds)
        start(interval: intervalSeconds)
    }

    // MARK: - Polling

    private func startPolling() {
        consecutiveErrors = 0
        lastErrorWasAuth = false
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
        if lastErrorWasAuth { return authRetryInterval }
        return min(intervalSeconds * pow(2.0, Double(min(consecutiveErrors, 6))), 300)
    }

    private func fetchOnce() async {
        do {
            let snapshot = try await provider.fetchUsage()
            consecutiveErrors = 0
            lastErrorWasAuth = false
            snapshotPublisher.send(snapshot)
        } catch let error as ProviderError {
            consecutiveErrors += 1
            lastErrorWasAuth = error.isAuthIssue
            if case .rateLimited = error {
                // Floor the next wait at 300s on a 429, regardless of the configured
                // interval: pick the smallest exponent n where interval·2ⁿ ≥ 300.
                let minBackoffExponent = max(0, Int(ceil(log2(300.0 / intervalSeconds))))
                consecutiveErrors = max(consecutiveErrors, minBackoffExponent)
            }
            errorPublisher.send(error)
        } catch {
            consecutiveErrors += 1
            lastErrorWasAuth = false
            errorPublisher.send(.unknown("unexpected"))
        }
    }
}
