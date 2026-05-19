import SwiftUI
import AppKit
import Combine
import ServiceManagement

/// Root application controller. Wires the AppState, the NotchWindowController,
/// and the polling pipeline.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    var notchController: NotchWindowController?
    var coordinator: UsageCoordinator?
    var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[NotchyLimit] launched — v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")

        // Bootstrap providers (Claude today, Gemini stub).
        ProviderRegistry.shared.bootstrap()

        // Wire services + coordinator.
        coordinator = UsageCoordinator(
            appState: appState,
            authService: AuthService.shared,
            usageService: UsageService.shared,
            notifications: NotificationService.shared
        )
        coordinator?.start()

        // Sync launch-at-login state from SMAppService into AppState.
        syncLaunchAtLoginState()

        // React to launchAtLogin toggle from Settings.
        appState.$launchAtLogin
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in self?.setLaunchAtLogin(enabled) }
            .store(in: &cancellables)

        // Build and show the notch window.
        notchController = NotchWindowController(appState: appState)
        notchController?.present()

        // The notch panel is non-activating by design (never steals focus).
        // When a sheet (onboarding/settings) needs keyboard input, activate
        // the app so the sheet window can become key and accept paste/typing.
        Publishers.CombineLatest3(
            appState.$showOnboarding,
            appState.$showSettings,
            appState.$showDiagnostics
        )
        .map { $0 || $1 || $2 }
        .removeDuplicates()
        .receive(on: RunLoop.main)
        .sink { anySheetOpen in
            if anySheetOpen {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        .store(in: &cancellables)

        // Surface onboarding if no provider is configured yet.
        if !AuthService.shared.hasAnyConfiguredProvider() {
            appState.showOnboarding = true
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.stop()
    }

    @objc func quit() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Launch at Login

    private func syncLaunchAtLoginState() {
        if #available(macOS 13.0, *) {
            appState.launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("[NotchyLimit] Launch at login toggle failed: \(error.localizedDescription)")
                // Revert the toggle if the OS call failed.
                appState.launchAtLogin = !enabled
            }
        }
    }
}
