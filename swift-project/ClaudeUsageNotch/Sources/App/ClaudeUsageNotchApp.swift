import SwiftUI
import AppKit

@main
struct ClaudeUsageNotchApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // Accessory: no Dock icon, no menu bar; we render into a custom NSPanel.
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
