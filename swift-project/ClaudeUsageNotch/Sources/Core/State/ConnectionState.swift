import Foundation

/// Whether the stored credentials work, when usage last synced, and whether a
/// sync is in flight.
public struct ConnectionState: Hashable {
    public enum Credentials: Hashable {
        case notConfigured
        case expired
        case connected(lastSync: Date?)
    }

    public enum Event: Hashable {
        case started(hasCredentials: Bool)
        case credentialsSaved
        case refreshRequested
        case synced(at: Date)
        case failed(ProviderError)
    }

    public enum Effect: Hashable {
        case notifyCredentialsExpired
    }

    public var credentials: Credentials
    public var isSyncing: Bool

    public static let notConfigured = ConnectionState(credentials: .notConfigured)

    public init(credentials: Credentials, isSyncing: Bool = false) {
        self.credentials = credentials
        self.isSyncing = isSyncing
    }

    public var isConnected: Bool {
        if case .connected = credentials { return true }
        return false
    }

    public var lastSyncedAt: Date? {
        guard !isSyncing, case .connected(let at) = credentials else { return nil }
        return at
    }

    @discardableResult
    public mutating func reduce(_ event: Event) -> Effect? {
        switch event {
        case .started(let hasCredentials):
            if !hasCredentials {
                credentials = .notConfigured
            } else if !isConnected {
                credentials = .connected(lastSync: nil)
            }
            return nil

        case .credentialsSaved:
            if !isConnected { credentials = .connected(lastSync: nil) }
            return nil

        case .refreshRequested:
            isSyncing = true
            return nil

        case .synced(let at):
            credentials = .connected(lastSync: at)
            isSyncing = false
            return nil

        case .failed(let error):
            let wasConnected = isConnected
            isSyncing = false
            switch error {
            case .missingCredentials: credentials = .notConfigured
            case .unauthorized:       credentials = .expired
            default:                  if wasConnected { credentials = .connected(lastSync: nil) }
            }
            return wasConnected && error == .unauthorized ? .notifyCredentialsExpired : nil
        }
    }
}
