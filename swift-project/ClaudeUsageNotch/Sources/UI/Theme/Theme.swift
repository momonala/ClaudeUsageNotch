import SwiftUI

/// Theme tokens. All design constants live here — do not inline values in views.
enum Theme {
    static let background      = Color(red: 0.04, green: 0.04, blue: 0.05)
    static let surface         = Color.white.opacity(0.06)
    static let stroke          = Color.white.opacity(0.10)
    static let textPrimary     = Color.white.opacity(0.96)
    static let textSecondary   = Color.white.opacity(0.62)
    static let textLabel       = Color.white.opacity(0.88)

    static let accentWarm = Color(nsColor: .systemBlue)
    static let accentCool = Color(nsColor: .systemTeal)

    // Semantic system colors: they adapt to increased contrast.
    static let statusHealthy  = Color(nsColor: .systemGreen)
    static let statusWarning  = Color(nsColor: .systemOrange)
    static let statusCritical = Color(nsColor: .systemRed)
    static let statusUnknown  = Color(nsColor: .secondaryLabelColor)

    // MARK: - Typography

    static let displayFont = Font.system(.title2, design: .rounded).weight(.semibold)
    static let bodyFont    = Font.system(.body, design: .rounded)
    static let captionFont = Font.system(.caption, design: .rounded)
    static let numericFont = Font.system(.body, design: .monospaced).weight(.semibold)

    static let notchFont     = Font.system(size: 9, weight: .semibold, design: .monospaced)
    static let notchFontBold = Font.system(size: 9, weight: .bold,     design: .monospaced)

    static let cardTitleFont     = Font.system(size: 12, weight: .semibold, design: .rounded)
    static let cardSubtitleFont  = Font.system(size: 10,                    design: .rounded)
    static let cardResetDateFont = Font.system(size: 9,                     design: .rounded)
    static let cardValueFont     = Font.system(size: 14, weight: .bold,     design: .monospaced)
    static let weeklyValueFont   = Font.system(size: 13, weight: .bold,     design: .monospaced)

    static let sectionLabelFont:    Font    = Font.system(size: 10, weight: .semibold, design: .rounded)
    static let sectionLabelKerning: CGFloat = 0.8

    // MARK: - Settings pane

    /// System label hierarchy rather than hardcoded opacities, so disabled rows get
    /// the platform's dimming. Resolved against the panel's pinned dark appearance.
    static let labelPrimary   = Color(nsColor: .labelColor)
    static let labelSecondary = Color(nsColor: .secondaryLabelColor)
    static let labelTertiary  = Color(nsColor: .tertiaryLabelColor)

    /// Sizes track the macOS built-in text styles (HIG > Typography) in the
    /// app's rounded variant.
    static let settingsTitleFont   = Font.system(size: 13, weight: .semibold, design: .rounded)
    static let settingsSectionFont = Font.system(size: 11, weight: .semibold, design: .rounded)
    static let settingsRowFont     = Font.system(size: 12,                    design: .rounded)
    static let settingsCaptionFont = Font.system(size: 10,                    design: .rounded)

    static let settingsRowMinHeight: CGFloat = 28
    static let settingsRowPaddingV:  CGFloat = 4
    /// Indents rows subordinate to the switch above them, so the dependency reads
    /// structurally and not just by dimming.
    static let settingsRowIndent:    CGFloat = 14
    static let settingsGroupSpacing: CGFloat = 11
    /// Sized to the longest label ("100%") and applied to all of them so the
    /// column aligns.
    static let settingsCheckboxWidth: CGFloat = 58
    /// Equal across rows so the trailing controls form one aligned column.
    static let settingsControlWidth: CGFloat = 104

    // MARK: - Notch switch and checkbox (see NotchToggleStyles)

    /// Sized to AppKit's mini switch so switch rows match button rows.
    static let switchTrackSize  = CGSize(width: 26, height: 15)
    static let switchKnobInset:   CGFloat = 2
    static let switchKnobShadow:  CGFloat = 1
    static let checkboxSize:      CGFloat = 13
    static let checkboxRadius:    CGFloat = 3.5
    static let checkmarkSize:     CGFloat = 8
    /// Off-state fills; the hairline gives them an edge against the panel's
    /// black. On-state is `accentWarm`.
    static let toggleOffFill    = Color.white.opacity(0.09)
    static let toggleOffStroke  = Color.white.opacity(0.20)
    /// Tertiary-label dimming doesn't apply to a filled shape, so the on/off
    /// distinction is preserved at lower contrast instead.
    static let toggleDisabledOnFill  = Color.white.opacity(0.20)
    static let toggleDisabledOffFill = Color.white.opacity(0.05)
    static let toggleDisabledKnob    = Color.white.opacity(0.5)
    static let togglePressedScale: CGFloat = 0.92

    // MARK: - Notch panel shape

    /// Top corners hug the hardware notch's inner curve; the bottom sweeps wider.
    static let panelTopRadius:     CGFloat = 10
    static let panelBottomRadius:  CGFloat = 20
    static let panelContentMargin: CGFloat = 12

    // MARK: - Layout

    /// Visible strip below the hardware notch. Must match what `CompactView` lays
    /// out (2 bar rows plus `compactContentBottomInset`), or the top row renders
    /// partially inside the hidden notch area.
    static let compactStripHeight: CGFloat = 30
    /// Bottom corner radius of the compact pill's black fill. `AgentStatusGlow`
    /// derives its own radius from this so the ring curves parallel to it.
    static let compactPillBottomRadius: CGFloat = 14
    /// Extra strip height for the optional third (credit) bar row.
    static let compactStripHeightCredit: CGFloat = 14
    /// Gap between the last bar row and the pill's bottom edge; without it the
    /// trailing percentage label runs through the bottom corner's arc.
    static let compactContentBottomInset: CGFloat = 5

    // MARK: - Progress bar

    static let progressTrackOpacity: Double = 0.08
    static let barHeightExpanded: CGFloat = 5
    static let barHeightNotch:    CGFloat = 3
    static let paceMarkerColor: Color = Color(nsColor: .white)
    static let paceMarkerWidth: CGFloat = 1.5

    // MARK: - Status card

    static let cardPaddingH:      CGFloat = 12
    static let cardPaddingV:      CGFloat = 6
    static let cardFillOpacity:   Double  = 0.06
    static let cardStrokeOpacity: Double  = 0.18
    static let cardStrokeWidth:   CGFloat = 0.75

    // MARK: - Spring animation

    static let springResponse: Double = 0.55
    static let springDamping:  Double = 0.72
}

// MARK: - Status color mapping (kept here so domain stays SwiftUI-free)

extension UsageStatus {
    var color: Color {
        switch self {
        case .healthy:  return Theme.statusHealthy
        case .warning:  return Theme.statusWarning
        case .critical: return Theme.statusCritical
        case .unknown:  return Theme.statusUnknown
        }
    }
}
