import SwiftUI
import AppKit
import Combine

/// Root application controller. Wires the AppState, the NotchWindowController,
/// and the polling pipeline.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    var notchController: NotchWindowController?
    var coordinator: UsageCoordinator?
    var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[NotchyLimit] launched")

        // Bootstrap providers (Claude today, Gemini stub).
        ProviderRegistry.shared.bootstrap()

        // Wire services + coordinator. The coordinator decides which provider is
        // "active" and feeds snapshots into appState.
        coordinator = UsageCoordinator(
            appState: appState,
            authService: AuthService.shared,
            usageService: UsageService.shared,
            notifications: NotificationService.shared
        )
        coordinator?.start()

        // Build and show the notch window.
        notchController = NotchWindowController(appState: appState)
        notchController?.present()

        // If no provider has credentials yet, surface onboarding.
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
}
