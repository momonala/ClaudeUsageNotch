import Foundation
import Combine

public enum ExpandedMode: Equatable {
    case usage, analytics, settings
}

@MainActor
public final class AppState: ObservableObject {
    private var isLoading = false

    @Published public var authStatus: AuthStatus = .notConfigured
    @Published public var syncStatus: SyncStatus = .idle

    @Published public var snapshot: ServiceUsageSnapshot?
    @Published public var incident: ServiceIncident?
    @Published public var providerError: ProviderError?

    @Published public var notchState: NotchState = .compactIdle
    @Published public var isNotchUIHidden: Bool = false { didSet { persist() } }
    @Published public var showOnboarding: Bool = false
    @Published public var expandedMode: ExpandedMode = .usage

    // MARK: - Convenience

    public var sessionPercent: Double { snapshot?.sessionWindow.percentUsed ?? 0 }
    public var sessionStatus: UsageStatus { snapshot?.sessionWindow.status ?? .unknown }
    public var sessionResetString: String? { snapshot?.sessionWindow.timeToResetString() }
    public var isAtSessionLimit: Bool { sessionPercent >= 1.0 }
    public var isStatusOnly: Bool { snapshot?.isStatusOnly ?? false }
    public var isBalance: Bool { snapshot?.isBalance ?? false }
    public var showsPercentBar: Bool { snapshot?.showsPercentBar ?? true }
    public var shortLabel: String { snapshot?.shortLabel ?? "—" }
    public var sessionResetShortString: String? { snapshot?.sessionWindow.timeToResetShortString() }

    public var combinedStatus: UsageStatus { snapshot?.combinedStatus ?? .unknown }

    public var activeIncident: ServiceIncident? {
        guard let i = incident, i.level.isActive else { return nil }
        return i
    }

    public init() { load() }

    // MARK: - Persistence

    private enum Key {
        static let notchUIHidden = "claudeusagenotch.notchUIHidden"
    }

    private func load() {
        isLoading = true
        defer { isLoading = false }
        let d = UserDefaults.standard
        if d.object(forKey: Key.notchUIHidden) != nil {
            isNotchUIHidden = d.bool(forKey: Key.notchUIHidden)
        }
    }

    private func persist() {
        guard !isLoading else { return }
        UserDefaults.standard.set(isNotchUIHidden, forKey: Key.notchUIHidden)
    }
}
