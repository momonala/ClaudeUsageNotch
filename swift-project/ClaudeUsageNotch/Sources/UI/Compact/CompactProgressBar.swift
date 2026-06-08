import SwiftUI

struct CompactProgressBar: View {
    var progress: Double  // 0…1
    var color: Color
    /// Elapsed-time pace through the window (0…1). Drawn as a vertical white tick.
    var expectedProgress: Double? = nil
    @State private var animatedProgress: Double = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(Theme.progressTrackOpacity))
                Capsule()
                    .fill(color)
                    .frame(width: max(4, min(1, animatedProgress) * geo.size.width))
                if let pace = expectedProgress {
                    paceMarker(at: pace, in: geo.size)
                }
            }
        }
        .onAppear {
            withAnimation(.spring(response: Theme.springResponse, dampingFraction: Theme.springDamping)) {
                animatedProgress = progress
            }
        }
        .onChange(of: progress) { _, newValue in
            withAnimation(.spring(response: Theme.springResponse, dampingFraction: Theme.springDamping)) {
                animatedProgress = newValue
            }
        }
    }

    private func paceMarker(at pace: Double, in size: CGSize) -> some View {
        let x = min(size.width, max(0, pace * size.width))
        return Rectangle()
            .fill(Theme.paceMarkerColor)
            .frame(width: Theme.paceMarkerWidth, height: size.height + 1)
            .offset(x: x - Theme.paceMarkerWidth / 2)
    }
}
