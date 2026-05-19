import Foundation
import AppKit

/// Helpers for working out where to position the notch panel.
enum ScreenUtils {
    /// The best screen to host the notch panel on.
    /// Preference order:
    ///   1. Screen with a hardware notch (safeAreaInsets.top > 0) — macOS 12+
    ///   2. Built-in display by name
    ///   3. NSScreen.main fallback
    static func notchScreen() -> NSScreen {
        // 1. Find a screen with an actual notch cutout.
        if let notched = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) {
            return notched
        }
        // 2. Built-in display by name (covers older macOS or edge cases).
        let builtInNames = ["built-in", "retina", "liquid retina", "color lcd"]
        if let builtIn = NSScreen.screens.first(where: { screen in
            let name = screen.localizedName.lowercased()
            return builtInNames.contains(where: { name.contains($0) })
        }) {
            return builtIn
        }
        // 3. Main screen fallback.
        return NSScreen.main ?? NSScreen.screens[0]
    }

    /// Compute the top-center position for a panel of `size`.
    ///
    /// On notch MacBooks the physical camera housing occupies the top
    /// `safeAreaInsets.top` points of the screen — there are literally no
    /// display pixels there. We offset by that amount so the panel sits
    /// flush against the BOTTOM edge of the notch, fully in visible pixels.
    /// On non-notch screens `safeAreaInsets.top` is 0, so behaviour is
    /// unchanged.
    static func topCenteredOrigin(forPanelSize size: NSSize) -> NSPoint {
        let frame = notchScreen().frame
        let originX = frame.midX - (size.width / 2)
        // Panel anchored to the very top of the screen.
        // The caller is responsible for embedding `safeAreaInsets.top` worth
        // of invisible notch-overlap at the top of the panel height so that
        // only the lower portion (below the hardware notch) is ever visible.
        let originY = frame.maxY - size.height
        return NSPoint(x: originX, y: originY)
    }
}
