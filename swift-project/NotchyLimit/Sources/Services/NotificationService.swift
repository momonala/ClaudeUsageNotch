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
            // Collect all thresholds newly crossed in this poll cycle (sorted low → high).
            var newlyCrossed: [(threshold: Double, key: String)] = []
            for threshold in thresholds.sorted() {
                let key = fireKey(providerId: providerId, label: label,
                                  threshold: threshold, window: window)
                if window.percentUsed >= threshold && lastFired[key] == nil {
                    newlyCrossed.append((threshold, key))
                }
            }

            // Mark all of them fired, but only notify once — for the highest.
            for (threshold, key) in newlyCrossed {
                lastFired[key] = threshold
                dirty = true
            }
            if let highest = newlyCrossed.last {
                fire(
                    title: "\(providerId.displayName) \(label) \(Int(highest.threshold * 100))% used",
                    body: usageBody(window: window, label: label)
                )
            }
        }
        if dirty { saveLastFired() }
    }

    // MARK: - Key generation

    /// Builds a stable deduplication key for a threshold + window pair.
    ///
    /// WHY hourly bucketing: Claude's usage endpoint recalculates `resets_at` as
    /// "now + 5 hours" on every API call. Using the raw `timeIntervalSince1970`
    /// as the key component means the key drifts by the poll interval on every
    /// fetch — the threshold appears unfired on every poll and notifications fire
    /// continuously. Truncating to the nearest hour produces a key that is stable
    /// for the full duration of any window (5-hour session, 7-day weekly) while
    /// still generating a new key once the window actually rolls over.
    ///
    /// WHY daily fallback: a nil `resetAt` previously hardcoded to 0, meaning
    /// "fire once, never again across all time." A daily bucket fires at most once
    /// per calendar day, which is more useful than either extreme.
    private func fireKey(providerId: ProviderId, label: String,
                         threshold: Double, window: UsageWindow) -> String {
        let bucket: Int
        if let resetAt = window.resetAt {
            bucket = Int(resetAt.timeIntervalSince1970 / 3600)
        } else {
            bucket = Int(Date().timeIntervalSince1970 / 86400)
        }
        return "\(providerId.rawValue):\(label):\(threshold):\(bucket)"
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
