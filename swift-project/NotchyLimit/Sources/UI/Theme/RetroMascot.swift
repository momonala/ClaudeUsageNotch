import SwiftUI

/// Tiny retro mascot — a friendly square-headed character with a glowing antenna.
/// Implemented as pure SwiftUI shapes so it scales crisply at any size.
struct RetroMascot: View {
    var size: CGFloat = 40
    var blinking: Bool = true

    @State private var blink: Bool = false
    @State private var antennaGlow: Bool = false

    var body: some View {
        ZStack {
            // Antenna
            VStack(spacing: 0) {
                Circle()
                    .fill(Theme.accentWarm)
                    .frame(width: size * 0.16, height: size * 0.16)
                    .shadow(color: Theme.accentWarm.opacity(antennaGlow ? 0.9 : 0.4),
                            radius: antennaGlow ? size * 0.18 : size * 0.08)
                Rectangle()
                    .fill(Theme.textSecondary)
                    .frame(width: size * 0.04, height: size * 0.12)
            }
            .offset(y: -size * 0.46)

            // Head
            RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                .fill(
                    LinearGradient(colors: [Color.white.opacity(0.18), Color.white.opacity(0.06)],
                                   startPoint: .top, endPoint: .bottom)
                )
                .frame(width: size * 0.92, height: size * 0.80)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                        .strokeBorder(Theme.stroke, lineWidth: 1.2)
                )

            // Eyes
            HStack(spacing: size * 0.18) {
                eye()
                eye()
            }
            .offset(y: -size * 0.04)

            // Mouth
            Capsule()
                .fill(Theme.accentCool)
                .frame(width: size * 0.22, height: size * 0.05)
                .offset(y: size * 0.18)
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                antennaGlow.toggle()
            }
            guard blinking else { return }
            Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
                withAnimation(.easeInOut(duration: 0.12)) { blink = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                    withAnimation(.easeInOut(duration: 0.12)) { blink = false }
                }
            }
        }
    }

    @ViewBuilder
    private func eye() -> some View {
        Capsule()
            .fill(Theme.accentWarm)
            .frame(width: size * 0.12, height: blink ? size * 0.02 : size * 0.16)
    }
}
