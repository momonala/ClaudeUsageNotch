import SwiftUI

struct CompactProgressBar: View {
    var progress: Double // 0...1+
    var color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.surface)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [color, color.opacity(0.85)],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: max(2, min(1, progress) * geo.size.width))
                    .shadow(color: color.opacity(0.4), radius: 4, y: 0)
            }
        }
    }
}
