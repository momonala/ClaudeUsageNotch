import SwiftUI

/// Animated ring along the notch's perimeter reflecting local Claude Code
/// session status. Shown only in `CompactView`'s idle (unhovered) state.
///
/// Each state gets a distinct, deliberately different animation so the
/// *kind* of motion carries meaning, not just the color:
/// - `.working`    — a faint blue ring with a comet travelling along it at
///                   constant speed (something is actively happening). The
///                   comet is the same weight as the ring, solid through its
///                   middle and fading out at head and tail, so it reads as a
///                   stretch of the ring lighting up rather than as a separate
///                   object riding on top of it.
/// - `.needsInput` — a solid amber ring that breathes thicker and thinner in
///                   place (a calmer but insistent "look at me").
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
/// Every stroke is laid *outside* that fill, not centred on its edge. The
/// fill is exactly the hardware cutout, so a centred stroke spent its inner
/// half covering the outermost points of black — pill plus ring measured one
/// cutout wide, and the black alone read narrower than the housing. Each
/// stroke now sits `lineWidth / 2` further out, putting its inner edge flush
/// against the fill and adding its full weight to the silhouette. The panel
/// carries `outset` points of transparent margin on its sides and bottom to
/// give them room; without it the window would clip them away.
///
/// Both animations run through a shape's `animatableData` rather than through
/// view modifiers, because both need geometry recomputed on every frame:
/// SwiftUI interpolates a view's animatable values, so a comet sliced into
/// separately-trimmed views has each slice's endpoints interpolating
/// independently — the slices drift apart and the comet renders as a row of
/// dashes. Driving one `phase` through `animatableData` keeps every slice's
/// geometry derived from the same instant.
struct AgentStatusGlow: View {
    let status: AgentStatus
    let justCompleted: Bool

    @State private var beadPosition: CGFloat = 0
    @State private var breathe = false

    private static let ringLineWidth: CGFloat = 2.47
    private static let amberLineWidth: CGFloat = 1.76
    /// Same weight as the ring it travels: the comet is the ring at full
    /// opacity, not a thicker overlay. Being identical widths, it also traces
    /// exactly the same path, so it can't sit a hair inside or outside.
    private static let beadLineWidth: CGFloat = ringLineWidth

    /// Share of the perimeter the comet covers.
    private static let beadLength: CGFloat = 0.2

    /// The comet fades in and out along its length by stacking this many
    /// segments, each shorter than the last and all sharing a midpoint, at a
    /// low alpha. Alpha accumulates where they overlap, so the comet is solid
    /// through the middle and tapers at both ends.
    ///
    /// The obvious alternative — cut the comet into equal slices and give each
    /// its own opacity — renders visibly rough. Neighbouring slices have to
    /// overlap or a hairline of background shows through the seam, and an
    /// overlap composites to a third alpha that matches neither slice; those
    /// bands then crawl along the ring as the comet travels. Nested segments
    /// have no seams to begin with, and cost half the draws.
    ///
    /// (A gradient is not an option here: SwiftUI can't gradient a stroke
    /// *along* a path, and an `AngularGradient` sweeps by angle from the
    /// centre, crossing a rounded rect's straight edges and corners at
    /// different speeds — the same reason the comet travels by trimming the
    /// path rather than by rotation.)
    private static let beadLayers: Int = 6
    private static let beadLayerAlpha: Double = 0.42

    // The comet's length is constant along the whole perimeter, and that is
    // what produces the compress-through-the-turns, stretch-on-the-straights
    // look: the same length of path spans far less visual width once it wraps
    // a 15 pt corner radius. Modulating the length by proximity to a corner
    // was tried and reverted — with the head at constant speed, any change in
    // length has to be absorbed by the tail, so the tail lurches forward and
    // falls back twice a lap. The effect is free; forcing it costs smoothness.

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
                // pinned to the fill. It used to breathe by `scaleEffect`,
                // which moved the whole ring outward — fine when the ring was
                // centred on the panel's edge and the growth was clipped away,
                // but now that the ring hugs the black it would visibly float
                // off it.
                ring(lineWidth: breathe ? Self.amberBreathWidth : Self.amberLineWidth)
                    .fill(Theme.statusWarning)
                    .opacity(breathe ? 1 : Self.amberTroughOpacity)
                    .onAppear(perform: startBreathing)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 2), value: justCompleted)
    }

    /// Each animation starts when *its own* branch appears, not when the view
    /// does.
    ///
    /// A `repeatForever` animation applies to the views present in the
    /// transaction that started it. Starting both from the view's `onAppear`
    /// therefore only animated whichever branch happened to be showing at that
    /// instant — a status change afterwards inserted the other branch with no
    /// animation attached, and it rendered frozen at its end state: a comet
    /// parked at the top-left corner, or an amber ring stuck at the top of a
    /// breath it never took. Statuses routinely change while the glow stays on
    /// screen (a session goes from working to needing input, or a completion
    /// flash gives way to a live session), so that was the common case, not
    /// the corner one.
    ///
    /// The reset has to land in its own transaction, hence the hop through the
    /// main queue: assigning the start and end values in one pass leaves
    /// SwiftUI with a single net change, and if that change is a no-op (the
    /// state is already at its end value from a previous run) there is nothing
    /// for the animation to attach to.
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

    /// `beadPosition` sweeps 0→1 then jumps back to 0 every cycle (how
    /// `repeatForever(autoreverses: false)` works on a single state change).
    /// The path is closed, so 0 and 1 are the same point and the jump is
    /// invisible — each slice wraps around the seam inside `CometSlice`.
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
/// The corner radius grows by the same amount the outline moved, keeping the
/// ring's curve parallel to the fill's rather than cutting across it. Nothing
/// is offset at the top: that edge is off-screen behind the camera housing, so
/// there is nothing there to wrap around.
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
/// A plain `.stroke(lineWidth:)` can't animate: `lineWidth` belongs to the
/// stroke style, not to the view's animatable data, so SwiftUI jumps straight
/// to the new weight. Regenerating the path through `animatableData` gives
/// every intermediate width a real path to fill. The inner edge stays pinned to
/// the fill at every weight — the band grows outward into the panel's margin,
/// never inward across the black.
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
/// `phase` is the animatable input, so every layer's geometry is derived from
/// the same instant on every frame. Trimming in the view layer instead —
/// `Shape.trim(from:to:)` — animates each endpoint independently between its
/// own start and end values, which pulls the layers apart as they travel.
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
