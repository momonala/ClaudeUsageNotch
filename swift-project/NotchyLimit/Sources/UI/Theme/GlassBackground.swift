import SwiftUI
import AppKit

// MARK: - NotchPillShape

/// Rounded rectangle whose top and bottom corner radii are independent.
///
/// Set `topRadius ≈ 8` to match the physical notch's inner corner so the
/// compact pill appears as a seamless downward extension of the hardware.
/// Set `bottomRadius ≈ 12–20` for the free, rounded bottom edge.
struct NotchPillShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let tr = min(topRadius,    min(rect.width, rect.height) / 2)
        let br = min(bottomRadius, min(rect.width, rect.height) / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + tr, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        p.addArc(center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr),
                 radius: tr, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        p.addArc(center: CGPoint(x: rect.maxX - br, y: rect.maxY - br),
                 radius: br, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX + br, y: rect.maxY))
        p.addArc(center: CGPoint(x: rect.minX + br, y: rect.maxY - br),
                 radius: br, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tr))
        p.addArc(center: CGPoint(x: rect.minX + tr, y: rect.minY + tr),
                 radius: tr, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        return p
    }
}

// MARK: - NotchGlassBackground

/// Glass background using `NotchPillShape` so the expanded panel's top corners
/// echo the notch's inner corner radius and sit flush against it.
///
/// `tintColor` bleeds the current status colour into the panel border and the
/// very faint wash behind the glass — giving visual cohesion without being loud.
struct NotchGlassBackground: View {
    var topRadius: CGFloat    = 12
    var bottomRadius: CGFloat = 20
    var tintColor: Color      = .clear

    private var shape: NotchPillShape {
        NotchPillShape(topRadius: topRadius, bottomRadius: bottomRadius)
    }

    var body: some View {
        ZStack {
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                .clipShape(shape)
            shape.fill(Color.black.opacity(0.65))
            // Subtle status colour wash
            shape.fill(tintColor.opacity(0.055))
            shape.fill(
                LinearGradient(
                    colors: [Color.white.opacity(0.08), Color.clear],
                    startPoint: .topLeading, endPoint: .center
                )
            )
            .blendMode(.plusLighter)
        }
        .overlay(
            shape.stroke(
                LinearGradient(
                    colors: [tintColor.opacity(0.35), Color.white.opacity(0.06)],
                    startPoint: .top, endPoint: .bottom
                ),
                lineWidth: 0.75
            )
        )
    }
}

// MARK: - GlassBackground (legacy — kept for any other call sites)

/// Reusable glass background — frosted blur + layered depth for a premium feel.
struct GlassBackground: View {
    var cornerRadius: CGFloat = 18

    var body: some View {
        ZStack {
            // Layer 1 — macOS frosted glass (NSVisualEffectView)
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

            // Layer 2 — dark tint so it reads well against any wallpaper
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.black.opacity(0.55))

            // Layer 3 — top-leading shine
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.09), Color.clear],
                        startPoint: .topLeading,
                        endPoint: .center
                    )
                )
                .blendMode(.plusLighter)

            // Layer 4 — 1px border
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.20), Color.white.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        }
    }
}

// MARK: - NSVisualEffectView bridge

struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blendingMode
        v.state = .active
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
