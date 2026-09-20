import SwiftUI
import AppKit
import Combine

/// Owns the borderless, non-activating NSPanel that hosts the notch UI.
///
/// Hover is polled rather than tracked: `NSTrackingArea.mouseExited` is
/// unreliable on non-activating panels during resize, and global event monitors
/// only see *other* apps' events.
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

    private enum Layout {
        static let expandedHeightThreshold: CGFloat = 80
        /// Slack around the expanded frame, so a hairline miss along the card's
        /// edge doesn't collapse the panel.
        static let expandedHoverGrow: CGFloat = 4
        /// Trimmed from each side of the compact hover target: the flanking menu
        /// bar items are a pointer's width away.
        static let compactHoverInsetX: CGFloat = 20
        static let compactHoverInsetBottom: CGFloat = 5

        static let expandPhase1Duration: TimeInterval = 0.16
        static let expandPhase2Delay:    TimeInterval = 0.12
        static let expandPhase2Duration: TimeInterval = 0.30
        static let collapseDuration:     TimeInterval = 0.22
    }

    // Every panel height includes `ScreenUtils.notchHeight`: the panel is anchored
    // at the screen's top edge, so that much of it hides inside the hardware cutout.

    /// The pill plus `AgentStatusGlow.outset` of margin, always reserved so the
    /// window doesn't resize whenever an agent starts or stops working.
    private var compactSize: NSSize {
        let extraRows = appState.snapshot?.extraWindowCount ?? 0
        let strip = appState.showsCompactContent ? Theme.compactStripHeight(extraRows: extraRows) : 0
        return NSSize(
            width: ScreenUtils.compactPanelWidthBase + AgentStatusGlow.outset * 2,
            height: ScreenUtils.notchHeight + strip + AgentStatusGlow.outset
        )
    }
    private var expandedSize: NSSize {
        let mode = appState.expandedMode
        return NSSize(
            width: ExpandedPanelGeometry.width(for: mode),
            height: ScreenUtils.notchHeight
                + ExpandedPanelGeometry.windowContentHeight(for: mode, snapshot: appState.snapshot)
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

        // .popUpMenu (101) outranks the menu bar compositor (mainMenu = 24), which
        // is required to render inside the notch area.
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
        // The notch UI is permanently dark; unpinned, Light Mode would draw
        // near-black stock labels on pure black.
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

        let compactSizeInputs = Publishers.MergeMany(
            appState.$snapshot.map { _ in () }.eraseToAnyPublisher(),
            appState.$isWorkHostFrontmost.map { _ in () }.eraseToAnyPublisher(),
            appState.$isNotchUIHidden.map { _ in () }.eraseToAnyPublisher()
        )
        compactSizeInputs
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.updateCompactLayoutIfNeeded() }
            .store(in: &cancellables)
    }

    /// `deinit` alone is unreliable — AppKit can keep an on-screen window alive,
    /// leaving a ghost pill behind.
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

    // MARK: - Hover polling

    private func startHoverTimer() {
        hoverTimer?.invalidate()
        let timer = Timer(timeInterval: 0.04, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollHover() }
        }
        RunLoop.main.add(timer, forMode: .common)
        hoverTimer = timer
    }

    /// Tight while compact so passing traffic doesn't trip the pill, forgiving
    /// while expanded so the card doesn't collapse under the pointer.
    private var hoverHitRect: NSRect {
        let frame = panel.frame
        switch appState.notchState {
        case .compactIdle, .compactHover:
            return compactHoverHitRect(in: frame)
        default:
            return frame.insetBy(dx: -Layout.expandedHoverGrow, dy: -Layout.expandedHoverGrow)
        }
    }

    /// The hardware cutout itself, and nothing below it: the strip hangs over
    /// ordinary window content, so treating it as a target would expand the panel
    /// whenever the pointer travels up to a title bar. Cutout-less screens use
    /// the strip instead.
    private func compactHoverHitRect(in frame: NSRect) -> NSRect {
        // Insets run from the pill's edges, not the panel's, which is wider by the
        // status ring's margin.
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

    private func updateCompactLayoutIfNeeded() {
        switch appState.notchState {
        case .compactIdle, .compactHover:
            let target = compactSize
            guard abs(panel.frame.width - target.width) > 0.5
                || abs(panel.frame.height - target.height) > 0.5 else { return }
            animate(to: target, duration: 0.25, timing: .easeInEaseOut)
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

        guard isExpanding else {
            animate(to: targetSize, duration: Layout.collapseDuration, timing: .easeInEaseOut)
            return
        }

        // Stretch width first (pill → wide strip), then drop the height.
        let midSize = NSSize(width: expandedSize.width, height: compactSize.height)
        animate(to: midSize, duration: Layout.expandPhase1Duration, timing: .easeOut)
        DispatchQueue.main.asyncAfter(deadline: .now() + Layout.expandPhase2Delay) { [weak self] in
            self?.animate(to: targetSize, duration: Layout.expandPhase2Duration, timing: .easeInEaseOut)
        }
    }

    private func animate(to size: NSSize, duration: TimeInterval, timing: CAMediaTimingFunctionName) {
        let origin = ScreenUtils.topCenteredOrigin(forPanelSize: size)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: timing)
            panel.animator().setFrame(NSRect(origin: origin, size: size), display: true)
        }
    }
}

// MARK: - Keyable panel

/// A borderless panel returns `canBecomeKey == false`, which blocks text-field
/// editing. With `becomesKeyOnlyIfNeeded` and `.nonactivatingPanel`, overriding it
/// makes the panel key on click-into-field only, never foregrounding the app.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }

    /// An accessory app has no menu bar, so Edit-menu key equivalents never reach
    /// the focused field editor. Dispatch them down the responder chain.
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
                CompactView(appState: appState, appSettings: appSettings)
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
