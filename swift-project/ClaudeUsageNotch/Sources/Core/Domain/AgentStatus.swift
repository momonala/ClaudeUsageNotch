import Foundation

/// Aggregated state of local Claude Code CLI sessions, fed by
/// `agent-status-hook/hook.py` via hooks configured in `~/.claude/settings.json`.
public enum AgentStatus: String, Codable, Hashable {
    case idle
    case working
    case needsInput

    /// Most-actionable status wins: a session waiting on the user should never
    /// be hidden behind another session that's merely working.
    public static func aggregate(_ statuses: [AgentStatus]) -> AgentStatus {
        if statuses.contains(.needsInput) { return .needsInput }
        if statuses.contains(.working) { return .working }
        return .idle
    }
}

/// One session's entry in the shared status file.
public struct AgentSessionEntry: Codable, Hashable {
    public let status: AgentStatus
    public let event: String
    public let ts: TimeInterval
    public let cwd: String

    public init(status: AgentStatus, event: String, ts: TimeInterval, cwd: String) {
        self.status = status
        self.event = event
        self.ts = ts
        self.cwd = cwd
    }
}

/// Aggregated read of the status file at a point in time.
public struct AgentStatusReading: Hashable {
    public let status: AgentStatus
    /// True when a session finished within the "just completed" flash window
    /// *and* no other session currently wants attention. A live
    /// `working`/`needsInput` session always outranks a completion flash, so
    /// a green pulse can never mask a session that needs the user.
    public let justCompleted: Bool

    public static let idle = AgentStatusReading(status: .idle, justCompleted: false)

    public init(status: AgentStatus, justCompleted: Bool) {
        self.status = status
        self.justCompleted = justCompleted
    }

    /// Drops stale non-idle entries (a session that stopped reporting without a
    /// `Stop`/`SessionEnd`, e.g. a killed terminal) before aggregating, so a dead
    /// session can't hold `working`/`needsInput` forever.
    public static func from(
        _ entries: [AgentSessionEntry],
        now: TimeInterval,
        staleAfter: TimeInterval = 180,
        completedWithin: TimeInterval = 30
    ) -> AgentStatusReading {
        let live = entries.filter { $0.status == .idle || now - $0.ts <= staleAfter }
        let status = AgentStatus.aggregate(live.map(\.status))
        let completedRecently = entries.contains {
            $0.event == "Stop" && now - $0.ts <= completedWithin
        }
        return AgentStatusReading(status: status,
                                  justCompleted: completedRecently && status == .idle)
    }
}
