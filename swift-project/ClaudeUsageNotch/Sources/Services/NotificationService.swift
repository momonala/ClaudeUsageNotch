import Foundation
import AppKit

/// Poll-driven usage notifications.
///
/// On each snapshot: for every quota window (session, weekly, optional Sonnet),
/// compare usage to the previous poll.
///
/// - **Going up:** fire when usage crosses a configured threshold we have not
///   notified for yet this cycle (high-water mark per window).
/// - **Going down:** usage decreased → window reset → fire a reset banner and
///   clear the threshold mark so the next climb can alert again.
///
/// Does not use `resets_at` for deduplication — Claude shifts that timestamp
/// on every API call.
public final class NotificationService {
    public static let shared = NotificationService()
    private init() {
        loadMark()
        loadLastPercent()
    }

    private let defaultsKey = "com.claudeusagenotch.NotificationService.highWaterMark"
    private let lastPercentKey = "com.claudeusagenotch.NotificationService.lastPercent"

    // "claude:session" → highest threshold already notified (0.0 = none)
    private var mark: [String: Double] = [:]
    // "claude:session" → usage percent on the previous poll
    private var lastPercent: [String: Double] = [:]

    // MARK: - Public API

    public func evaluate(snapshot: ServiceUsageSnapshot,
                         thresholds: [Double],
                         providerId: ProviderId) {
        let sorted = thresholds.sorted()
        var markDirty = false
        var lastPercentDirty = false

        for window in notifiableWindows(in: snapshot) {
            let label = Self.windowLabel(window.type)
            let key = "\(providerId.rawValue):\(label)"
            let usage = window.percentUsed
            let previous = lastPercent[key] ?? 0

            if Self.didUsageDecrease(previous: previous, current: usage) {
                mark[key] = 0
                markDirty = true
                fire(
                    title: "\(providerId.displayName) \(label) reset",
                    body: "\(label.capitalized) window reset — you're back to 0%."
                )
            } else if !sorted.isEmpty, usage > 0 {
                let currentMark = mark[key] ?? 0
                if let highest = sorted.last(where: { usage >= $0 }), highest > currentMark {
                    mark[key] = highest
                    markDirty = true
                    let title = highest >= 1.0
                        ? "\(providerId.displayName) \(label) limit reached"
                        : "\(providerId.displayName) \(label) \(Int(highest * 100))% used"
                    fire(title: title, body: usageBody(window: window, label: label))
                }
            }

            if previous != usage {
                lastPercent[key] = usage
                lastPercentDirty = true
            }
        }

        if markDirty { saveMark() }
        if lastPercentDirty { saveLastPercent() }
    }

    /// True when the current reading is lower than the previous poll.
    static func didUsageDecrease(previous: Double, current: Double) -> Bool {
        current < previous - 0.001
    }

    public func send(title: String, body: String) {
        fire(title: title, body: body)
    }

    public func sendTest() {
        fire(title: "ClaudeUsageNotch", body: "Notifications are working.")
    }

    // MARK: - Windows

    private func notifiableWindows(in snapshot: ServiceUsageSnapshot) -> [UsageWindow] {
        var windows = [snapshot.sessionWindow]
        if let weekly = snapshot.weeklyWindow { windows.append(weekly) }
        if let sonnet = snapshot.weeklySonnetWindow { windows.append(sonnet) }
        return windows.filter { Self.notifiableTypes.contains($0.type) }
    }

    private static let notifiableTypes: Set<UsageWindowType> = [.session, .weekly, .weeklyModel]

    private static func windowLabel(_ type: UsageWindowType) -> String {
        switch type {
        case .session:     return "session"
        case .weekly:      return "weekly"
        case .weeklyModel: return "sonnet"
        default:           return type.rawValue
        }
    }

    // MARK: - Persistence

    private func saveMark() {
        UserDefaults.standard.set(mark, forKey: defaultsKey)
    }

    private func loadMark() {
        mark = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Double] ?? [:]
    }

    private func saveLastPercent() {
        UserDefaults.standard.set(lastPercent, forKey: lastPercentKey)
    }

    private func loadLastPercent() {
        lastPercent = UserDefaults.standard.dictionary(forKey: lastPercentKey) as? [String: Double] ?? [:]
    }

    // MARK: - Delivery

    private func usageBody(window: UsageWindow, label: String) -> String {
        if window.isAtLimit {
            return window.timeToResetString().map { "Blocked. \($0)." } ?? "Session limit reached."
        }
        let pct = Int(window.percentUsed * 100)
        if let reset = window.timeToResetString() {
            return "\(pct)% of \(label) limit. \(reset)."
        }
        return "\(pct)% of your \(label) limit used."
    }

    private func fire(title: String, body: String) {
        NotificationBannerController.shared.show(title: title, body: body)
    }
}
