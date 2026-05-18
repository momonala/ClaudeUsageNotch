import Foundation
import AppKit

/// Helpers for working out where to position the notch panel.
enum ScreenUtils {
    /// Frame of the primary screen, in screen coordinates.
    static func primaryFrame() -> NSRect {
        NSScreen.screens.first?.frame ?? .zero
    }

    /// Frame of the screen that currently has the menu bar.
    static func mainScreenFrame() -> NSRect {
        NSScreen.main?.frame ?? primaryFrame()
    }

    /// Compute the top-center position for a panel of `size`, anchored to the
    /// top of the main screen, accounting for the menu bar / notch area.
    static func topCenteredOrigin(forPanelSize size: NSSize) -> NSPoint {
        let frame = mainScreenFrame()
        let midX = frame.midX
        let originX = midX - (size.width / 2)
        // Top of the screen, minus a tiny gap so we sit inside the notch area.
        let originY = frame.maxY - size.height
        return NSPoint(x: originX, y: originY)
    }
}
