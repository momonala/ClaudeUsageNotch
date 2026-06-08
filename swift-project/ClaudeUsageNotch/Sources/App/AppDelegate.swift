import SwiftUI
import AppKit
import Combine
import ServiceManagement

/// Root application controller. Wires AppState, NotchWindowController,
/// and the polling pipeline.
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let appState = AppState()
    var notchController: NotchWindowController?
    var coordinator: UsageCoordinator?
    var cancellables = Set<AnyCancellable>()

    // Standalone aux windows — work in every display mode (incl. menu-bar-only).
    private var onboardingWindow: NSWindow?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[ClaudeUsageNotch] launched — v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")

        ProviderRegistry.shared.bootstrap()

        coordinator = UsageCoordinator(
            appState: appState,
            authService: AuthService.shared,
            usageService: UsageService.shared,
            notifications: NotificationService.shared
        )
        coordinator?.start()

        syncLaunchAtLoginState()

        appState.$launchAtLogin
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in self?.setLaunchAtLogin(enabled) }
            .store(in: &cancellables)

        notchController = NotchWindowController(appState: appState)
        notchController?.present()

        // Present aux screens as standalone windows whenever their flag flips.
        appState.$showOnboarding.removeDuplicates().receive(on: RunLoop.main)
            .sink { [weak self] show in self?.presentAux(.onboarding, show: show) }
            .store(in: &cancellables)
        appState.$showSettings.removeDuplicates().receive(on: RunLoop.main)
            .sink { [weak self] show in self?.presentAux(.settings, show: show) }
            .store(in: &cancellables)
        if !AuthService.shared.hasAnyConfiguredProvider() {
            appState.showOnboarding = true
        }
    }

    // MARK: - Aux windows (Onboarding / Settings / Diagnostics)

    private enum AuxKind { case onboarding, settings }

    private func presentAux(_ kind: AuxKind, show: Bool) {
        let current: NSWindow? = {
            switch kind {
            case .onboarding: return onboardingWindow
            case .settings:   return settingsWindow
            }
        }()

        guard show else {
            current?.close()
            return
        }
        if let current {
            NSApp.activate(ignoringOtherApps: true)
            current.makeKeyAndOrderFront(nil)
            return
        }

        let content: NSView
        let size: NSSize
        let title: String
        switch kind {
        case .onboarding:
            content = NSHostingView(rootView: OnboardingView(appState: appState))
            size = NSSize(width: 420, height: 480); title = "Welcome to Notchy"
        case .settings:
            content = NSHostingView(rootView: SettingsView(appState: appState))
            size = NSSize(width: 460, height: 440); title = "Notchy Settings"
        }

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentView = content
        window.delegate = self
        window.center()

        switch kind {
        case .onboarding: onboardingWindow = window
        case .settings:   settingsWindow = window
        }

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let w = notification.object as? NSWindow else { return }
        switch w {
        case onboardingWindow: onboardingWindow = nil; appState.showOnboarding = false
        case settingsWindow:   settingsWindow = nil;   appState.showSettings = false
        default: break
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.stop()
    }

    @objc func quit() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Launch at login

    private func syncLaunchAtLoginState() {
        appState.launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register()   }
            else       { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("[ClaudeUsageNotch] Launch at login toggle failed: \(error.localizedDescription)")
            appState.launchAtLogin = !enabled
        }
    }
}
