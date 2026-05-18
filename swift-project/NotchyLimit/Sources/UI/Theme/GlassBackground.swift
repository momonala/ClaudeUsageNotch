import SwiftUI

/// Reusable glass background with subtle inner border.
struct GlassBackground: View {
    var cornerRadius: CGFloat = 18
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Theme.background.opacity(0.78))
            // Soft inner highlight to give depth.
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 1)
            // Faint top-left highlight.
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.06), Color.clear],
                        startPoint: .topLeading,
                        endPoint: .center
                    )
                )
                .blendMode(.plusLighter)
        }
    }
}
