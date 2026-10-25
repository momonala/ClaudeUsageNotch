import Foundation

/// The macOS Computer Name, which identifies this Mac to the sync server.
/// `ProcessInfo.hostName` follows the network (VPN, Wi-Fi), so one Mac reports several names.
enum DeviceName {
    static let current = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
    static let header = "X-Device-Name"

    /// Header values must be ASCII, and Computer Names often contain a curly apostrophe.
    static let headerValue = current.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "unknown"
}
