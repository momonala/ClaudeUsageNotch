import Foundation
import AppKit

/// Heuristic check for a hardware notch. macOS exposes
/// `NSScreen.safeAreaInsets.top > 0` on MacBooks with a notch.
enum NotchDetector {
    static func hasHardwareNotch() -> Bool {
        guard let main = NSScreen.main else { return false }
        return main.safeAreaInsets.top > 0
    }
}
