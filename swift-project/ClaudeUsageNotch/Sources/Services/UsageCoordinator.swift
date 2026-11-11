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
                self.appState.connection.reduce(.synced(at: Date()))
                self.handleNotifications(for: snapshot)
                QuotaSyncService.push(snapshot, settings: self.appSettings)
            }
            .store(in: &cancellables)

        usageService.errorPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] err in
                guard let self else { return }
                if self.appState.connection.reduce(.failed(err)) == .notifyCredentialsExpired {
                    self.notifications.send(
                        title: "Claude credentials expired",
                        body: "Open ClaudeUsageNotch → Settings to reconnect."
                    )
                }
            }
            .store(in: &cancellables)

        IncidentMonitor.shared.incidentPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] incident in
                self?.appState.incident = incident
            }
            .store(in: &cancellables)
        IncidentMonitor.shared.start()

        FrontmostAppService.shared.isWorkHostFrontmost
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isHost in
                self?.appState.isWorkHostFrontmost = isHost
            }
            .store(in: &cancellables)
        FrontmostAppService.shared.start()

        AgentStatusService.shared.readingPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] reading in
                self?.appState.agentStatus = reading.status
                self?.appState.agentJustCompleted = reading.justCompleted
            }
            .store(in: &cancellables)

        // The setting drives the service, not just the glow: no point polling
        // the status file when the pulse is off.
        appSettings.$showAgentStatusPulse
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled {
                    AgentStatusService.shared.start()
                } else {
                    AgentStatusService.shared.stop()
                    self.appState.agentStatus = .idle
                    self.appState.agentJustCompleted = false
                }
            }
            .store(in: &cancellables)

        appSettings.$pollIntervalSeconds
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] interval in self?.usageService.updateInterval(interval) }
            .store(in: &cancellables)

        let hasCredentials = authService.hasAnyConfiguredProvider()
        appState.connection.reduce(.started(hasCredentials: hasCredentials))
        if hasCredentials {
            usageService.start(interval: appSettings.pollIntervalSeconds)
        }
    }

    public func stop() {
        usageService.stopAll()
        FrontmostAppService.shared.stop()
        IncidentMonitor.shared.stop()
        AgentStatusService.shared.stop()
        cancellables.removeAll()
    }

    public func onCredentialsSaved() {
        appState.connection.reduce(.credentialsSaved)
        usageService.start(interval: appSettings.pollIntervalSeconds)
        IncidentMonitor.shared.start()
    }

    public func refreshNow() {
        appState.connection.reduce(.refreshRequested)
        usageService.refreshNow()
    }

    // MARK: - Helpers

    private func handleNotifications(for snapshot: ServiceUsageSnapshot) {
        guard appSettings.notificationsEnabled else { return }
        notifications.evaluate(snapshot: snapshot, thresholds: appSettings.thresholds)
    }
}
