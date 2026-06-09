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
    var cancellables = Set<AnyCancellable>()

    private var onboardingWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[ClaudeUsageNotch] launched — v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")

        coordinator = UsageCoordinator(
            appState: appState,
            appSettings: appSettings,
            authService: AuthService.shared,
            usageService: UsageService.shared,
            notifications: NotificationService.shared
        )
        coordinator?.start()

        syncLaunchAtLoginState()

        appSettings.$launchAtLogin
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in self?.setLaunchAtLogin(enabled) }
            .store(in: &cancellables)

        notchController = NotchWindowController(
            appState: appState,
            appSettings: appSettings,
            refreshAction: { [weak self] in self?.coordinator?.refreshNow() }
        )
        notchController?.present()

        appState.$showOnboarding.removeDuplicates().receive(on: RunLoop.main)
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
            }
        )
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 420, height: 480)),
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

    func windowWillClose(_ notification: Notification) {
        guard let w = notification.object as? NSWindow, w === onboardingWindow else { return }
        onboardingWindow = nil
        appState.showOnboarding = false
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.stop()
        notchController?.teardown()
    }

    @objc func quit() {
        NSApplication.shared.terminate(nil)
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
