import SwiftUI

/// Animated ring along the notch's perimeter reflecting local Claude Code
/// session status. Shown only in `CompactView`'s idle (unhovered) state.
///
/// Each state gets a distinct, deliberately different animation so the
/// *kind* of motion carries meaning, not just the color:
/// - `.working`    — a steady blue ring with one thicker bright bead
///                   travelling around it at constant speed (something is
///                   actively happening).
/// - `.needsInput` — a solid, thin amber ring that breathes bigger/smaller
///                   in place (a calmer but insistent "look at me").
/// - just completed — a flat, unanimated green ring (done, nothing to watch).
///   `AgentStatusReading` already guarantees this never coincides with a live
///   `working`/`needsInput` session, so the branches below can't conflict.
///
/// Uses the same squared-top shape as `CompactView`'s content fill (top
/// radius 0) so the ring's sides run straight up flush with the physical
/// notch cutout rather than curving inward before reaching it — a rounded
/// top radius is only invisible on notches short enough for the curve to
/// stay inside the hidden top strip, which doesn't hold across all Mac
/// notch sizes (e.g. it becomes visible on larger MacBook Pro notches).
///
/// The bead travels via `trim(from:to:)` along this shape's actual path,
/// not an `AngularGradient` rotated by angle — an angle-from-center sweep
/// covers a rounded rect's straight edges and corners at different visual
/// speeds (they don't subtend equal angle for equal arc length), which
/// looks uneven. `trim` walks the path itself, so speed stays constant.
/// The breathing amber ring uses `scaleEffect` (bounded to shrink inward,
/// never grow outward) rather than an animated `lineWidth`, which doesn't
/// reliably interpolate through SwiftUI's stroke rendering.
struct AgentStatusGlow: View {
    let status: AgentStatus
    let justCompleted: Bool

    @State private var beadPosition: CGFloat = 0
    @State private var breathe = false

    private static let ringLineWidth: CGFloat = 1.9
    private static let amberLineWidth: CGFloat = 1.35
    private static let beadLineWidth: CGFloat = 3.75
    private static let beadLength: CGFloat = 0.12
    private static let beadDuration: Double = 2.2
    private static let breatheDuration: Double = 1.6
    private static let breatheScale: CGFloat = 1.06

    private var ringShape: NotchPillShape { NotchPillShape(topRadius: 0, bottomRadius: 14) }

    var body: some View {
        Group {
            if justCompleted {
                ringShape.stroke(Theme.statusHealthy.opacity(0.9), lineWidth: Self.ringLineWidth)
            } else if status == .working {
                ZStack {
                    ringShape.stroke(Theme.accentCool.opacity(0.5), lineWidth: Self.ringLineWidth)
                    bead
                }
            } else if status == .needsInput {
                // Rests at its true (1x) size and grows outward from there —
                // never shrinks inward, which would open a gap revealing the
                // black background as a visible outline around the ring.
                ringShape
                    .stroke(Theme.statusWarning, lineWidth: Self.amberLineWidth)
                    .scaleEffect(breathe ? Self.breatheScale : 1)
                    .opacity(breathe ? 1 : 0.75)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.linear(duration: Self.beadDuration).repeatForever(autoreverses: false)) {
                beadPosition = 1
            }
            withAnimation(.easeInOut(duration: Self.breatheDuration).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
        .animation(.easeOut(duration: 2), value: justCompleted)
    }

    /// `beadPosition` sweeps 0→1 then jumps back to 0 every cycle (how
    /// `repeatForever(autoreverses: false)` works on a single state change).
    /// The shape's path is closed, so 0 and 1 are the same point — trimming
    /// a second segment from the start whenever the primary one overflows
    /// past 1 makes that jump invisible instead of a visible pop.
    private var bead: some View {
        let end = beadPosition + Self.beadLength
        return ZStack {
            ringShape
                .trim(from: beadPosition, to: min(end, 1))
                .stroke(Theme.accentCool, style: StrokeStyle(lineWidth: Self.beadLineWidth, lineCap: .round))
            if end > 1 {
                ringShape
                    .trim(from: 0, to: end - 1)
                    .stroke(Theme.accentCool, style: StrokeStyle(lineWidth: Self.beadLineWidth, lineCap: .round))
            }
        }
    }
}
