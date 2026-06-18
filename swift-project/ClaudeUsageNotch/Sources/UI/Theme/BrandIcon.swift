import SwiftUI
import AppKit

/// Loads the bundled Claude brand logo (`brand-claude.png`).
enum BrandIcon {
    private static var cachedImage: NSImage?

    static func image() -> NSImage? {
        if let cached = cachedImage { return cached }
        let url = Bundle.main.url(forResource: "brand-claude", withExtension: "png", subdirectory: "BrandIcons")
            ?? Bundle.main.url(forResource: "brand-claude", withExtension: "png")
        guard let url, let image = NSImage(contentsOf: url) else { return nil }
        cachedImage = image
        return image
    }
}

/// Claude's brand logo, falling back to an SF Symbol when the asset is missing.
struct ProviderIconView: View {
    var size: CGFloat = 16
    /// Tint applied only to the SF Symbol fallback; brand PNG renders as-is.
    var fallbackColor: Color? = nil
    /// VoiceOver label. Pass `nil` (default) to mark the icon as decorative.
    var accessibilityLabel: String? = nil

    var body: some View {
        Group {
            if let ns = BrandIcon.image() {
                Image(nsImage: ns)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: size, height: size)
            } else {
                let symbol = Image(systemName: "sparkle").font(.system(size: size * 0.9))
                if let c = fallbackColor { symbol.foregroundColor(c) } else { symbol }
            }
        }
        .accessibilityHidden(accessibilityLabel == nil)
        .accessibilityLabel(accessibilityLabel ?? "")
    }
}
