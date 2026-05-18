import Foundation

/// Stable, machine-readable identifier for a usage provider.
/// Used for keychain keys, settings storage, and analytics-free debug logs.
public enum ProviderId: String, Codable, Hashable, CaseIterable {
    case claude
    case gemini   // future
    case chatgpt  // future

    public var displayName: String {
        switch self {
        case .claude:  return "Claude"
        case .gemini:  return "Gemini"
        case .chatgpt: return "ChatGPT"
        }
    }

    /// True if the provider is implemented and selectable in onboarding.
    public var isAvailable: Bool {
        switch self {
        case .claude:  return true
        case .gemini:  return false
        case .chatgpt: return false
        }
    }
}
