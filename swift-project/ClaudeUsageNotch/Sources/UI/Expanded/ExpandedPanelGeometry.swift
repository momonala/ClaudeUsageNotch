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
        // Fits the settings pane at the width above in its tallest state
        // (validation footer showing), plus clearance for the corner sweep.
        // There's no scroll view, so too short clips it.
        case .settings:  return 548
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

    /// The `.usage` base height has slack for most of one optional card
    /// (Fable, usage credits); each further card needs a full row.
    static let usageFirstExtraCard: CGFloat = 5
    static let usageExtraCard:      CGFloat = 38

    static func cardHeight(for mode: ExpandedMode, snapshot: ServiceUsageSnapshot?) -> CGFloat {
        let base = cardHeight(for: mode)
        guard mode == .usage, let cards = snapshot?.extraWindowCount, cards > 0 else { return base }
        return base + usageFirstExtraCard + CGFloat(cards - 1) * usageExtraCard
    }

    /// Panel content height below the screen top, excluding the notch overlap.
    /// Callers add `ScreenUtils.notchHeight` to get the full panel height.
    static func windowContentHeight(for mode: ExpandedMode, snapshot: ServiceUsageSnapshot?) -> CGFloat {
        cardHeight(for: mode, snapshot: snapshot) + notchGap(for: mode)
    }
}
