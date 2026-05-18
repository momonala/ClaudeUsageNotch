import SwiftUI
import AppKit
import Combine

/// Owns the borderless, non-activating NSPanel that hosts the notch UI.
/// Manages hover/click → expand/pin state transitions.
final class NotchWindowController: NSObject {
    private let panel: NSPanel
    private let appState: AppState
    private var hostingController: NSHostingController<RootNotchView>?
    private var cancellables = Set<AnyCancellable>()

    private let compactSize = NSSize(width: 220, height: 30)
    private let expandedSize = NSSize(width: 360, height: 320)

    init(appState: AppState) {
        self.appState = appState
        self.panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: compactSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.acceptsMouseMovedEvents = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true

        // React to UI state changes (size animation).
        appState.$notchState
            .receive(on: RunLoop.main)
            .sink { [weak self] state in self?.applyState(state) }
            .store(in: &cancellables)
    }

    func present() {
        let root = RootNotchView(appState: appState, controller: self)
        let hosting = NSHostingController(rootView: root)
        hosting.view.wantsLayer = true
        self.hostingController = hosting
        panel.contentView = hosting.view

        applyState(appState.notchState)
        panel.orderFrontRegardless()
    }

    // MARK: - State transitions

    func userHoveredIn() {
        // Tiny intent delay before expanding (mirrors macOS notch idioms).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self = self else { return }
            // Only honor if still in hover-eligible state.
            switch self.appState.notchState {
            case .compactIdle, .compactHover:
                self.appState.notchState = .expandedHover
            default: break
            }
        }
        appState.notchState = .compactHover
    }

    func userHoveredOut() {
        // Don't collapse if pinned.
        if appState.notchState == .expandedPinned { return }
        appState.notchState = .compactIdle
    }

    func userClicked() {
        switch appState.notchState {
        case .expandedPinned:
            appState.notchState = .compactIdle
        default:
            appState.notchState = .expandedPinned
        }
    }

    func userPressedEscape() {
        appState.notchState = .compactIdle
    }

    private func applyState(_ state: NotchState) {
        let size: NSSize
        switch state {
        case .hidden:           size = NSSize(width: 1, height: 1)
        case .compactIdle, .compactHover: size = compactSize
        case .expandedHover, .expandedPinned: size = expandedSize
        }
        let origin = ScreenUtils.topCenteredOrigin(forPanelSize: size)
        let frame = NSRect(origin: origin, size: size)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        }
    }
}

/// Root content that swaps between compact and expanded.
struct RootNotchView: View {
    @ObservedObject var appState: AppState
    let controller: NotchWindowController

    var body: some View {
        Group {
            switch appState.notchState {
            case .hidden:
                Color.clear
            case .compactIdle, .compactHover:
                CompactView(appState: appState)
                    .onHover { hovering in
                        if hovering { controller.userHoveredIn() }
                        else        { controller.userHoveredOut() }
                    }
                    .onTapGesture { controller.userClicked() }
            case .expandedHover, .expandedPinned:
                ExpandedPanelView(appState: appState, controller: controller)
                    .onHover { hovering in
                        if !hovering, appState.notchState == .expandedHover {
                            controller.userHoveredOut()
                        }
                    }
            }
        }
        .sheet(isPresented: $appState.showOnboarding) {
            OnboardingView(appState: appState).frame(width: 420, height: 480)
        }
        .sheet(isPresented: $appState.showSettings) {
            SettingsView(appState: appState).frame(width: 440, height: 520)
        }
        .sheet(isPresented: $appState.showDiagnostics) {
            DiagnosticsView(appState: appState).frame(width: 420, height: 360)
        }
    }
}
