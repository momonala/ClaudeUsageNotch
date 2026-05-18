import SwiftUI

/// Theme tokens. Dark glassmorphic palette with a soft retro accent.
enum Theme {
    // Base background tones (deep near-black with subtle warmth).
    static let background      = Color(red: 0.04, green: 0.04, blue: 0.05)
    static let surface         = Color.white.opacity(0.06)
    static let surfaceElevated = Color.white.opacity(0.10)
    static let stroke          = Color.white.opacity(0.10)
    static let textPrimary     = Color.white.opacity(0.96)
    static let textSecondary   = Color.white.opacity(0.62)

    // Retro accents — warm peach + cool cyan glow.
    static let accentWarm = Color(red: 1.0,  green: 0.55, blue: 0.42)
    static let accentCool = Color(red: 0.43, green: 0.94, blue: 0.96)

    // Status colors (color-coded thresholds).
    static let statusHealthy  = Color(red: 0.33, green: 0.84, blue: 0.55)
    static let statusWarning  = Color(red: 1.00, green: 0.78, blue: 0.20)
    static let statusCritical = Color(red: 1.00, green: 0.40, blue: 0.38)
    static let statusUnknown  = Color.white.opacity(0.35)

    // Typography
    static let displayFont = Font.system(.title2, design: .rounded).weight(.semibold)
    static let bodyFont    = Font.system(.body, design: .rounded)
    static let captionFont = Font.system(.caption, design: .rounded)
    static let numericFont = Font.system(.body, design: .monospaced).weight(.semibold)
}
