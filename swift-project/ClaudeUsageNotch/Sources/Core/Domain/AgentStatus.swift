import Foundation

/// Aggregated state of local Claude Code CLI sessions, fed by
/// `agent-status-hook/hook.py` via hooks configured in `~/.claude/settings.json`.
/// `agent-status-hook/transitions.json` pins which hook event leads to which case.
public enum AgentStatus: Hashable {
    case idle
    case completed
    case working
    case needsInput

    /// Most-actionable status wins: a session waiting on the user should never
    /// be hidden behind another session that's merely working, and a finished
    /// session's pulse never masks one that's still going.
    public static func aggregate(_ statuses: [AgentStatus]) -> AgentStatus {
        if statuses.contains(.needsInput) { return .needsInput }
        if statuses.contains(.working) { return .working }
        if statuses.contains(.completed) { return .completed }
        return .idle
    }

    public static func current(
        from entries: [AgentSessionEntry],
        now: TimeInterval,
        staleAfter: TimeInterval = 180,
        completedWithin: TimeInterval = 30
    ) -> AgentStatus {
        aggregate(entries.map {
            $0.status(at: now, staleAfter: staleAfter, completedWithin: completedWithin)
        })
    }
}

/// One session's entry in the shared status file.
public struct AgentSessionEntry: Codable, Hashable {
    /// The status values the hook writes. A finished turn is written as `idle`
    /// with event `Stop`.
    public enum Reported: String, Codable, Hashable {
        case idle
        case working
        case needsInput
    }

    public static let stopEvent = "Stop"

    public let status: Reported
    public let event: String
    public let ts: TimeInterval
    public let cwd: String

    public init(status: Reported, event: String, ts: TimeInterval, cwd: String) {
        self.status = status
        self.event = event
        self.ts = ts
        self.cwd = cwd
    }

    /// Entries that stopped reporting without a `Stop`/`SessionEnd` (a killed
    /// terminal) read as idle, so a dead session can't hold `working` forever.
    public func status(at now: TimeInterval,
                       staleAfter: TimeInterval,
                       completedWithin: TimeInterval) -> AgentStatus {
        let age = now - ts
        switch status {
        case .idle:
            return event == Self.stopEvent && age <= completedWithin ? .completed : .idle
        case .working:
            return age <= staleAfter ? .working : .idle
        case .needsInput:
            return age <= staleAfter ? .needsInput : .idle
        }
    }
}
