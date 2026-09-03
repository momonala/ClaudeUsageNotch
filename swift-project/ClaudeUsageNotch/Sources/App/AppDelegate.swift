import SwiftUI
import AppKit
import Combine
import ServiceManagement

/// Root application controller. Wires AppState, AppSettings, NotchWindowController,
/// and the polling pipeline.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let appState    = AppState()
    let appSettings = AppSettings()
    var notchController: NotchWindowController?
    var coordinator: UsageCoordinator?
    var historySync: HistorySyncService?
    var cancellables = Set<AnyCancellable>()

    private var onboardingWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `xcodebuild test` injects the unit-test bundle into this app, so a
        // normal launch would spin up a second notch panel and start Keychain
        // reads, network polling and timers inside the test process — which
        // traps before a single test runs. The tests exercise pure types via
        // `@testable import`; they need the module loaded, not the app running.
        if NSClassFromString("XCTestCase") != nil { return }

        NSLog("[ClaudeUsageNotch] launched — v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")

        coordinator = UsageCoordinator(
            appState: appState,
            appSettings: appSettings,
            authService: AuthService.shared,
            usageService: UsageService.shared,
            notifications: NotificationService.shared
        )
        coordinator?.start()

        historySync = HistorySyncService(settings: appSettings)
        historySync?.start()

        // Delay 10 s after wake so Wi-Fi has time to reconnect before the first fetch.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                self?.coordinator?.refreshNow()
            }
        }

        // Retry immediately on screen unlock — Keychain is available and network is stable.
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.coordinator?.refreshNow() }
        }

        syncLaunchAtLoginState()

        appSettings.$launchAtLogin
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in self?.setLaunchAtLogin(enabled) }
            .store(in: &cancellables)

        notchController = NotchWindowController(appState: appState, appSettings: appSettings)
        notchController?.present()

        appState.$showOnboarding.removeDuplicates().receive(on: DispatchQueue.main)
            .sink { [weak self] show in self?.presentOnboarding(show: show) }
            .store(in: &cancellables)

        if !AuthService.shared.hasAnyConfiguredProvider() {
            appState.showOnboarding = true
        }
    }

    // MARK: - Aux windows

    private func presentOnboarding(show: Bool) {
        guard show else { onboardingWindow?.close(); return }
        if let w = onboardingWindow { NSApp.activate(ignoringOtherApps: true); w.makeKeyAndOrderFront(nil); return }

        let view = OnboardingView(
            appState: appState,
            appSettings: appSettings,
            onCredentialsSaved: { [weak self] in
                self?.coordinator?.onCredentialsSaved()
            },
            onContentHeightChange: { [weak self] height in
                self?.resizeOnboardingWindow(toContentHeight: height)
            }
        )
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 420, height: 365)),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to ClaudeUsageNotch"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.delegate = self
        window.center()
        onboardingWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Resizes the onboarding window to hug the current step's content instead
    /// of leaving empty space below shorter steps. Keeps the top edge anchored
    /// so the header/progress dots don't jump around as the height changes.
    private func resizeOnboardingWindow(toContentHeight height: CGFloat) {
        guard let window = onboardingWindow else { return }
        let targetContentSize = NSSize(width: 420, height: height)
        let targetFrame = window.frameRect(forContentRect: NSRect(origin: .zero, size: targetContentSize))
        guard abs(targetFrame.height - window.frame.height) > 0.5 else { return }
        var newFrame = window.frame
        let deltaHeight = targetFrame.height - newFrame.height
        newFrame.size.height = targetFrame.height
        newFrame.origin.y -= deltaHeight
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(newFrame, display: true)
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let w = notification.object as? NSWindow, w === onboardingWindow else { return }
        onboardingWindow = nil
        appState.showOnboarding = false
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.stop()
        historySync?.stop()
        notchController?.teardown()
    }

    // MARK: - Launch at login

    private func syncLaunchAtLoginState() {
        appSettings.launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register()   }
            else       { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("[ClaudeUsageNotch] Launch at login toggle failed: \(error.localizedDescription)")
            appSettings.launchAtLogin = !enabled
        }
    }
}
