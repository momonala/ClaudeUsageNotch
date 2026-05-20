import SwiftUI

/// Retro robot mascot with Lottie-style SwiftUI animations.
///
/// Animations driven by `usagePercent`:
///   0.00–0.74 → happy  (slow breathe, gentle antenna sway, occasional eye scan)
///   0.75–0.89 → worried (faster breathe, brow furrow, quicker blinks)
///   0.90–1.00 → alarmed (rapid antenna pulse, wide eyes, head tilt)
struct RetroMascot: View {
    var size: CGFloat = 40
    var usagePercent: Double = 0

    // Breathing
    @State private var breatheScale: CGFloat = 1.0
    // Antenna
    @State private var antennaGlow: Bool = false
    @State private var antennaSway: Double = 0
    // Eyes
    @State private var blink: Bool = false
    @State private var eyeShift: Double = 0
    // Entry
    @State private var appeared: Bool = false
    // Worry tilt
    @State private var headTilt: Double = 0

    private var mood: Mood {
        if usagePercent >= 0.9  { return .alarmed }
        if usagePercent >= 0.75 { return .worried }
        return .happy
    }

    enum Mood { case happy, worried, alarmed }

    var body: some View {
        ZStack {
            // ── Antenna ─────────────────────────────────────────────────────
            VStack(spacing: 0) {
                Circle()
                    .fill(moodColor)
                    .frame(width: size * 0.17, height: size * 0.17)
                    .shadow(
                        color: moodColor.opacity(antennaGlow ? 0.95 : 0.3),
                        radius: antennaGlow ? size * 0.22 : size * 0.07
                    )
                    .scaleEffect(antennaGlow ? 1.15 : 0.92)
                Rectangle()
                    .fill(Theme.textSecondary.opacity(0.7))
                    .frame(width: size * 0.04, height: size * 0.13)
            }
            .offset(x: antennaSway * size * 0.04, y: -size * 0.47)
            .rotationEffect(.degrees(antennaSway * 3.5))

            // ── Head ────────────────────────────────────────────────────────
            RoundedRectangle(cornerRadius: size * 0.19, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.20), Color.white.opacity(0.05)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .frame(width: size * 0.92, height: size * 0.80)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.19, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.22), Color.white.opacity(0.06)],
                                startPoint: .top, endPoint: .bottom
                            ),
                            lineWidth: 1.2
                        )
                )
                .rotationEffect(.degrees(headTilt))

            // ── Brow (worried/alarmed only) ──────────────────────────────────
            if mood != .happy {
                HStack(spacing: size * 0.14) {
                    browLine(flip: false)
                    browLine(flip: true)
                }
                .offset(y: -size * 0.19)
                .rotationEffect(.degrees(headTilt))
            }

            // ── Eyes ─────────────────────────────────────────────────────────
            HStack(spacing: size * 0.18) {
                eyeView()
                eyeView()
            }
            .offset(x: eyeShift * size * 0.06, y: -size * 0.04)
            .rotationEffect(.degrees(headTilt))

            // ── Mouth ────────────────────────────────────────────────────────
            mouthView
                .offset(y: size * 0.18)
                .rotationEffect(.degrees(headTilt))
        }
        .frame(width: size, height: size)
        .scaleEffect(appeared ? breatheScale : 0.4)
        .opacity(appeared ? 1 : 0)
        .onAppear { startAnimations() }
        .onChange(of: mood) { _ in updateMoodAnimations() }
    }

    // MARK: - Sub-views

    @ViewBuilder
    private func eyeView() -> some View {
        Capsule()
            .fill(moodColor)
            .frame(
                width:  size * (mood == .alarmed ? 0.15 : 0.12),
                height: blink ? size * 0.02 : size * (mood == .alarmed ? 0.20 : 0.16)
            )
            .shadow(color: moodColor.opacity(0.5), radius: size * 0.06)
    }

    @ViewBuilder
    private func browLine(flip: Bool) -> some View {
        Capsule()
            .fill(Theme.textSecondary.opacity(0.7))
            .frame(width: size * 0.13, height: size * 0.03)
            .rotationEffect(.degrees(flip ? 12 : -12))
    }

    @ViewBuilder
    private var mouthView: some View {
        switch mood {
        case .happy:
            // Slight smile arc
            Arc(startAngle: .degrees(10), endAngle: .degrees(170), clockwise: false)
                .stroke(Theme.accentCool, style: StrokeStyle(lineWidth: size * 0.05, lineCap: .round))
                .frame(width: size * 0.26, height: size * 0.10)
        case .worried:
            // Flat line
            Capsule()
                .fill(Theme.textSecondary.opacity(0.8))
                .frame(width: size * 0.22, height: size * 0.04)
        case .alarmed:
            // Open O mouth
            Circle()
                .stroke(Theme.statusCritical.opacity(0.9),
                        style: StrokeStyle(lineWidth: size * 0.05))
                .frame(width: size * 0.18, height: size * 0.14)
        }
    }

    // MARK: - Color helpers

    private var moodColor: Color {
        switch mood {
        case .happy:   return Theme.accentWarm
        case .worried: return Theme.statusWarning
        case .alarmed: return Theme.statusCritical
        }
    }

    // MARK: - Animation setup

    private func startAnimations() {
        // Entry spring bounce
        withAnimation(.spring(response: 0.5, dampingFraction: 0.55, blendDuration: 0)) {
            appeared = true
        }
        startBreathing()
        startAntennaAnimations()
        startBlinking()
        startEyeScan()
    }

    private func startBreathing() {
        let duration: Double = mood == .alarmed ? 0.7 : (mood == .worried ? 1.4 : 2.8)
        withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: true)) {
            breatheScale = mood == .alarmed ? 1.06 : 1.025
        }
    }

    private func startAntennaAnimations() {
        // Glow pulse
        let glowDuration: Double = mood == .alarmed ? 0.45 : (mood == .worried ? 0.9 : 1.6)
        withAnimation(.easeInOut(duration: glowDuration).repeatForever(autoreverses: true)) {
            antennaGlow.toggle()
        }
        // Sway
        let swayDuration: Double = mood == .alarmed ? 0.6 : 2.2
        withAnimation(.easeInOut(duration: swayDuration).repeatForever(autoreverses: true)) {
            antennaSway = mood == .alarmed ? 1.0 : 0.4
        }
        // Head tilt when worried/alarmed
        let tilt: Double = mood == .alarmed ? -4 : (mood == .worried ? -2 : 0)
        withAnimation(.easeInOut(duration: 0.6)) {
            headTilt = tilt
        }
    }

    private func startBlinking() {
        let interval: TimeInterval = mood == .alarmed ? 1.2 : (mood == .worried ? 2.2 : 3.5)
        func scheduleBlink() {
            DispatchQueue.main.asyncAfter(deadline: .now() + interval) {
                withAnimation(.easeInOut(duration: 0.09)) { blink = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.11) {
                    withAnimation(.easeInOut(duration: 0.09)) { blink = false }
                    // Double-blink when alarmed
                    if mood == .alarmed {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                            withAnimation(.easeInOut(duration: 0.09)) { blink = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.11) {
                                withAnimation(.easeInOut(duration: 0.09)) { blink = false }
                                scheduleBlink()
                            }
                        }
                    } else {
                        scheduleBlink()
                    }
                }
            }
        }
        scheduleBlink()
    }

    private func startEyeScan() {
        guard mood == .happy else { return }
        func scheduleGlance() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: 4...8)) {
                withAnimation(.easeInOut(duration: 0.3)) { eyeShift = Bool.random() ? 1 : -1 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    withAnimation(.easeInOut(duration: 0.3)) { eyeShift = 0 }
                    scheduleGlance()
                }
            }
        }
        scheduleGlance()
    }

    private func updateMoodAnimations() {
        // Re-trigger animations when mood changes
        breatheScale = 1.0
        antennaGlow  = false
        antennaSway  = 0
        startBreathing()
        startAntennaAnimations()
        startBlinking()
        if mood == .happy { startEyeScan() }
        else { withAnimation(.easeInOut(duration: 0.3)) { eyeShift = 0 } }
    }
}

// MARK: - Arc shape for smile

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
