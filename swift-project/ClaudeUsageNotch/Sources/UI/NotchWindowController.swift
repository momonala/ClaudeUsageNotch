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
    private let refreshAction: () -> Void
    private var hostingController: NSHostingController<RootNotchView>?
    private var cancellables = Set<AnyCancellable>()
    private var hoverTimer: Timer?
    private var isCurrentlyHovering = false
    private var clickOutsideMonitor: Any?

    // MARK: - Layout constants

    private enum Layout {
        static let expandedWidth: CGFloat      = 380
        static let expandedWidthChart: CGFloat = 1090
        /// Visible strip height below the hardware notch in compact mode.
        static let compactStripHeight: CGFloat = Theme.compactStripHeight
        static let expandedContentHeight: CGFloat         = 184
        static let expandedContentHeightChart: CGFloat    = 618
        static let expandedContentHeightSettings: CGFloat = 258
        static let hoverHitInset: CGFloat    = -4

        static let expandPhase1Duration: TimeInterval = 0.16
        static let expandPhase2Delay:    TimeInterval = 0.12
        static let expandPhase2Duration: TimeInterval = 0.30
        static let collapseDuration:     TimeInterval = 0.22
    }

    // Panel heights include safeAreaInsets.top (the hardware notch height,
    // ~37 pt on MBP 14/16").  The panel is anchored at screen.frame.maxY so
    // the top portion sits inside the notch (invisible — black blends with
    // hardware) and only the lower "visible extension" is seen by the user.
    // This is identical to how the iOS Dynamic Island works.
    private var compactSize: NSSize {
        NSSize(
            width: ScreenUtils.compactPanelWidth(
                atSessionLimit: appState.isAtSessionLimit,
                countdownText: appState.sessionResetShortString
            ),
            height: ScreenUtils.notchHeight + Layout.compactStripHeight
        )
    }
    private var expandedSize: NSSize {
        switch appState.expandedMode {
        case .usage:
            return NSSize(width: Layout.expandedWidth,
                          height: ScreenUtils.notchHeight + Layout.expandedContentHeight)
        case .analytics:
            return NSSize(width: Layout.expandedWidthChart,
                          height: ScreenUtils.notchHeight + Layout.expandedContentHeightChart)
        case .settings:
            return NSSize(width: Layout.expandedWidth,
                          height: ScreenUtils.notchHeight + Layout.expandedContentHeightSettings)
        }
    }

    init(appState: AppState, appSettings: AppSettings, refreshAction: @escaping () -> Void) {
        self.appState = appState
        self.appSettings = appSettings
        self.refreshAction = refreshAction
        self.panel = KeyablePanel(
            contentRect: NSRect(origin: .zero, size: NSSize(width: ScreenUtils.compactPanelWidthDefault, height: 30)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        // .popUpMenu (101) sits above the menu bar compositor (mainMenu = 24),
        // which is required to render inside the notch area on MacBook.
        panel.level = NSWindow.Level(rawValue: Int(NSWindow.Level.popUpMenu.rawValue))
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.isOpaque         = false
        panel.backgroundColor  = .clear
        panel.hasShadow        = false  // SwiftUI views manage their own shadows
        panel.isMovable        = false
        panel.isMovableByWindowBackground = false
        panel.acceptsMouseMovedEvents = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true

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
        let root = RootNotchView(appState: appState, appSettings: appSettings, controller: self, refreshAction: refreshAction)
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

    private func pollHover() {
        let hitRect = panel.frame.insetBy(dx: Layout.hoverHitInset, dy: Layout.hoverHitInset)
        let hovering = hitRect.contains(NSEvent.mouseLocation)
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
            guard abs(panel.frame.width - target.width) > 0.5 else { return }
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
                       && panel.frame.height < (ScreenUtils.notchHeight + 80)

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
}

// MARK: - Root SwiftUI view

struct RootNotchView: View {
    @ObservedObject var appState: AppState
    let appSettings: AppSettings
    let controller: NotchWindowController
    let refreshAction: () -> Void

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
                        CompactView(appState: appState)
                    }
                }
                .onTapGesture { controller.userClicked() }
                .contextMenu {
                    Button { refreshAction() } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
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
                ExpandedPanelView(appState: appState, appSettings: appSettings, controller: controller, refreshAction: refreshAction)
                    .transition(.asymmetric(
                        insertion: .identity,
                        removal: .opacity.combined(with: .scale(scale: 0.92, anchor: .top))
                    ))
            }
        }
        .animation(.spring(response: 0.22, dampingFraction: 0.78), value: appState.notchState)
    }
}
