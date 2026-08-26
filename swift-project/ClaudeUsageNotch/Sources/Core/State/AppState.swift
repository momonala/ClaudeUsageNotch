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

    @Published public var agentStatus: AgentStatus = .idle
    @Published public var agentJustCompleted: Bool = false

    /// Whether the frontmost app is one Claude Code runs in — see
    /// `FrontmostAppService`. Defaults to true so the pill shows its bars if
    /// the service never reports (a broken observer shouldn't silently empty
    /// the notch).
    @Published public var isWorkHostFrontmost: Bool = true

    // MARK: - Convenience

    public var sessionPercent: Double { snapshot?.sessionWindow.effectivePercentUsed() ?? 0 }
    public var sessionStatus: UsageStatus { snapshot?.sessionWindow.effectiveStatus() ?? .unknown }
    public var sessionResetString: String? { snapshot?.sessionWindow.timeToResetString() }
    public var isAtSessionLimit: Bool { sessionPercent >= 1.0 }
    public var isStatusOnly: Bool { snapshot?.isStatusOnly ?? false }
    public var isBalance: Bool { snapshot?.isBalance ?? false }
    public var showsPercentBar: Bool { snapshot?.showsPercentBar ?? true }
    public var shortLabel: String { snapshot?.shortLabel ?? "—" }
    /// Reset countdown for the compact pill's label slot ("45m", "2h"). Kept
    /// to three characters so the pill stays exactly as wide as the cutout —
    /// see `UsageWindow.timeToResetCompactString`.
    public var sessionResetCompactString: String? { snapshot?.sessionWindow.timeToResetCompactString() }

    /// Whether the compact pill draws its bars and percentages at all. Away
    /// from the app you run Claude Code in, the pill keeps its shape and its
    /// status ring but drops the readout: the numbers are only worth the screen
    /// space where you'd act on them, and everywhere else the notch is better
    /// off looking like hardware. Hover still expands the full panel.
    public var showsCompactContent: Bool { isWorkHostFrontmost }

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
