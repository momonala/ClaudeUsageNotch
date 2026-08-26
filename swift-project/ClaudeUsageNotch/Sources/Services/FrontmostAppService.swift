import AppKit
import Combine

/// Tracks whether the app the user is currently in is one a Claude Code
/// session plausibly runs in — a terminal, an editor with one embedded, or the
/// Claude desktop app.
///
/// This drives how much the compact pill shows. In that app you get the full
/// strip of bars and percentages; anywhere else the pill keeps only its status
/// ring, so the notch reads as stock hardware the moment you switch away and
/// the numbers are there exactly where you'd act on them. Hovering still
/// expands the full panel from either state.
///
/// Needs no permissions: frontmost-application changes are public
/// `NSWorkspace` notifications, unlike anything that reads window contents.
final class FrontmostAppService {
    static let shared = FrontmostAppService()
    private init() {}

    let isWorkHostFrontmost = CurrentValueSubject<Bool, Never>(true)

    /// Matched as prefixes, so build variants come along for free — VS Code's
    /// Insiders build, iTerm2's beta, and Cursor and its ToDesktop-packaged
    /// relatives, which ship under per-build identifiers like
    /// `com.todesktop.230313mzl4w4u92`.
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

    /// Observes `frontmostApplication` by KVO rather than listening for
    /// `didActivateApplicationNotification`.
    ///
    /// The notification only fires on a *change*, so a wrong first reading
    /// sticks until the user next switches apps — and the first reading is
    /// taken during launch, exactly when `open` is briefly activating things.
    /// In practice that left the pill collapsed for several seconds with the
    /// terminal plainly in front. KVO's `.initial` delivers the current value
    /// and every later one through the same path, so a bad launch-time reading
    /// is corrected the moment it settles.
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

    /// Whether a bundle identifier counts as a host for a Claude Code session.
    static func isWorkHost(_ bundleIdentifier: String) -> Bool {
        workHostPrefixes.contains { bundleIdentifier.hasPrefix($0) }
    }

    private func update(to app: NSRunningApplication?) {
        guard let identifier = app?.bundleIdentifier else { return }
        // Our own panel can take focus — the settings pane has a text field —
        // and that is not the user leaving their terminal, so it must not
        // collapse the pill out from under them mid-edit.
        guard identifier != Bundle.main.bundleIdentifier else { return }

        let isHost = Self.isWorkHost(identifier)
        if isHost != isWorkHostFrontmost.value {
            isWorkHostFrontmost.send(isHost)
        }
    }
}
