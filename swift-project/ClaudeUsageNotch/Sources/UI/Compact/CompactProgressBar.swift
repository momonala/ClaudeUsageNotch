import SwiftUI

struct CompactProgressBar: View {
    var progress: Double  // 0…1
    var color: Color
    @State private var animatedProgress: Double = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(Theme.progressTrackOpacity))
                Capsule()
                    .fill(color)
                    .frame(width: max(4, min(1, animatedProgress) * geo.size.width))
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
}
