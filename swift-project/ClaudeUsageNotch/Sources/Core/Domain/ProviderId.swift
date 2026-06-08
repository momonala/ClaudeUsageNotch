import Foundation

public enum ProviderId: String, Codable, Hashable, CaseIterable {
    case claude

    public var displayName: String { "Claude" }
    public var iconSymbol: String { "sparkle" }
    public var statusPageBaseURL: URL? { URL(string: "https://status.anthropic.com") }
}
