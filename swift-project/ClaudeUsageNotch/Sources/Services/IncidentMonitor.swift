import Foundation
import Combine

// MARK: - Domain

/// Severity of a provider's current service status, mapped from statuspage.io's
/// `status.indicator` field.
public enum IncidentLevel: String, Codable, Hashable {
    case none
    case minor
    case major
    case critical
    case maintenance

    public init(indicator: String?) {
        switch indicator?.lowercased() {
        case "minor":       self = .minor
        case "major":       self = .major
        case "critical":    self = .critical
        case "maintenance": self = .maintenance
        default:            self = .none   // "none" or anything unexpected
        }
    }

    /// True when there's an active incident worth badging in the UI.
    public var isActive: Bool { self != .none }

    public var defaultSummary: String {
        switch self {
        case .none:        return "All systems operational"
        case .minor:       return "Minor service issue"
        case .major:       return "Major outage"
        case .critical:    return "Critical outage"
        case .maintenance: return "Under maintenance"
        }
    }
}

/// A point-in-time read of Claude's status page.
public struct ServiceIncident: Hashable, Codable {
    public let level: IncidentLevel
    public let summary: String
    public let checkedAt: Date

    public init(level: IncidentLevel, summary: String, checkedAt: Date = Date()) {
        self.level = level
        self.summary = summary
        self.checkedAt = checkedAt
    }
}

// MARK: - StatusPage client

/// Reads a statuspage.io-backed status page.
final class StatusPageService {
    static let shared = StatusPageService()

    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    private struct StatusPageDTO: Decodable {
        struct Status: Decodable {
            let indicator: String?
            let description: String?
        }
        let status: Status
    }

    func fetchIncident(baseURL: URL) async -> ServiceIncident? {
        let url = baseURL.appendingPathComponent("api/v2/status.json")
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        guard
            let (data, response) = try? await session.data(for: request),
            let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
            let dto = try? JSONDecoder().decode(StatusPageDTO.self, from: data)
        else {
            return nil
        }

        let level = IncidentLevel(indicator: dto.status.indicator)
        let summary = dto.status.description?.isEmpty == false
            ? dto.status.description!
            : level.defaultSummary
        return ServiceIncident(level: level, summary: summary)
    }
}

// MARK: - Monitor

private let claudeStatusURL = URL(string: "https://status.anthropic.com")!

/// Polls Claude's status page on a slow cadence and publishes incidents.
/// Independent of auth — outages are public.
final class IncidentMonitor {
    static let shared = IncidentMonitor()
    private init() {}

    let incidentPublisher = PassthroughSubject<ServiceIncident, Never>()

    private var task: Task<Void, Never>?

    /// Outages are public and slow-moving, so a fixed slow cadence is plenty.
    private static let pollInterval: TimeInterval = 300

    func start() {
        stop()
        task = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.pollOnce()
                try? await Task.sleep(nanoseconds: UInt64(Self.pollInterval * 1_000_000_000))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func pollOnce() async {
        guard let incident = await StatusPageService.shared.fetchIncident(baseURL: claudeStatusURL) else { return }
        incidentPublisher.send(incident)
    }
}
