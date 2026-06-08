import Foundation
import Combine

/// Persisted user preferences. Separate from AppState (runtime) to avoid
/// triggering usage-data observers on settings-only changes.
@MainActor
public final class AppSettings: ObservableObject {
    @Published public var pollIntervalSeconds: TimeInterval = 300 { didSet { persist() } }
    @Published public var notificationsEnabled: Bool = true { didSet { persist() } }
    @Published public var thresholds: [Double] = [0.25, 0.5, 0.75, 0.9, 1.0] { didSet { persist() } }
    @Published public var launchAtLogin: Bool = false

    private var isLoading = false

    private enum Key {
        static let pollInterval     = "claudeusagenotch.pollIntervalSeconds"
        static let notifications    = "claudeusagenotch.notificationsEnabled"
        static let thresholds       = "claudeusagenotch.thresholds"
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
    }

    private func persist() {
        guard !isLoading else { return }
        let d = UserDefaults.standard
        d.set(pollIntervalSeconds, forKey: Key.pollInterval)
        d.set(notificationsEnabled, forKey: Key.notifications)
        d.set(thresholds, forKey: Key.thresholds)
    }
}
