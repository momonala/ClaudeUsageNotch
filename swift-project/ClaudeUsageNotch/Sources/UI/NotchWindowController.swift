import SwiftUI
import AppKit
import Combine

/// Owns the borderless, non-activating NSPanel that hosts the notch UI.
///
/// Hover strategy: Timer polling NSEvent.mouseLocation every 40 ms.
/// NSTrackingArea.mouseExited is unreliable on non-activating panels during
/// resize. NSEvent.addGlobalMonitorForEvents only fires for OTHER apps' events,
/// not our own panel's events. A polling timer is the only approach that works
/// reliably at any window level regardless of activation state.
@MainActor
final class NotchWindowController: NSObject {
    private let panel: NSPanel
    private let appState: AppState
    private let appSettings: AppSettings
    private var hostingController: NSHostingController<RootNotchView>?
    private var cancellables = Set<AnyCancellable>()
    private var hoverTimer: Timer?
    private var isCurrentlyHovering = false
    private var clickOutsideMonitor: Any?

    // MARK: - Layout constants

    private enum Layout {
        // Expanded panel width/height live in `ExpandedPanelGeometry`, shared
        // with `ExpandedPanelView` so the window and its card can't desync.
        /// Visible strip height below the hardware notch in compact mode.
        static let compactStripHeight: CGFloat = Theme.compactStripHeight
        /// Extra compact-strip height for the optional third (credit) bar.
        static let compactStripHeightCredit: CGFloat      = Theme.compactStripHeightCredit
        /// Minimum height delta above compact that indicates the panel is already expanded.
        static let expandedHeightThreshold: CGFloat = 80
        /// Grow applied to the *expanded* panel's frame when testing for hover.
        /// Forgiving on purpose: the pointer is already inside the card, and a
        /// hairline miss along its edge would collapse the panel mid-interaction.
        static let expandedHoverGrow: CGFloat = 4
        /// Trimmed from each side of the *compact* hover target. The pill is
        /// exactly as wide as the notch cutout, and the menu bar items
        /// immediately flanking it (clock, status icons) are a pointer's width
        /// away — reaching for one used to clip the pill's edge and expand.
        static let compactHoverInsetX: CGFloat = 20
        /// Trimmed from the bottom of the compact hover target on screens with
        /// no hardware cutout, where the visible strip is all there is to aim
        /// at. Unused on notched screens — see `compactHoverHitRect`.
        static let compactHoverInsetBottom: CGFloat = 5

        static let expandPhase1Duration: TimeInterval = 0.16
        static let expandPhase2Delay:    TimeInterval = 0.12
        static let expandPhase2Duration: TimeInterval = 0.30
        static let collapseDuration:     TimeInterval = 0.22
    }

    // Panel heights include safeAreaInsets.top (the hardware notch height —
    // 32 pt on a 14" M5; it varies by model, so it's always read per-screen).  The panel is anchored at screen.frame.maxY so
    // the top portion sits inside the notch (invisible — black blends with
    // hardware) and only the lower "visible extension" is seen by the user.
    // This is identical to how the iOS Dynamic Island works.
    /// Panel frame in compact mode: the pill (exactly the hardware cutout) plus
    /// `AgentStatusGlow.outset` of transparent margin on its sides and bottom.
    ///
    /// The margin is always there, whether or not the status ring is currently
    /// showing — it costs nothing (the panel is transparent and the pill is
    /// centred inside it), and reserving it up front keeps the window from
    /// resizing every time an agent starts or stops working.
    private var compactSize: NSSize {
        let creditExtra = appState.snapshot?.creditWindow != nil ? Layout.compactStripHeightCredit : 0
        // No readout, no strip: the pill shrinks to the cutout itself, so
        // nothing hangs below the notch when you're not in your terminal.
        let strip = appState.showsCompactContent ? Layout.compactStripHeight + creditExtra : 0
        return NSSize(
            width: ScreenUtils.compactPanelWidthBase + AgentStatusGlow.outset * 2,
            height: ScreenUtils.notchHeight + strip + AgentStatusGlow.outset
        )
    }
    private var expandedSize: NSSize {
        let mode = appState.expandedMode
        let hasCredit = appState.snapshot?.creditWindow != nil
        return NSSize(
            width: ExpandedPanelGeometry.width(for: mode),
            height: ScreenUtils.notchHeight
                + ExpandedPanelGeometry.windowContentHeight(for: mode, hasCredit: hasCredit)
        )
    }

    init(appState: AppState, appSettings: AppSettings) {
        self.appState = appState
        self.appSettings = appSettings
        self.panel = KeyablePanel(
            contentRect: NSRect(
                origin: .zero,
                size: NSSize(width: ScreenUtils.compactPanelWidthBase + AgentStatusGlow.outset * 2, height: 30)
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        // .popUpMenu (101) sits above the menu bar compositor (mainMenu = 24),
        // which is required to render inside the notch area on MacBook.
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.isOpaque         = false
        panel.backgroundColor  = .clear
        panel.hasShadow        = false  // SwiftUI views manage their own shadows
        panel.isMovable        = false
        panel.isMovableByWindowBackground = false
        panel.acceptsMouseMovedEvents = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        // The notch UI is a permanently dark surface (it has to blend with the
        // black camera housing), so pin the panel to the dark appearance rather
        // than inheriting the system's. Without this, the stock controls in the
        // settings pane — pop-up buttons, the text field, push buttons — render
        // their Light Mode variant on pure black whenever the user is in Light
        // Mode, and the semantic label colors resolve to near-black on
        // near-black.
        panel.appearance = NSAppearance(named: .darkAqua)

        appState.$notchState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.applyState(state) }
            .store(in: &cancellables)

        appState.$expandedMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                switch self.appState.notchState {
                case .expandedHover, .expandedPinned: self.applyState(self.appState.notchState)
                default: break
                }
            }
            .store(in: &cancellables)

        appState.$snapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateCompactLayoutIfNeeded() }
            .store(in: &cancellables)

        appState.$isWorkHostFrontmost
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateCompactLayoutIfNeeded() }
            .store(in: &cancellables)
    }

    /// Explicitly remove the notch panel from screen and stop all observers.
    /// Called when the display mode no longer includes the notch — relying on
    /// `deinit` alone is unreliable because AppKit can keep an on-screen window
    /// alive, leaving a ghost pill behind.
    func teardown() {
        hoverTimer?.invalidate()
        hoverTimer = nil
        if let m = clickOutsideMonitor {
            NSEvent.removeMonitor(m)
            clickOutsideMonitor = nil
        }
        cancellables.removeAll()
        panel.orderOut(nil)
        panel.contentView = nil
        hostingController = nil
    }

    func present() {
        let root = RootNotchView(appState: appState, appSettings: appSettings, controller: self)
        let hosting = NSHostingController(rootView: root)
        hosting.view.wantsLayer = true
        self.hostingController = hosting
        panel.contentView = hosting.view

        applyState(appState.notchState)
        panel.orderFrontRegardless()

        startHoverTimer()
        startClickOutsideMonitor()
    }

    // MARK: - Click-outside to dismiss

    private func startClickOutsideMonitor() {
        if let m = clickOutsideMonitor { NSEvent.removeMonitor(m) }
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                guard self.appState.notchState == .expandedPinned else { return }
                if !self.panel.frame.contains(NSEvent.mouseLocation) {
                    self.appState.notchState = .compactIdle
                }
            }
        }
    }

    // MARK: - Hover polling (Timer — the only reliable approach)

    private func startHoverTimer() {
        hoverTimer?.invalidate()
        let timer = Timer(timeInterval: 0.04, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollHover() }
        }
        RunLoop.main.add(timer, forMode: .common)
        hoverTimer = timer
    }

    /// Hover-to-expand target. Asymmetric by state: a deliberately tight
    /// region while compact (so the pill isn't tripped by passing traffic), a
    /// forgiving one while expanded (so the card doesn't collapse under the
    /// pointer). Both are keyed off `panel.frame`, which already tracks the
    /// current size.
    private var hoverHitRect: NSRect {
        let frame = panel.frame
        switch appState.notchState {
        case .compactIdle, .compactHover:
            return compactHoverHitRect(in: frame)
        default:
            return frame.insetBy(dx: -Layout.expandedHoverGrow, dy: -Layout.expandedHoverGrow)
        }
    }

    /// Collapsed hover target: the hardware cutout itself, and nothing below it.
    ///
    /// The panel's lower portion — the visible strip carrying the bars — hangs
    /// below the menu bar over ordinary window content, so treating it as a
    /// hover target expanded the panel whenever the pointer merely travelled up
    /// to a window's title bar. Aiming at the cutout is unambiguous: nothing
    /// else lives there, and the pointer has to leave the whole (much larger)
    /// expanded frame to collapse again, so the two regions can't oscillate.
    ///
    /// Screens with no cutout have nothing to aim at, so they keep the strip as
    /// the target, trimmed at the bottom.
    private func compactHoverHitRect(in frame: NSRect) -> NSRect {
        // Insets run from the pill's edges, not the panel's: the panel is wider
        // by the status ring's margin on each side, and counting that as hover
        // target would quietly loosen the tight aim this state depends on.
        let insetX = Layout.compactHoverInsetX + AgentStatusGlow.outset
        let x = frame.minX + insetX
        let width = max(0, frame.width - insetX * 2)
        let notchHeight = min(ScreenUtils.notchHeight, frame.height)
        guard notchHeight > 0 else {
            let insetBottom = Layout.compactHoverInsetBottom + AgentStatusGlow.outset
            return NSRect(x: x,
                          y: frame.minY + insetBottom,
                          width: width,
                          height: frame.height - insetBottom)
        }
        return NSRect(x: x, y: frame.maxY - notchHeight, width: width, height: notchHeight)
    }

    private func pollHover() {
        let hovering = hoverHitRect.contains(NSEvent.mouseLocation)
        guard hovering != isCurrentlyHovering else { return }
        isCurrentlyHovering = hovering
        if hovering { userHoveredIn()  }
        else        { userHoveredOut() }
    }

    // MARK: - State transitions

    func userHoveredIn() {
        // Expand immediately on hover-in; the compactHover state is transient
        // (it renders identically to compactIdle) before the expand animation.
        if appState.notchState == .compactIdle {
            appState.notchState = .expandedHover
        }
    }

    func userHoveredOut() {
        guard appState.notchState != .expandedPinned else { return }
        appState.notchState = .compactIdle
    }

    func userClicked() {
        switch appState.notchState {
        case .expandedPinned: appState.notchState = .compactIdle
        default:              appState.notchState = .expandedPinned
        }
    }

    func userPressedEscape() {
        appState.notchState = .compactIdle
    }

    // MARK: - Layout

    /// Animate compact width when countdown text needs more room beside the notch.
    private func updateCompactLayoutIfNeeded() {
        switch appState.notchState {
        case .compactIdle, .compactHover:
            let target = compactSize
            // Both dimensions: compact width is fixed at the cutout now, so a
            // width-only test would never fire — and every compact resize left
            // is a height change (the credit row appearing, the readout being
            // gated on which app is frontmost).
            guard abs(panel.frame.width - target.width) > 0.5
                || abs(panel.frame.height - target.height) > 0.5 else { return }
            let origin = ScreenUtils.topCenteredOrigin(forPanelSize: target)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(NSRect(origin: origin, size: target), display: true)
            }
        default:
            break
        }
    }

    private func applyState(_ state: NotchState) {
        let targetSize: NSSize
        switch state {
        case .hidden:                         targetSize = NSSize(width: 1, height: 1)
        case .compactIdle, .compactHover:     targetSize = compactSize
        case .expandedHover, .expandedPinned: targetSize = expandedSize
        }

        let isExpanding = (state == .expandedHover || state == .expandedPinned)
                       && panel.frame.height < (ScreenUtils.notchHeight + Layout.expandedHeightThreshold)

        if isExpanding {
            // Phase 1: stretch width first (pill → wide strip)
            let midSize   = NSSize(width: expandedSize.width, height: compactSize.height)
            let midOrigin = ScreenUtils.topCenteredOrigin(forPanelSize: midSize)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = Layout.expandPhase1Duration
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(NSRect(origin: midOrigin, size: midSize), display: true)
            }
            // Phase 2: drop height after stretch settles
            let finalOrigin = ScreenUtils.topCenteredOrigin(forPanelSize: targetSize)
            DispatchQueue.main.asyncAfter(deadline: .now() + Layout.expandPhase2Delay) { [weak self] in
                guard let self else { return }
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = Layout.expandPhase2Duration
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    self.panel.animator().setFrame(NSRect(origin: finalOrigin, size: targetSize), display: true)
                }
            }
        } else {
            let origin = ScreenUtils.topCenteredOrigin(forPanelSize: targetSize)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = Layout.collapseDuration
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(NSRect(origin: origin, size: targetSize), display: true)
            }
        }
    }
}

// MARK: - Keyable panel

/// A borderless panel returns `canBecomeKey == false` by default, which blocks
/// text-field editing (e.g. the sync-server URL in settings). Overriding it lets
/// the panel take key focus when a control needs it. Paired with
/// `becomesKeyOnlyIfNeeded = true` and `.nonactivatingPanel`, the panel only
/// becomes key on click-into-field and never foregrounds the app.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }

    /// This is an accessory app with no menu bar, so the standard Edit-menu key
    /// equivalents (⌘A/C/V/X/Z) never get dispatched to the focused field editor.
    /// Translate them here and send the matching action down the responder chain.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command else {
            return super.performKeyEquivalent(with: event)
        }
        let action: Selector?
        switch event.charactersIgnoringModifiers {
        case "a": action = #selector(NSText.selectAll(_:))
        case "c": action = #selector(NSText.copy(_:))
        case "v": action = #selector(NSText.paste(_:))
        case "x": action = #selector(NSText.cut(_:))
        case "z": action = Selector(("undo:"))
        default:  action = nil
        }
        if let action, NSApp.sendAction(action, to: nil, from: self) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

// MARK: - Root SwiftUI view

struct RootNotchView: View {
    @ObservedObject var appState: AppState
    let appSettings: AppSettings
    let controller: NotchWindowController

    var body: some View {
        Group {
            switch appState.notchState {
            case .hidden:
                Color.clear
            case .compactIdle, .compactHover:
                Group {
                    if appState.isNotchUIHidden {
                        Color.clear
                    } else {
                        CompactView(appState: appState, appSettings: appSettings)
                    }
                }
                .onTapGesture { controller.userClicked() }
                .contextMenu {
                    Button {
                        appState.expandedMode = .settings
                        appState.notchState = .expandedPinned
                    } label: {
                        Label("Settings", systemImage: "gearshape.fill")
                    }
                    Button { NotificationService.shared.sendTest() } label: {
                        Label("Send test notification", systemImage: "bell.fill")
                    }
                    Divider()
                    Button(role: .destructive) {
                        NSApplication.shared.terminate(nil)
                    } label: {
                        Label("Quit ClaudeUsageNotch", systemImage: "power")
                    }
                }
            case .expandedHover, .expandedPinned:
                ExpandedPanelView(appState: appState, appSettings: appSettings, controller: controller)
                    .transition(.asymmetric(
                        insertion: .identity,
                        removal: .opacity.combined(with: .scale(scale: 0.92, anchor: .top))
                    ))
            }
        }
        .animation(.spring(response: 0.22, dampingFraction: 0.78), value: appState.notchState)
    }
}
