import Foundation
import Combine

/// Owns the polling loop. Single-instance, holds no UI state.
/// Snapshots/errors are emitted via publishers consumed by `UsageCoordinator`.
public final class UsageService {
    public static let shared = UsageService()
    private init() {}

    public let snapshotPublisher = PassthroughSubject<ServiceUsageSnapshot, Never>()
    public let errorPublisher    = PassthroughSubject<ProviderError, Never>()

    private var pollTask: Task<Void, Never>?
    private(set) var intervalSeconds: TimeInterval = 300
    private(set) var activeProviderId: ProviderId = .claude

    public func start(providerId: ProviderId, interval: TimeInterval) {
        stop()
        activeProviderId = providerId
        intervalSeconds = max(60, interval)
        pollTask = Task { [weak self] in
            guard let self = self else { return }
            // Immediate first fetch, then interval-paced.
            await self.fetchOnce()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(self.intervalSeconds * 1_000_000_000))
                if Task.isCancelled { break }
                await self.fetchOnce()
            }
        }
    }

    public func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    public func refreshNow() {
        Task { await fetchOnce() }
    }

    public func updateInterval(_ seconds: TimeInterval) {
        intervalSeconds = max(60, seconds)
        start(providerId: activeProviderId, interval: intervalSeconds)
    }

    @MainActor
    private func fetchOnce() async {
        guard let provider = ProviderRegistry.shared.provider(for: activeProviderId) else {
            errorPublisher.send(.unknown("No provider registered for \(activeProviderId.rawValue)"))
            return
        }
        do {
            let snapshot = try await provider.fetchUsage()
            snapshotPublisher.send(snapshot)
        } catch let error as ProviderError {
            errorPublisher.send(error)
        } catch {
            errorPublisher.send(.unknown(error.localizedDescription))
        }
    }
}
