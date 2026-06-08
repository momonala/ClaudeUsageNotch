import SwiftUI

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

/// Solid-black background for the expanded panel.
///
/// Top corners echo the notch's inner radius so the panel sits flush against
/// the hardware; bottom corners are fully rounded. Pure black blends seamlessly
/// with the physical notch housing.
struct NotchGlassBackground: View {
    var topRadius: CGFloat    = 12
    var bottomRadius: CGFloat = 20

    private var shape: NotchPillShape {
        NotchPillShape(topRadius: topRadius, bottomRadius: bottomRadius)
    }

    var body: some View {
        shape.fill(Color.black)
    }
}

