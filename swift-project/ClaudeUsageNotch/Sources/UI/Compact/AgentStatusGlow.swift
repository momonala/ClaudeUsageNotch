import SwiftUI

/// Animated ring along the notch's perimeter reflecting local Claude Code
/// session status.
///
/// Strokes lie *outside* the pill's fill, not centred on its edge: the fill is
/// exactly the hardware cutout, so a centred stroke would cover the outermost
/// black. The panel must carry `outset` points of transparent margin on its
/// sides and bottom or the window clips the strokes away.
struct AgentStatusGlow: View {
    let status: AgentStatus
    let justCompleted: Bool

    @State private var beadPosition: CGFloat = 0
    @State private var breathe = false

    private static let ringLineWidth: CGFloat = 2.47
    private static let amberLineWidth: CGFloat = 1.76
    private static let beadLineWidth: CGFloat = ringLineWidth

    /// Share of the perimeter the comet covers.
    private static let beadLength: CGFloat = 0.2

    /// The comet tapers by stacking low-alpha slices around a shared midpoint.
    /// A gradient can't do this: SwiftUI won't gradient a stroke *along* a path,
    /// and an `AngularGradient` crosses edges and corners at different speeds.
    private static let beadLayers: Int = 6
    private static let beadLayerAlpha: Double = 0.42

    private static let beadDuration: Double = 2.2
    private static let breatheDuration: Double = 1.6
    /// Kept within `outset` or the swell clips flat at the top of every breath.
    private static let amberBreathWidth: CGFloat = 2.7
    private static let amberTroughOpacity: Double = 0

    private static let ringOpacity: Double = 0.3

    /// Transparent margin the compact panel must carry: the heaviest stroke any
    /// state can put on the perimeter.
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
                // Weight, not scale: a `scaleEffect` breath would float the ring
                // off the black.
                ring(lineWidth: breathe ? Self.amberBreathWidth : Self.amberLineWidth)
                    .fill(Theme.statusWarning)
                    .opacity(breathe ? 1 : Self.amberTroughOpacity)
                    .onAppear(perform: startBreathing)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 2), value: justCompleted)
    }

    /// A `repeatForever` animation only applies to views present in the
    /// transaction that started it, hence the per-branch `onAppear`; the reset
    /// needs its own transaction or SwiftUI sees a single net change.
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

    /// `beadPosition` sweeps 0→1 then jumps back. The path is closed, so the
    /// jump is invisible; each slice wraps the seam inside `CometSlice`.
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

/// The pill's outline pushed `lineWidth / 2` outward inside `rect`, corner radius
/// growing to match so the curve stays parallel to the fill's. The top edge sits
/// behind the camera housing and is not offset.
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
/// `.stroke(lineWidth:)` jumps between weights — `lineWidth` isn't animatable
/// data — so each intermediate width gets a real path to fill instead.
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
/// `phase` is animated rather than the trim endpoints, which SwiftUI would
/// animate independently and pull the layers apart mid-travel.
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
        // Layers share a midpoint so they nest rather than butt together.
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
