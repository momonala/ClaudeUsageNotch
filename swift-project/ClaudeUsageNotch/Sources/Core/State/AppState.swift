import Foundation
import Combine

@MainActor
public final class AppState: ObservableObject {
    private var isLoading = false

    @Published public var activeProviderId: ProviderId = .claude { didSet { persist() } }
    @Published public var authStatus: AuthStatus = .notConfigured
    @Published public var syncStatus: SyncStatus = .idle

    @Published public var snapshots: [ProviderId: ServiceUsageSnapshot] = [:]
    @Published public var enabledProviders: [ProviderId] = [.claude] { didSet { persist() } }
    @Published public var incidents: [ProviderId: ServiceIncident] = [:]
    @Published public var providerErrors: [ProviderId: ProviderError] = [:]

    @Published public var notchState: NotchState = .compactIdle
    @Published public var isNotchUIHidden: Bool = false { didSet { persist() } }
    @Published public var showOnboarding: Bool = false
    @Published public var showSettings: Bool = false

    // MARK: - Snapshot access

    public var activeSnapshot: ServiceUsageSnapshot? { snapshots[activeProviderId] }

    // MARK: - Convenience (always reflects activeProviderId's snapshot)

    public var sessionPercent: Double { activeSnapshot?.sessionWindow.percentUsed ?? 0 }
    public var sessionStatus: UsageStatus { activeSnapshot?.sessionWindow.status ?? .unknown }
    public var sessionResetString: String? { activeSnapshot?.sessionWindow.timeToResetString() }
    public var isAtSessionLimit: Bool { sessionPercent >= 1.0 }
    public var activeIsStatusOnly: Bool { activeSnapshot?.isStatusOnly ?? false }
    public var activeIsBalance: Bool { activeSnapshot?.isBalance ?? false }
    public var activeShowsPercentBar: Bool { activeSnapshot?.showsPercentBar ?? true }
    public var activeShortLabel: String { activeSnapshot?.shortLabel ?? "—" }
    public var sessionResetShortString: String? { activeSnapshot?.sessionWindow.timeToResetShortString() }

    // MARK: - Multi-provider

    public var combinedStatus: UsageStatus {
        let statuses = snapshots.values.map { $0.combinedStatus }
        if statuses.contains(.critical) { return .critical }
        if statuses.contains(.warning)  { return .warning }
        if statuses.isEmpty             { return .unknown }
        return .healthy
    }

    public var isMultiProvider: Bool { snapshots.count >= 2 }

    public var activeIncident: ServiceIncident? {
        guard let incident = incidents[activeProviderId], incident.level.isActive else { return nil }
        return incident
    }

    public var worstIncident: ServiceIncident? {
        let active = enabledProviders.compactMap { incidents[$0] }.filter { $0.level.isActive }
        let order: [IncidentLevel] = [.critical, .major, .minor, .maintenance]
        for level in order {
            if let hit = active.first(where: { $0.level == level }) { return hit }
        }
        return nil
    }

    public init() { load() }

    // MARK: - Persistence (runtime state only — settings live in AppSettings)

    private enum Key {
        static let activeProvider   = "claudeusagenotch.activeProvider"
        static let enabledProviders = "claudeusagenotch.enabledProviders"
        static let notchUIHidden    = "claudeusagenotch.notchUIHidden"
    }

    private func load() {
        isLoading = true
        defer { isLoading = false }
        let d = UserDefaults.standard
        if let raw = d.string(forKey: Key.activeProvider), let p = ProviderId(rawValue: raw) {
            activeProviderId = p
        }
        if let raws = d.array(forKey: Key.enabledProviders) as? [String] {
            let restored = raws.compactMap { ProviderId(rawValue: $0) }
            if !restored.isEmpty { enabledProviders = restored }
        }
        if d.object(forKey: Key.notchUIHidden) != nil {
            isNotchUIHidden = d.bool(forKey: Key.notchUIHidden)
        }
    }

    private func persist() {
        guard !isLoading else { return }
        let d = UserDefaults.standard
        d.set(activeProviderId.rawValue, forKey: Key.activeProvider)
        d.set(enabledProviders.map(\.rawValue), forKey: Key.enabledProviders)
        d.set(isNotchUIHidden, forKey: Key.notchUIHidden)
    }
}
