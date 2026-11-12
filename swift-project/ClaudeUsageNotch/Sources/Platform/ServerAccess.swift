import Foundation

enum ServerAccess {
    private static let store = KeychainStore(service: "com.claudeusagenotch.server-access")

    static func authorize(_ request: inout URLRequest) {
        guard let id = value(for: "client-id"), let secret = value(for: "client-secret") else { return }
        request.setValue(id, forHTTPHeaderField: "CF-Access-Client-Id")
        request.setValue(secret, forHTTPHeaderField: "CF-Access-Client-Secret")
    }

    private static func value(for account: String) -> String? {
        store.get(account: account).flatMap { String(data: $0, encoding: .utf8) }
    }
}
