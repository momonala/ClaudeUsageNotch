import Foundation
import Combine

/// Glues UsageService -> AppState -> NotificationService.
/// Owns no UI; only updates the published state and fires notifications.
public final class UsageCoordinator {
    private let appState: AppState
    private let authService: AuthService
    private let usageService: UsageService
    private let notifications: NotificationService
    private var cancellables = Set<AnyCancellable>()

    public init(
        appState: AppState,
        authService: AuthService,
        usageService: UsageService,
        notifications: NotificationService
    ) {
        self.appState = appState
        self.authService = authService
        self.usageService = usageService
        self.notifications = notifications
    }

    public func start() {
        // Pipe successful snapshots into AppState.
        usageService.snapshotPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot in
                guard let self = self else { return }
                self.appState.latestSnapshot = snapshot
                self.appState.authStatus = .valid
                self.appState.syncStatus = .ok(at: Date())
                self.handleNotifications(for: snapshot)
            }
            .store(in: &cancellables)

        usageService.errorPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] err in
                guard let self = self else { return }
                if err.isAuthIssue {
                    self.appState.authStatus = (err == .missingCredentials) ? .notConfigured : .expired
                }
                self.appState.syncStatus = .error(err)
            }
            .store(in: &cancellables)

        // Begin polling if creds exist; otherwise wait for onboarding.
        if authService.hasCredential(for: appState.activeProviderId) {
            appState.authStatus = .valid
            usageService.start(providerId: appState.activeProviderId,
                               interval: appState.pollIntervalSeconds)
        } else {
            appState.authStatus = .notConfigured
        }
    }

    public func stop() {
        usageService.stop()
        cancellables.removeAll()
    }

    public func onCredentialsSaved() {
        appState.authStatus = .valid
        usageService.start(providerId: appState.activeProviderId,
                           interval: appState.pollIntervalSeconds)
    }

    public func refreshNow() {
        appState.syncStatus = .syncing
        usageService.refreshNow()
    }

    private func handleNotifications(for snapshot: ServiceUsageSnapshot) {
        guard appState.notificationsEnabled else { return }
        notifications.evaluate(snapshot: snapshot,
                               thresholds: appState.thresholds,
                               providerId: snapshot.providerId)
    }
}
