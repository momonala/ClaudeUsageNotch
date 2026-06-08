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

    private func reconcileEnabledProviders() {
        var enabled = appState.enabledProviders.filter { isConfigured($0) }
        for id in ProviderId.allCases where isConfigured(id) && !enabled.contains(id) {
            enabled.append(id)
        }
        if enabled != appState.enabledProviders {
            appState.enabledProviders = enabled
        }
        if !enabled.contains(appState.activeProviderId), let first = enabled.first {
            appState.activeProviderId = first
        }
    }

    public func start() {
        reconcileEnabledProviders()

        usageService.snapshotPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot in
                guard let self else { return }
                self.appState.snapshots[snapshot.providerId] = snapshot
                self.appState.providerErrors[snapshot.providerId] = nil
                if snapshot.providerId == self.appState.activeProviderId {
                    self.appState.authStatus = .valid
                    self.appState.syncStatus = .ok(at: Date())
                }
                self.handleNotifications(for: snapshot)
            }
            .store(in: &cancellables)

        usageService.errorPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] (providerId, err) in
                guard let self else { return }
                self.appState.providerErrors[providerId] = err
                guard providerId == self.appState.activeProviderId else { return }
                if err.isAuthIssue {
                    let wasValid = self.appState.authStatus == .valid
                    self.appState.authStatus = (err == .missingCredentials) ? .notConfigured : .expired
                    if wasValid && err == .unauthorized {
                        self.notifications.send(
                            title: "\(providerId.displayName) credentials expired",
                            body: "Open ClaudeUsageNotch → Settings to reconnect."
                        )
                    }
                }
                self.appState.syncStatus = .error(err)
            }
            .store(in: &cancellables)

        IncidentMonitor.shared.incidentPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] (providerId, incident) in
                self?.appState.incidents[providerId] = incident
            }
            .store(in: &cancellables)
        IncidentMonitor.shared.start(providers: appState.enabledProviders)

        // Propagate poll interval changes from Settings to the service automatically.
        appSettings.$pollIntervalSeconds
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] interval in self?.usageService.updateInterval(interval) }
            .store(in: &cancellables)

        let configured = appState.enabledProviders.filter { isConfigured($0) }
        if configured.isEmpty {
            appState.authStatus = .notConfigured
        } else {
            appState.authStatus = .valid
            usageService.start(providers: configured, interval: appSettings.pollIntervalSeconds)
        }
    }

    public func stop() {
        usageService.stopAll()
        IncidentMonitor.shared.stop()
        cancellables.removeAll()
    }

    public func onCredentialsSaved(for providerId: ProviderId = .claude) {
        if !appState.enabledProviders.contains(providerId) {
            appState.enabledProviders.append(providerId)
        }
        appState.authStatus = .valid
        usageService.start(providers: appState.enabledProviders.filter { isConfigured($0) },
                           interval: appSettings.pollIntervalSeconds)
        IncidentMonitor.shared.start(providers: appState.enabledProviders)
    }

    public func refreshNow() {
        appState.syncStatus = .syncing
        usageService.refreshNow()
    }

    public func disableProvider(_ providerId: ProviderId) {
        appState.enabledProviders.removeAll { $0 == providerId }
        appState.snapshots.removeValue(forKey: providerId)
        appState.incidents.removeValue(forKey: providerId)
        usageService.stop(providerId: providerId)
        IncidentMonitor.shared.start(providers: appState.enabledProviders)
    }

    // MARK: - Helpers

    private func isConfigured(_ providerId: ProviderId) -> Bool {
        authService.cliOAuthAvailable(for: providerId) || authService.hasCredential(for: providerId)
    }

    private func handleNotifications(for snapshot: ServiceUsageSnapshot) {
        guard appSettings.notificationsEnabled else { return }
        notifications.evaluate(snapshot: snapshot,
                               thresholds: appSettings.thresholds,
                               providerId: snapshot.providerId)
    }
}
