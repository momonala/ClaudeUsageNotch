import SwiftUI

/// Animated ring along the notch's perimeter reflecting local Claude Code
/// session status. Shown only in `CompactView`'s idle (unhovered) state.
///
/// Each state animates differently, so the *kind* of motion carries meaning
/// and not just the color:
/// - `.working`    — a faint blue ring with a comet travelling along it.
/// - `.needsInput` — an amber ring breathing thicker and thinner in place.
/// - just completed — a flat, unanimated green ring.
///
/// `AgentStatusReading` guarantees a completion flash never coincides with a
/// live `working`/`needsInput` session, so the branches below can't conflict.
///
/// Every stroke is laid *outside* the pill's fill, not centred on its edge:
/// the fill is exactly the hardware cutout, so a centred stroke would spend
/// its inner half covering the outermost black. The panel carries `outset`
/// points of transparent margin on its sides and bottom to give the strokes
/// room; without it the window clips them away.
struct AgentStatusGlow: View {
    let status: AgentStatus
    let justCompleted: Bool

    @State private var beadPosition: CGFloat = 0
    @State private var breathe = false

    private static let ringLineWidth: CGFloat = 2.47
    private static let amberLineWidth: CGFloat = 1.76
    /// Same weight as the ring it travels: the comet is the ring at full
    /// opacity, not a thicker overlay, and traces exactly the same path.
    private static let beadLineWidth: CGFloat = ringLineWidth

    /// Share of the perimeter the comet covers.
    private static let beadLength: CGFloat = 0.2

    /// The comet tapers at both ends by stacking this many low-alpha segments,
    /// each shorter than the last and all sharing a midpoint, so accumulated
    /// alpha peaks through the middle. Equal slices with per-slice opacity
    /// render rough instead: neighbours must overlap or a hairline of
    /// background shows at the seam, and the overlap composites to a third
    /// alpha whose bands crawl along the ring as the comet travels.
    ///
    /// A gradient can't do this: SwiftUI won't gradient a stroke *along* a
    /// path, and an `AngularGradient` sweeps by angle from the centre, crossing
    /// a rounded rect's edges and corners at different speeds.
    private static let beadLayers: Int = 6
    private static let beadLayerAlpha: Double = 0.42

    private static let beadDuration: Double = 2.2
    private static let breatheDuration: Double = 1.6
    /// Peak weight of the breathing amber ring — it thickens outward from
    /// `amberLineWidth` and back. Kept within `outset` so the swell stays
    /// inside the panel's margin instead of being clipped flat at the top of
    /// every breath.
    private static let amberBreathWidth: CGFloat = 2.7
    /// Opacity at the bottom of the breath. The ring thins *and* fades on the
    /// way down, all the way to invisible, so each breath reads as the ring
    /// appearing and receding rather than as a band that merely got narrower.
    private static let amberTroughOpacity: Double = 0

    /// The resting ring is faint — it marks the track; the comet is what the
    /// eye is meant to follow.
    private static let ringOpacity: Double = 0.3

    /// Transparent margin the compact panel must carry on its sides and bottom
    /// for this view to draw into: the heaviest stroke any state can put on the
    /// perimeter, which is the amber ring at the top of its breath.
    static let outset: CGFloat = max(ringLineWidth, max(amberBreathWidth, beadLineWidth))

    var body: some View {
        Group {
            if justCompleted {
                ring(lineWidth: Self.ringLineWidth)
                    .fill(Theme.statusHealthy.opacity(0.9))
            } else if status == .working {
                ZStack {
                    ring(lineWidth: Self.ringLineWidth)
                        .fill(Theme.accentCool.opacity(Self.ringOpacity))
                    comet
                }
                .onAppear(perform: startComet)
            } else if status == .needsInput {
                // Breathes in weight, thickening outward from an inner edge
                // pinned to the fill — a `scaleEffect` breath would move the
                // whole ring and visibly float it off the black.
                ring(lineWidth: breathe ? Self.amberBreathWidth : Self.amberLineWidth)
                    .fill(Theme.statusWarning)
                    .opacity(breathe ? 1 : Self.amberTroughOpacity)
                    .onAppear(perform: startBreathing)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 2), value: justCompleted)
    }

    /// Started from *its own* branch's `onAppear`, not the view's: a
    /// `repeatForever` animation only applies to the views present in the
    /// transaction that started it, and statuses routinely change while the
    /// glow stays on screen. A branch inserted later would render frozen at
    /// its end state.
    ///
    /// The reset needs its own transaction, hence the hop through the main
    /// queue: assigning start and end in one pass leaves SwiftUI a single net
    /// change, and a no-op change (already at the end value from a previous
    /// run) gives the animation nothing to attach to.
    private func startComet() {
        beadPosition = 0
        DispatchQueue.main.async {
            withAnimation(.linear(duration: Self.beadDuration).repeatForever(autoreverses: false)) {
                beadPosition = 1
            }
        }
    }

    private func startBreathing() {
        breathe = false
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: Self.breatheDuration).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
    }

    private func ring(lineWidth: CGFloat) -> PerimeterRing {
        PerimeterRing(lineWidth: lineWidth, outset: Self.outset)
    }

    /// `beadPosition` sweeps 0→1 then jumps back to 0 each cycle. The path is
    /// closed, so 0 and 1 are the same point and the jump is invisible — each
    /// slice wraps the seam inside `CometSlice`.
    private var comet: some View {
        ZStack {
            ForEach(0..<Self.beadLayers, id: \.self) { layer in
                CometSlice(
                    phase: beadPosition,
                    layer: layer,
                    layers: Self.beadLayers,
                    baseLength: Self.beadLength,
                    lineWidth: Self.beadLineWidth,
                    outset: Self.outset
                )
                .fill(Theme.accentCool.opacity(Self.beadLayerAlpha))
            }
        }
    }
}

// MARK: - Perimeter geometry

/// The pill's outline pushed `lineWidth / 2` outward inside `rect`, which is
/// the whole panel — `outset` wider than the pill on each side and below it.
///
/// The corner radius grows by the same amount, keeping the ring's curve
/// parallel to the fill's rather than cutting across it. Nothing is offset at
/// the top: that edge sits behind the camera housing, with nothing to wrap.
private func perimeterPath(in rect: CGRect, lineWidth: CGFloat, outset: CGFloat) -> Path {
    let inset = outset - lineWidth / 2
    let ringRect = CGRect(
        x: rect.minX + inset,
        y: rect.minY,
        width: max(0, rect.width - inset * 2),
        height: max(0, rect.height - inset)
    )
    let radius = Theme.compactPillBottomRadius + lineWidth / 2
    return NotchPillShape(topRadius: 0, bottomRadius: radius).path(in: ringRect)
}

/// The full perimeter at an animatable weight, drawn as a filled band.
///
/// A plain `.stroke(lineWidth:)` can't animate — `lineWidth` belongs to the
/// stroke style, not the view's animatable data, so SwiftUI jumps straight to
/// the new weight. Regenerating the path through `animatableData` gives every
/// intermediate width a real path to fill, with its inner edge still pinned to
/// the fill so the band only ever grows outward.
private struct PerimeterRing: Shape {
    var lineWidth: CGFloat
    let outset: CGFloat

    var animatableData: CGFloat {
        get { lineWidth }
        set { lineWidth = newValue }
    }

    func path(in rect: CGRect) -> Path {
        perimeterPath(in: rect, lineWidth: lineWidth, outset: outset)
            .strokedPath(StrokeStyle(lineWidth: lineWidth))
    }
}

/// One lit layer of the comet: a stretch of perimeter centred on the comet's
/// midpoint, `layer` 0 running its full length and each later one shorter.
///
/// `phase` is the animatable input, so every layer's geometry derives from the
/// same instant on every frame. `Shape.trim(from:to:)` in the view layer would
/// animate each endpoint independently and pull the layers apart mid-travel.
private struct CometSlice: Shape {
    var phase: CGFloat
    let layer: Int
    let layers: Int
    let baseLength: CGFloat
    let lineWidth: CGFloat
    let outset: CGFloat

    var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let outline = perimeterPath(in: rect, lineWidth: lineWidth, outset: outset)
        let head = phase.truncatingRemainder(dividingBy: 1)
        let span = baseLength
        let length = span * CGFloat(layers - layer) / CGFloat(layers)
        // Every layer shares the comet's midpoint, so they nest instead of
        // butting against each other.
        let from = head - (span + length) / 2
        let start = from < 0 ? from + 1 : from
        let to = start + length
        var lit = outline.trimmedPath(from: start, to: min(to, 1))
        if to > 1 {
            lit.addPath(outline.trimmedPath(from: 0, to: to - 1))
        }
        return lit.strokedPath(StrokeStyle(lineWidth: lineWidth))
    }

}
