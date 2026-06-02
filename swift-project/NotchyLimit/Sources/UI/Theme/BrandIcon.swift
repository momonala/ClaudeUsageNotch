import SwiftUI
import AppKit

/// Loads the bundled brand logo (`brand-<id>.png`) for a provider.
///
/// Logos are sourced from the open-source lobehub icon set, rasterized to
/// transparent PNGs at build time. Colored marks (Claude, Gemini, Perplexity,
/// DeepSeek) keep their brand colors; monochrome marks (OpenAI, Codex,
/// ElevenLabs, OpenRouter) are baked white so they read on Notchy's dark UI.
enum BrandIcon {
    private static var cache: [ProviderId: NSImage] = [:]

    static func image(for id: ProviderId) -> NSImage? {
        if let cached = cache[id] { return cached }
        guard let url = Bundle.main.url(forResource: "brand-\(id.rawValue)", withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        cache[id] = image
        return image
    }
}

/// A provider's logo, falling back to its SF Symbol when the brand asset is
/// missing (e.g. an old build without bundled logos). Drop-in replacement for
/// `Image(systemName: id.iconSymbol)`.
struct ProviderIconView: View {
    let id: ProviderId
    var size: CGFloat = 16
    /// Tint applied only to the SF Symbol fallback; brand PNGs render as-is.
    var fallbackColor: Color? = nil

    var body: some View {
        if let ns = BrandIcon.image(for: id) {
            Image(nsImage: ns)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            let symbol = Image(systemName: id.iconSymbol).font(.system(size: size * 0.9))
            if let c = fallbackColor { symbol.foregroundColor(c) } else { symbol }
        }
    }
}
