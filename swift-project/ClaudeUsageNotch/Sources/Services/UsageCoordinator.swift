import Foundation
import Combine

/// Glues UsageService → AppState → NotificationService.
/// Owns no UI; only updates published state and fires notifications.
@MainActor
public final class UsageCoordinator {
    private let appState: AppState
    private let appSettings: AppSettings
    private let authService: AuthService
    private let usageService: UsageService
    private let notifications: NotificationService
    private var cancellables = Set<AnyCancellable>()

    public init(
        appState: AppState,
        appSettings: AppSettings,
        authService: AuthService,
        usageService: UsageService,
        notifications: NotificationService
    ) {
        self.appState = appState
        self.appSettings = appSettings
        self.authService = authService
        self.usageService = usageService
        self.notifications = notifications
    }

    public func start() {
        usageService.snapshotPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                guard let self else { return }
                self.appState.snapshot = snapshot
                self.appState.providerError = nil
                self.appState.authStatus = .valid
                self.appState.syncStatus = .ok(at: Date())
                self.handleNotifications(for: snapshot)
            }
            .store(in: &cancellables)

        usageService.errorPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] err in
                guard let self else { return }
                self.appState.providerError = err
                if err.isAuthIssue {
                    let wasValid = self.appState.authStatus == .valid
                    self.appState.authStatus = (err == .missingCredentials) ? .notConfigured : .expired
                    if wasValid && err == .unauthorized {
                        self.notifications.send(
                            title: "Claude credentials expired",
                            body: "Open ClaudeUsageNotch → Settings to reconnect."
                        )
                    }
                }
                self.appState.syncStatus = .error(err)
            }
            .store(in: &cancellables)

        IncidentMonitor.shared.incidentPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] incident in
                self?.appState.incident = incident
            }
            .store(in: &cancellables)
        IncidentMonitor.shared.start()

        appSettings.$pollIntervalSeconds
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] interval in self?.usageService.updateInterval(interval) }
            .store(in: &cancellables)

        if authService.hasAnyConfiguredProvider() {
            appState.authStatus = .valid
            usageService.start(interval: appSettings.pollIntervalSeconds)
        } else {
            appState.authStatus = .notConfigured
        }
    }

    public func stop() {
        usageService.stopAll()
        IncidentMonitor.shared.stop()
        cancellables.removeAll()
    }

    public func onCredentialsSaved() {
        appState.authStatus = .valid
        usageService.start(interval: appSettings.pollIntervalSeconds)
        IncidentMonitor.shared.start()
    }

    public func refreshNow() {
        appState.syncStatus = .syncing
        usageService.refreshNow()
    }

    // MARK: - Helpers

    private func handleNotifications(for snapshot: ServiceUsageSnapshot) {
        guard appSettings.notificationsEnabled else { return }
        notifications.evaluate(snapshot: snapshot, thresholds: appSettings.thresholds)
    }
}
