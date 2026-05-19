import SwiftUI

struct CompactProgressBar: View {
    var progress: Double  // 0…1
    var color: Color
    @State private var animatedProgress: Double = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Track
                Capsule()
                    .fill(Color.white.opacity(0.08))
                // Fill
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.75), color],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(4, min(1, animatedProgress) * geo.size.width))
                    .shadow(color: color.opacity(0.55), radius: 5, y: 0)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.7)) {
                animatedProgress = progress
            }
        }
        .onChange(of: progress) { newValue in
            withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) {
                animatedProgress = newValue
            }
        }
    }
}
