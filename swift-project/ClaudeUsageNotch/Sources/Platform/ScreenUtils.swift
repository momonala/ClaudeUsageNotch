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

    /// Points trimmed from each side of the gap macOS reports between the
    /// menu bar's two auxiliary areas.
    ///
    /// Those areas abut the cutout's *bounding box*, which includes the
    /// filleted corners where its edges curve back inward. A pill drawn to the
    /// full reported gap therefore overhangs the cutout by a few points on each
    /// side, visible as two slivers of pill sticking out past the black
    /// housing. Trimming brings its edges flush with the cutout's straight
    /// sides. The fillet radius is a constant across the notched MacBooks, so
    /// this is a fixed inset rather than something derived per-screen.
    private static let notchFilletInset: CGFloat = 4

    /// Width of the physical notch cutout, derived from the areas macOS reports
    /// on either side of it (available since macOS 12 on any screen with a notch).
    /// Falls back to `compactPanelWidthDefault` on screens without a notch, or if
    /// those areas aren't reported for some reason.
    static var notchWidth: CGFloat {
        guard let screen = notchScreen(), screen.safeAreaInsets.top > 0 else {
            return compactPanelWidthDefault
        }
        let leftWidth = screen.auxiliaryTopLeftArea?.width ?? 0
        let rightWidth = screen.auxiliaryTopRightArea?.width ?? 0
        guard leftWidth > 0 || rightWidth > 0 else { return compactPanelWidthDefault }
        return screen.frame.width - leftWidth - rightWidth - (notchFilletInset * 2)
    }

    // MARK: - Compact panel width

    static let compactPanelWidthDefault: CGFloat = 176
    /// Extra width when the session row shows a countdown instead of "%".
    private static let compactCountdownWidthBump: CGFloat = 32
    private static let compactPercentSlotWidth: CGFloat = 25

    /// Baseline compact pill width: exactly this machine's notch cutout.
    ///
    /// Deliberately carries no margin, and is not floored at
    /// `compactPanelWidthDefault` — a `max()` against that default silently
    /// overshot the cutout on any Mac whose notch is narrower than it (the 13"
    /// Air reports a 179 pt gap, so a 176 pt floor is within a few points of
    /// mattering). `notchWidth` already falls back to the default on screens
    /// with no notch at all, which is the only case the floor was protecting.
    static var compactPanelWidthBase: CGFloat { notchWidth }

    /// Widen the compact pill for session-limit countdowns (e.g. "2h 1m") so the
    /// label sits further into the visible "ear" beside the hardware notch.
    static func compactPanelWidth(atSessionLimit: Bool, countdownText: String?) -> CGFloat {
        let base = compactPanelWidthBase
        guard atSessionLimit else { return base }
        let font = NSFont.monospacedSystemFont(ofSize: 9, weight: .bold)
        let text = countdownText ?? "LIMIT"
        let textWidth = ceil((text as NSString).size(withAttributes: [.font: font]).width)
        let measuredExtra = max(0, textWidth + 12 - compactPercentSlotWidth)
        let extra = max(measuredExtra, compactCountdownWidthBump)
        return min(base + extra, base + 48)
    }
}
