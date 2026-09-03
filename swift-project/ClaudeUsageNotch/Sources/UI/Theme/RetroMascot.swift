import SwiftUI

/// Retro robot mascot for the onboarding header: breathes, sways and glows its
/// antenna, blinks, and occasionally glances sideways.
struct RetroMascot: View {
    var size: CGFloat = 40

    @State private var breatheScale: CGFloat = 1.0
    @State private var antennaGlow = false
    @State private var antennaSway: Double = 0
    @State private var blink = false
    @State private var eyeShift: Double = 0
    @State private var appeared = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            antenna
            head
            eyes
            smile
                .offset(y: size * 0.18)
        }
        .frame(width: size, height: size)
        .scaleEffect(appeared ? breatheScale : 0.4)
        .opacity(appeared ? 1 : 0)
        .onAppear(perform: startAnimations)
        .onDisappear { breatheScale = 1.0 }
        .task { await blinkLoop() }
        .task { await eyeScanLoop() }
    }

    // MARK: - Sub-views

    private var antenna: some View {
        VStack(spacing: 0) {
            Circle()
                .fill(Theme.accentWarm)
                .frame(width: size * 0.17, height: size * 0.17)
                .shadow(
                    color: Theme.accentWarm.opacity(antennaGlow ? 0.40 : 0.15),
                    radius: antennaGlow ? size * 0.08 : size * 0.03
                )
                .scaleEffect(antennaGlow ? 1.15 : 0.92)
            Rectangle()
                .fill(Theme.textSecondary.opacity(0.7))
                .frame(width: size * 0.04, height: size * 0.13)
        }
        .offset(x: antennaSway * size * 0.04, y: -size * 0.47)
        .rotationEffect(.degrees(antennaSway * 3.5))
    }

    private var head: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.19, style: .continuous)
        return shape
            .fill(Color.white.opacity(0.12))
            .frame(width: size * 0.92, height: size * 0.80)
            .overlay(shape.strokeBorder(Color.white.opacity(0.18), lineWidth: 1.2))
    }

    private var eyes: some View {
        HStack(spacing: size * 0.18) {
            eye
            eye
        }
        .offset(x: eyeShift * size * 0.06, y: -size * 0.04)
    }

    private var eye: some View {
        Capsule()
            .fill(Theme.accentWarm)
            .frame(width: size * 0.12, height: blink ? size * 0.02 : size * 0.16)
            .shadow(color: Theme.accentWarm.opacity(0.5), radius: size * 0.06)
    }

    private var smile: some View {
        Arc(startAngle: .degrees(10), endAngle: .degrees(170), clockwise: false)
            .stroke(Theme.accentCool, style: StrokeStyle(lineWidth: size * 0.05, lineCap: .round))
            .frame(width: size * 0.26, height: size * 0.10)
    }

    // MARK: - Animation

    private func startAnimations() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.55, blendDuration: 0)) {
            appeared = true
        }
        if !reduceMotion {
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                breatheScale = 1.025
            }
        }
        withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
            antennaGlow.toggle()
        }
        withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
            antennaSway = 0.4
        }
    }

    private func blinkLoop() async {
        defer { withAnimation(.easeInOut(duration: 0.09)) { blink = false } }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(3.5))
            if Task.isCancelled { break }
            withAnimation(.easeInOut(duration: 0.09)) { blink = true }
            try? await Task.sleep(for: .milliseconds(110))
            withAnimation(.easeInOut(duration: 0.09)) { blink = false }
        }
    }

    private func eyeScanLoop() async {
        defer { withAnimation(.easeInOut(duration: 0.3)) { eyeShift = 0 } }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Double.random(in: 4...8)))
            if Task.isCancelled { break }
            withAnimation(.easeInOut(duration: 0.3)) { eyeShift = Bool.random() ? 1 : -1 }
            try? await Task.sleep(for: .milliseconds(900))
            withAnimation(.easeInOut(duration: 0.3)) { eyeShift = 0 }
        }
    }
}

private struct Arc: Shape {
    var startAngle: Angle
    var endAngle: Angle
    var clockwise: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: rect.width / 2,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: clockwise
        )
        return path
    }
}
