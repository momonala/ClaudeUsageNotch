import Foundation
import Combine
import OSLog

/// Polls the status file `agent-status-hook/hook.py` writes to and publishes
/// the aggregated `AgentStatusReading` across all local Claude Code sessions.
final class AgentStatusService {
    static let shared = AgentStatusService()
    private init() {}

    let readingPublisher = PassthroughSubject<AgentStatusReading, Never>()

    private var task: Task<Void, Never>?
    private static let pollInterval: TimeInterval = 1.5
    private static let log = Logger(subsystem: "com.claudeusagenotch", category: "AgentStatus")

    private static let statusFileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ClaudeUsageNotch/agent-status.json")
    }()

    func start() {
        stop()
        task = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                self.pollOnce()
                try? await Task.sleep(nanoseconds: UInt64(Self.pollInterval * 1_000_000_000))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    /// No status file means no hook has ever run (or every session ended) —
    /// genuinely idle. A file that exists but won't decode is a bug in the hook
    /// or a truncated write, which would otherwise be indistinguishable from an
    /// idle machine forever, so it gets logged rather than silently swallowed.
    private func pollOnce() {
        guard let data = try? Data(contentsOf: Self.statusFileURL) else {
            readingPublisher.send(.idle)
            return
        }
        do {
            let entries = try JSONDecoder().decode([String: AgentSessionEntry].self, from: data)
            readingPublisher.send(
                AgentStatusReading.from(Array(entries.values), now: Date().timeIntervalSince1970)
            )
        } catch {
            Self.log.error("Undecodable agent status file: \(error.localizedDescription, privacy: .public)")
            readingPublisher.send(.idle)
        }
    }
}
