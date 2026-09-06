import CoreGraphics

/// Single source of truth for the expanded panel's size, per mode: shared by
/// `NotchWindowController`, which sizes the `NSPanel`, and `ExpandedPanelView`,
/// which sizes the card inside it.
///
/// The window is taller than the card by `notchGap`, plus the
/// `ScreenUtils.notchHeight` points hidden inside the hardware notch.
enum ExpandedPanelGeometry {
    /// Card width — also the window width, since the card spans it fully.
    static func width(for mode: ExpandedMode) -> CGFloat {
        switch mode {
        case .usage:     return 380
        case .analytics: return 1090
        // The settings pane's ideal width, set by the threshold row: five 58pt
        // checkboxes beside their indented label. Narrower wraps the labels.
        case .settings:  return 420
        }
    }

    /// Height of the glass card itself, excluding the notch overlap and gap.
    static func cardHeight(for mode: ExpandedMode) -> CGFloat {
        switch mode {
        case .usage:     return 120
        case .analytics: return 590
        // The settings pane measures ~463.5pt at the width above, in its
        // tallest state (validation footer showing); the remainder is clearance
        // for the corner sweep. There's no scroll view, so too short clips it.
        case .settings:  return 468
        }
    }

    /// Transparent run between the hardware notch's bottom edge and the card.
    static func notchGap(for mode: ExpandedMode) -> CGFloat {
        switch mode {
        case .usage:     return 38
        case .analytics: return 28
        case .settings:  return 28
        }
    }

    /// Extra card height for the optional "Usage credits" card (Team plans only).
    static let usageCreditExtra: CGFloat = 5

    /// Panel content height below the screen top, excluding the notch overlap.
    /// Callers add `ScreenUtils.notchHeight` to get the full panel height.
    static func windowContentHeight(for mode: ExpandedMode, hasCredit: Bool) -> CGFloat {
        let credit = (mode == .usage && hasCredit) ? usageCreditExtra : 0
        return cardHeight(for: mode) + notchGap(for: mode) + credit
    }
}
