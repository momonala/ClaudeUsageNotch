import Foundation
import AppKit

/// Helpers for working out where to position the notch panel.
enum ScreenUtils {
    /// The best screen to host the notch panel on, preferring a hardware
    /// cutout, then the built-in display by name, then whatever is main.
    ///
    /// Nil only when there are no screens at all (e.g. mid-reconfiguration),
    /// in which case the panel has nothing to anchor to.
    static func notchScreen() -> NSScreen? {
        if let notched = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) {
            return notched
        }
        let builtInNames = ["built-in", "retina", "liquid retina", "color lcd"]
        if let builtIn = NSScreen.screens.first(where: { screen in
            let name = screen.localizedName.lowercased()
            return builtInNames.contains(where: { name.contains($0) })
        }) {
            return builtIn
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    /// Height of the hardware notch area (safeAreaInsets.top). 0 on non-notch screens.
    static var notchHeight: CGFloat { notchScreen()?.safeAreaInsets.top ?? 0 }

    /// Top-centre position for a panel of `size`, flush with the screen's top
    /// edge. Callers are responsible for including `notchHeight` in that size,
    /// so only the portion below the hardware cutout is ever visible.
    static func topCenteredOrigin(forPanelSize size: NSSize) -> NSPoint {
        guard let frame = notchScreen()?.frame else { return .zero }
        return NSPoint(x: frame.midX - (size.width / 2), y: frame.maxY - size.height)
    }

    // MARK: - Hardware notch width

    /// Width of the physical notch cutout, derived from the areas macOS reports
    /// on either side of it. Falls back to `compactPanelWidthDefault` when
    /// there's no cutout, or those areas aren't reported.
    ///
    /// Taken raw, with nothing trimmed off: macOS documents these areas as
    /// abutting the camera housing, so the gap *is* the cutout width, and the
    /// filleted corners are a question of what shape the pill draws rather than
    /// how wide it is. Don't expect the two areas to be symmetric either — a
    /// 14" MBP reports 665 pt left and 662 pt right of a physically centred
    /// cutout, and that 3 pt of slop is the accuracy ceiling here.
    static var notchWidth: CGFloat {
        guard let screen = notchScreen(), screen.safeAreaInsets.top > 0 else {
            return compactPanelWidthDefault
        }
        let leftWidth = screen.auxiliaryTopLeftArea?.width ?? 0
        let rightWidth = screen.auxiliaryTopRightArea?.width ?? 0
        guard leftWidth > 0 || rightWidth > 0 else { return compactPanelWidthDefault }
        return screen.frame.width - leftWidth - rightWidth
    }

    // MARK: - Compact panel width

    /// Width of the compact pill on a screen with no hardware cutout, where
    /// there is no cutout to match and the pill is free-standing.
    static let compactPanelWidthDefault: CGFloat = 176

    /// The compact pill is exactly this machine's notch cutout — in every
    /// state, with no margin and no floor. Nothing about the session's usage
    /// may widen it: the reset countdown at the limit fits the same label slot
    /// the "%" readout uses (see `UsageWindow.CountdownWidth`).
    static var compactPanelWidthBase: CGFloat { notchWidth }
}
