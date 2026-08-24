import CoreGraphics

/// Single source of truth for the expanded panel's size, per mode.
///
/// Two things need these numbers and must agree: `NotchWindowController` sizes
/// the actual `NSPanel`, and `ExpandedPanelView` sizes the glass card drawn
/// inside it. They used to hardcode the same literals separately, so changing
/// one without the other silently desynced the card from its window.
///
/// The window is taller than the card by `notchGap`: the panel is anchored at
/// the screen top so its first `ScreenUtils.notchHeight` points sit inside the
/// hardware notch, and the gap is the transparent run between the notch's
/// bottom edge and the top of the card.
enum ExpandedPanelGeometry {
    /// Card width — also the window width, since the card spans it fully.
    static func width(for mode: ExpandedMode) -> CGFloat {
        switch mode {
        case .usage:     return 380
        case .analytics: return 1090
        case .settings:  return 460
        }
    }

    /// Height of the glass card itself, excluding the notch overlap and gap.
    static func cardHeight(for mode: ExpandedMode) -> CGFloat {
        switch mode {
        case .usage:     return 120
        case .analytics: return 590
        case .settings:  return 323
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
