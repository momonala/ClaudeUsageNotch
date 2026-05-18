import Foundation
import UserNotifications
import AppKit

/// Threshold-aware notification dispatcher. Anti-spam via per-provider+window+threshold tracking.
public final class NotificationService {
    public static let shared = NotificationService()
    private init() {
        // Request once on first use. macOS will silently no-op if the user has
        // already decided. We don't gate on authorization; fallbacks fire via
        // NSUserNotification (legacy) which works for unsigned dev builds.
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private var lastFired: [String: Double] = [:]

    /// Compare snapshot windows against thresholds and fire when newly crossed.
    /// Each (provider, window, threshold) tuple may only fire once per
    /// reset window. When `resetAt` advances, the tracker self-clears.
    public func evaluate(snapshot: ServiceUsageSnapshot, thresholds: [Double], providerId: ProviderId) {
        let windows: [(UsageWindow, String)] = [
            (snapshot.primaryWindow,  "session"),
            (snapshot.secondaryWindow.map { ($0, "weekly") }?.0 ?? snapshot.primaryWindow, snapshot.secondaryWindow == nil ? "session" : "weekly")
        ]
        for (window, label) in windows where window.percentUsed > 0 {
            for threshold in thresholds.sorted() {
                let key = "\(providerId.rawValue):\(label):\(threshold):\(window.resetAt?.timeIntervalSince1970 ?? 0)"
                if window.percentUsed >= threshold && lastFired[key] == nil {
                    lastFired[key] = threshold
                    fire(
                        title: "\(providerId.displayName) \(label) usage \(Int(threshold * 100))%",
                        body: usageBody(window: window, label: label)
                    )
                }
            }
        }
    }

    public func sendTest() {
        fire(title: "Notchy Limit test", body: "Notifications are working.")
    }

    private func usageBody(window: UsageWindow, label: String) -> String {
        let pct = Int(window.percentUsed * 100)
        if let reset = window.timeToResetString() {
            return "\(pct)% used — \(reset)."
        }
        return "\(pct)% of your \(label) limit used."
    }

    private func fire(title: String, body: String) {
        // Prefer UserNotifications; if authorization is denied, fall back to
        // NSUserNotification (deprecated but works without sign-off for
        // local builds).
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content,
                                            trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if error != nil {
                let legacy = NSUserNotification()
                legacy.title = title
                legacy.informativeText = body
                NSUserNotificationCenter.default.deliver(legacy)
            }
        }
    }
}
