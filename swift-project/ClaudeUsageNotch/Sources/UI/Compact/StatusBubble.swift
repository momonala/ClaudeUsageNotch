import SwiftUI

// MARK: - Incident styling

extension IncidentLevel {
    var tint: Color {
        switch self {
        case .none:        return Theme.statusHealthy
        case .minor:       return Theme.statusWarning
        case .maintenance: return Theme.accentCool
        case .major, .critical: return Theme.statusCritical
        }
    }

    var glyph: String {
        switch self {
        case .maintenance: return "wrench.and.screwdriver.fill"
        default:           return "exclamationmark.triangle.fill"
        }
    }
}

/// Small pill for one-line status callouts (outage, last-synced).
struct StatusBubble: View {
    let icon: String?
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 8, weight: .semibold))
            }
            Text(text)
                .font(.system(size: 9, weight: .medium))
                .lineLimit(1)
        }
        .foregroundColor(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(tint.opacity(Theme.cardFillOpacity))
                .overlay(Capsule().strokeBorder(tint.opacity(Theme.cardStrokeOpacity), lineWidth: Theme.cardStrokeWidth))
        )
    }
}
