import Foundation
import AppKit

/// Helpers for working out where to position the notch panel.
enum ScreenUtils {
    /// The best screen to host the notch panel on.
    /// Preference order:
    ///   1. Screen with a hardware notch (safeAreaInsets.top > 0) — macOS 12+
    ///   2. Built-in display by name
    ///   3. NSScreen.main fallback
    ///
    /// Returns nil only when there are no screens at all (e.g. mid-reconfiguration),
    /// in which case the panel has nothing to anchor to.
    static func notchScreen() -> NSScreen? {
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
        return NSScreen.main ?? NSScreen.screens.first
    }

    /// Height of the hardware notch area (safeAreaInsets.top). 0 on non-notch screens.
    static var notchHeight: CGFloat { notchScreen()?.safeAreaInsets.top ?? 0 }

    static var hasHardwareNotch: Bool {
        NSScreen.screens.contains { $0.safeAreaInsets.top > 0 }
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
        guard let frame = notchScreen()?.frame else { return .zero }
        let originX = frame.midX - (size.width / 2)
        // Panel anchored to the very top of the screen.
        // The caller is responsible for embedding `safeAreaInsets.top` worth
        // of invisible notch-overlap at the top of the panel height so that
        // only the lower portion (below the hardware notch) is ever visible.
        let originY = frame.maxY - size.height
        return NSPoint(x: originX, y: originY)
    }

    // MARK: - Hardware notch width

    /// Width of the physical notch cutout, derived from the areas macOS reports
    /// on either side of it (available since macOS 12 on any screen with a notch).
    /// Falls back to `compactPanelWidthDefault` on screens without a notch, or if
    /// those areas aren't reported for some reason.
    ///
    /// Taken raw, with nothing trimmed off it. A previous version subtracted a
    /// fixed 4 pt per side to account for the cutout's filleted corners; that
    /// constant was tuned by eye against one machine and left the pill visibly
    /// narrower than the housing on another (a 14" MBP reports a 185 pt gap, so
    /// the pill came out 177 pt). macOS documents these areas as abutting the
    /// camera housing, so the gap *is* the cutout width — the fillets are a
    /// question of what shape the pill draws, not how wide it is.
    ///
    /// Do not expect the two areas to be symmetric: the 14" MBP reports 665 pt
    /// left and 662 pt right of a physically centred cutout. That 3 pt of
    /// layout slop is the accuracy ceiling here, which is another reason not to
    /// hand-tune point-level corrections on top of this number.
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
    /// state, with no margin and no floor.
    ///
    /// State-dependent width is deliberately gone. The pill used to grow by
    /// 32 pt once the session hit 100%, to park the reset countdown ("2h 58m")
    /// on visible pixels beside the housing; the cost was a pill that stuck out
    /// ~15 pt each side of the cutout for as long as the limit lasted. The
    /// countdown now fits the same label slot the "%" readout uses — see
    /// `UsageWindow.timeToResetCompactString` — so the silhouette never moves.
    static var compactPanelWidthBase: CGFloat { notchWidth }
}
