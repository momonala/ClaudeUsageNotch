import SwiftUI

/// Circular arc progress ring. Stroke color and glow are driven by the
/// caller-supplied status colour so the ring is always in sync with the
/// design system's health palette.
struct StatusRingView: View {
    let progress: Double    // 0…1 (clamped internally)
    let color: Color
    var size: CGFloat = 68
    @State private var animatedProgress: CGFloat = 0

    var body: some View {
        ZStack {
            // Track
            Circle()
                .stroke(color.opacity(0.12), lineWidth: lineWidth)

            // Glow layer (blurred, slightly wider)
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    color.opacity(0.30),
                    style: StrokeStyle(lineWidth: lineWidth + 5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .blur(radius: 5)

            // Fill arc
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.7)) {
                animatedProgress = CGFloat(min(progress, 1.0))
            }
        }
        .onChange(of: progress) { newValue in
            withAnimation(.spring(response: 0.6, dampingFraction: 0.75)) {
                animatedProgress = CGFloat(min(newValue, 1.0))
            }
        }
    }

    private var lineWidth: CGFloat { size * 0.085 }
}
