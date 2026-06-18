import SwiftUI

/// Theme tokens. All design constants live here — do not inline values in views.
enum Theme {
    // Base background tones
    static let background      = Color(red: 0.04, green: 0.04, blue: 0.05)
    static let surface         = Color.white.opacity(0.06)
    static let surfaceElevated = Color.white.opacity(0.10)
    static let stroke          = Color.white.opacity(0.10)
    static let textPrimary     = Color.white.opacity(0.96)
    static let textSecondary   = Color.white.opacity(0.62)
    static let textLabel       = Color.white.opacity(0.88)

    // Accents — system blue primary + system teal for maintenance state.
    static let accentWarm = Color(nsColor: .systemBlue)
    static let accentCool = Color(nsColor: .systemTeal)

    // Status colors — semantic system colors, adapt to increased contrast and appearance.
    static let statusHealthy  = Color(nsColor: .systemGreen)
    static let statusWarning  = Color(nsColor: .systemOrange)
    static let statusCritical = Color(nsColor: .systemRed)
    static let statusUnknown  = Color(nsColor: .secondaryLabelColor)

    // MARK: - Typography

    static let displayFont = Font.system(.title2, design: .rounded).weight(.semibold)
    static let bodyFont    = Font.system(.body, design: .rounded)
    static let captionFont = Font.system(.caption, design: .rounded)
    static let numericFont = Font.system(.body, design: .monospaced).weight(.semibold)

    // Compact notch strip
    static let notchFont     = Font.system(size: 9, weight: .semibold, design: .monospaced)
    static let notchFontBold = Font.system(size: 9, weight: .bold,     design: .monospaced)
    static let notchFontTiny = Font.system(size: 8, weight: .semibold, design: .monospaced)

    // Expanded panel header
    static let headerFont = Font.system(size: 11, weight: .semibold, design: .rounded)
    static let headerFontRegular = Font.system(size: 11, design: .rounded)

    // Status cards (expanded panel)
    static let cardTitleFont    = Font.system(size: 12, weight: .semibold, design: .rounded)
    static let cardSubtitleFont = Font.system(size: 10,                    design: .rounded)
    static let cardValueFont    = Font.system(size: 14, weight: .bold,     design: .monospaced)
    static let weeklyValueFont  = Font.system(size: 13, weight: .bold,     design: .monospaced)

    // Settings
    static let sectionLabelFont:    Font    = Font.system(size: 10, weight: .semibold, design: .rounded)
    static let sectionLabelKerning: CGFloat = 0.8
    static let iconBgSize:          CGFloat = 34
    static let iconCornerRadius:    CGFloat = 8

    // MARK: - Layout

    /// Height of the visible strip below the hardware notch in compact mode.
    static let compactStripHeight: CGFloat = 22

    // MARK: - Progress bar

    static let progressTrackOpacity: Double = 0.08
    static let barHeightExpanded: CGFloat = 5
    static let barHeightNotch:    CGFloat = 3
    /// Vertical marker showing where usage "should" be based on elapsed window time.
    static let paceMarkerColor: Color = Color(nsColor: .white)
    static let paceMarkerWidth: CGFloat = 1.5

    // MARK: - Status card

    static let cardCornerRadius:  CGFloat = 12
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

// MARK: - View helpers

extension View {
    /// Standard tinted card background shared by SessionCard and WeeklyCard.
    func statusCardStyle(color: Color) -> some View {
        background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(color.opacity(Theme.cardFillOpacity))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                        .strokeBorder(color.opacity(Theme.cardStrokeOpacity), lineWidth: Theme.cardStrokeWidth)
                )
        )
    }
}
