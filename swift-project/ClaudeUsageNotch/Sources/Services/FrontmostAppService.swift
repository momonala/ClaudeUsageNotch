import AppKit
import Combine

/// Tracks whether the frontmost app is one a Claude Code session plausibly runs
/// in — a terminal, an editor with one embedded, or the Claude desktop app.
///
/// Drives how much the compact pill shows: the full strip of bars in such an
/// app, the status ring alone anywhere else. Hovering expands the full panel
/// from either state.
final class FrontmostAppService {
    static let shared = FrontmostAppService()
    private init() {}

    let isWorkHostFrontmost = CurrentValueSubject<Bool, Never>(true)

    /// Matched as prefixes, so build variants come along for free — including
    /// ToDesktop-packaged apps like Cursor, which ship under per-build
    /// identifiers such as `com.todesktop.230313mzl4w4u92`.
    private static let workHostPrefixes = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "com.github.wez.wezterm",
        "io.alacritty",
        "net.kovidgoyal.kitty",
        "dev.warp.Warp",
        "co.zeit.hyper",
        "org.tabby",
        "com.microsoft.VSCode",
        "com.todesktop",
        "com.anthropic.claude",
    ]

    private var observation: NSKeyValueObservation?

    /// KVO rather than `didActivateApplicationNotification`: the notification
    /// only fires on a change, so a wrong launch-time reading (taken while
    /// `open` is briefly activating things) would stick until the next app
    /// switch. `.initial` delivers the current value through the same path.
    func start() {
        guard observation == nil else { return }
        observation = NSWorkspace.shared.observe(\.frontmostApplication, options: [.initial, .new]) {
            [weak self] workspace, _ in
            self?.update(to: workspace.frontmostApplication)
        }
    }

    func stop() {
        observation?.invalidate()
        observation = nil
    }

    static func isWorkHost(_ bundleIdentifier: String) -> Bool {
        workHostPrefixes.contains { bundleIdentifier.hasPrefix($0) }
    }

    private func update(to app: NSRunningApplication?) {
        guard let identifier = app?.bundleIdentifier else { return }
        // Our own panel can take focus (the settings pane has a text field),
        // which must not collapse the pill mid-edit.
        guard identifier != Bundle.main.bundleIdentifier else { return }

        let isHost = Self.isWorkHost(identifier)
        if isHost != isWorkHostFrontmost.value {
            isWorkHostFrontmost.send(isHost)
        }
    }
}
