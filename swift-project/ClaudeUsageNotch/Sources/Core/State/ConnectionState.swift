import Foundation

/// Whether the stored credentials work, and when usage last synced.
public indirect enum ConnectionState: Hashable {
    case notConfigured
    case expired
    case connected(lastSync: Date?)
    case syncing(from: ConnectionState)

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

    /// The state with any in-flight sync stripped off.
    public var settled: ConnectionState {
        if case .syncing(let from) = self { return from.settled }
        return self
    }

    public var isConnected: Bool {
        if case .connected = settled { return true }
        return false
    }

    public var isSyncing: Bool {
        if case .syncing = self { return true }
        return false
    }

    public var lastSyncedAt: Date? {
        if case .connected(let at) = self { return at }
        return nil
    }

    @discardableResult
    public mutating func reduce(_ event: Event) -> Effect? {
        switch event {
        case .started(let hasCredentials):
            self = replacingSettled(hasCredentials ? connectedKeepingSync : .notConfigured)
            return nil

        case .credentialsSaved:
            self = replacingSettled(connectedKeepingSync)
            return nil

        case .refreshRequested:
            self = .syncing(from: settled)
            return nil

        case .synced(let at):
            self = .connected(lastSync: at)
            return nil

        case .failed(let error):
            let wasConnected = isConnected
            switch error {
            case .missingCredentials: self = .notConfigured
            case .unauthorized:       self = .expired
            default:                  self = wasConnected ? .connected(lastSync: nil) : settled
            }
            return wasConnected && error == .unauthorized ? .notifyCredentialsExpired : nil
        }
    }

    private var connectedKeepingSync: ConnectionState {
        if case .connected = settled { return settled }
        return .connected(lastSync: nil)
    }

    private func replacingSettled(_ next: ConnectionState) -> ConnectionState {
        isSyncing ? .syncing(from: next) : next
    }
}
