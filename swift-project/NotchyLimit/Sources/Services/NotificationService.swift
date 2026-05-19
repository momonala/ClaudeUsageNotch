import Foundation
import AppKit

/// Threshold-aware notification dispatcher.
///
/// Delivery strategy: custom in-app banner (NotificationBannerController).
/// This requires zero system permissions and works reliably for unsigned/local builds.
/// `lastFired` is persisted to UserDefaults so restarts don't re-fire thresholds
/// within the same reset window.
public final class NotificationService {
    public static let shared = NotificationService()
    private init() { loadLastFired() }

    private let defaultsKey = "com.notchylimit.NotificationService.lastFired"
    private var lastFired: [String: Double] = [:]

    // MARK: - Public API

    public func evaluate(snapshot: ServiceUsageSnapshot, thresholds: [Double], providerId: ProviderId) {
        var windows: [(UsageWindow, String)] = [(snapshot.primaryWindow, "session")]
        if let weekly = snapshot.secondaryWindow  { windows.append((weekly, "weekly")) }
        if let model  = snapshot.tertiaryWindow   { windows.append((model,  "model"))  }

        var dirty = false
        for (window, label) in windows where window.percentUsed > 0 {
            for threshold in thresholds.sorted() {
                let key = "\(providerId.rawValue):\(label):\(threshold):\(window.resetAt?.timeIntervalSince1970 ?? 0)"
                if window.percentUsed >= threshold && lastFired[key] == nil {
                    lastFired[key] = threshold
                    dirty = true
                    fire(
                        title: "\(providerId.displayName) \(label) \(Int(threshold * 100))% used",
                        body: usageBody(window: window, label: label)
                    )
                }
            }
        }
        if dirty { saveLastFired() }
    }

    public func sendTest() {
        fire(title: "Notchy Limit", body: "Notifications are working.")
    }

    // MARK: - Persistence

    private func saveLastFired() {
        UserDefaults.standard.set(lastFired, forKey: defaultsKey)
    }

    private func loadLastFired() {
        lastFired = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Double] ?? [:]
    }

    // MARK: - Delivery

    private func usageBody(window: UsageWindow, label: String) -> String {
        let pct = Int(window.percentUsed * 100)
        if let reset = window.timeToResetString() {
            return "\(pct)% of \(label) limit — resets \(reset)."
        }
        return "\(pct)% of your \(label) limit used."
    }

    private func fire(title: String, body: String) {
        NotificationBannerController.shared.show(title: title, body: body)
    }
}
