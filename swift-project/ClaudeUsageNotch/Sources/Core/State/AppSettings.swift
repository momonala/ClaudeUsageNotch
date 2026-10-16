import Foundation
import Combine

/// Persisted user preferences. Separate from AppState (runtime) to avoid
/// triggering usage-data observers on settings-only changes.
@MainActor
public final class AppSettings: ObservableObject {
    @Published public var pollIntervalSeconds: TimeInterval = 300 { didSet { persist() } }
    @Published public var notificationsEnabled: Bool = true { didSet { persist() } }
    /// Fractions of a usage window that can fire a notification. The settings
    /// pane offers exactly these, so a default always has a control.
    public static let availableThresholds: [Double] = [0.25, 0.5, 0.75, 0.9, 1.0]
    @Published public var thresholds: [Double] = AppSettings.availableThresholds { didSet { persist() } }
    // Not persisted here: the source of truth is `SMAppService.mainApp.status`,
    // synced into this property at launch (see AppDelegate.syncLaunchAtLoginState).
    @Published public var launchAtLogin: Bool = false

    /// Base URL of the sync server, e.g. `http://raspberrypi.local:5014`. Empty disables sync.
    @Published public var apiBaseURL: String = "http://localhost:5014" { didSet { persist() } }

    @Published public var syncIntervalSeconds: TimeInterval = 600 { didSet { persist() } }

    /// Perimeter glow reflecting local Claude Code session status. See `agent-status-hook/`.
    @Published public var showAgentStatusPulse: Bool = true { didSet { persist() } }

    @Published public var showFableInCompact: Bool = true { didSet { persist() } }
    @Published public var showCreditsInCompact: Bool = true { didSet { persist() } }

    /// Optional rows (Fable, credits) the compact pill shows for this snapshot.
    public func compactExtraWindows(for snapshot: ServiceUsageSnapshot?) -> [UsageWindow] {
        [showFableInCompact ? snapshot?.weeklyFableWindow : nil,
         showCreditsInCompact ? snapshot?.creditWindow : nil].compactMap { $0 }
    }

    /// The sync server's base URL, or a path under it. Nil when sync is off or
    /// the address doesn't parse.
    public func apiURL(path: String? = nil) -> URL? {
        let base = apiBaseURL.trimmingCharacters(in: .whitespaces)
        guard !base.isEmpty, let url = URL(string: base) else { return nil }
        return path.map { url.appendingPathComponent($0) } ?? url
    }

    public var syncEnabled: Bool { apiURL() != nil }

    private var isLoading = false

    private enum Key {
        static let pollInterval     = "claudeusagenotch.pollIntervalSeconds"
        static let notifications    = "claudeusagenotch.notificationsEnabled"
        static let thresholds       = "claudeusagenotch.thresholds"
        static let apiBaseURL       = "claudeusagenotch.apiBaseURL"
        static let syncInterval     = "claudeusagenotch.syncIntervalSeconds"
        static let showAgentPulse   = "claudeusagenotch.showAgentStatusPulse"
        static let showFable        = "claudeusagenotch.showFableInCompact"
        static let showCredits      = "claudeusagenotch.showCreditsInCompact"
    }

    public init() { load() }

    private func load() {
        isLoading = true
        defer { isLoading = false }
        let d = UserDefaults.standard
        if d.object(forKey: Key.pollInterval) != nil {
            let v = d.double(forKey: Key.pollInterval)
            if v >= 60 { pollIntervalSeconds = v }
        }
        if d.object(forKey: Key.notifications) != nil {
            notificationsEnabled = d.bool(forKey: Key.notifications)
        }
        if let t = d.array(forKey: Key.thresholds) as? [Double], !t.isEmpty {
            thresholds = t
        }
        // Only override the default when a non-empty value was stored.
        if let url = d.string(forKey: Key.apiBaseURL), !url.isEmpty {
            apiBaseURL = url
        }
        if d.object(forKey: Key.syncInterval) != nil {
            let v = d.double(forKey: Key.syncInterval)
            if v >= 60 { syncIntervalSeconds = v }
        }
        if d.object(forKey: Key.showAgentPulse) != nil {
            showAgentStatusPulse = d.bool(forKey: Key.showAgentPulse)
        }
        if d.object(forKey: Key.showFable) != nil {
            showFableInCompact = d.bool(forKey: Key.showFable)
        }
        if d.object(forKey: Key.showCredits) != nil {
            showCreditsInCompact = d.bool(forKey: Key.showCredits)
        }
    }

    private func persist() {
        guard !isLoading else { return }
        let d = UserDefaults.standard
        d.set(pollIntervalSeconds, forKey: Key.pollInterval)
        d.set(notificationsEnabled, forKey: Key.notifications)
        d.set(thresholds, forKey: Key.thresholds)
        d.set(apiBaseURL, forKey: Key.apiBaseURL)
        d.set(syncIntervalSeconds, forKey: Key.syncInterval)
        d.set(showAgentStatusPulse, forKey: Key.showAgentPulse)
        d.set(showFableInCompact, forKey: Key.showFable)
        d.set(showCreditsInCompact, forKey: Key.showCredits)
    }
}
