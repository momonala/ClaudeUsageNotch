import SwiftUI

/// Theme tokens. All design constants live here — do not inline values in views.
enum Theme {
    // Base background tones (deep near-black with subtle warmth).
    static let background      = Color(red: 0.04, green: 0.04, blue: 0.05)
    static let surface         = Color.white.opacity(0.06)
    static let surfaceElevated = Color.white.opacity(0.10)
    static let stroke          = Color.white.opacity(0.10)
    static let textPrimary     = Color.white.opacity(0.96)
    static let textSecondary   = Color.white.opacity(0.62)
    static let textLabel       = Color.white.opacity(0.88)

    // Accents — system blue primary + desaturated teal for maintenance state.
    static let accentWarm = Color(nsColor: .systemBlue)
    static let accentCool = Color(red: 0.35, green: 0.75, blue: 0.82)

    // Status colors (color-coded thresholds).
    static let statusHealthy  = Color(red: 0.33, green: 0.84, blue: 0.55)
    static let statusWarning  = Color(red: 1.00, green: 0.78, blue: 0.20)
    static let statusCritical = Color(red: 1.00, green: 0.40, blue: 0.38)
    static let statusUnknown  = Color.white.opacity(0.35)

    // MARK: - Typography

    static let displayFont = Font.system(.title2, design: .rounded).weight(.semibold)
    static let bodyFont    = Font.system(.body, design: .rounded)
    static let captionFont = Font.system(.caption, design: .rounded)
    static let numericFont = Font.system(.body, design: .monospaced).weight(.semibold)

    // Compact notch strip
    static let notchFont     = Font.system(size: 9, weight: .semibold, design: .monospaced)
    static let notchFontBold = Font.system(size: 9, weight: .bold,     design: .monospaced)

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

    // MARK: - Progress bar

    static let progressTrackOpacity: Double = 0.08

    /// Bar height for all rows in the expanded hover panel.
    static let barHeightExpanded: CGFloat = 5
    /// Bar height for all rows in the compact notch strip.
    static let barHeightNotch: CGFloat = 3

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
