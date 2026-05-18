import SwiftUI

/// Expanded notch panel. Shown on hover-expand or click-pin.
struct ExpandedPanelView: View {
    @ObservedObject var appState: AppState
    let controller: NotchWindowController

    var body: some View {
        ZStack {
            GlassBackground(cornerRadius: 22)
            VStack(alignment: .leading, spacing: 14) {
                HeaderRow(appState: appState, controller: controller)
                SessionCard(appState: appState)
                if let weekly = appState.latestSnapshot?.secondaryWindow {
                    WeeklyCard(window: weekly)
                }
                if let weeklySonnet = appState.latestSnapshot?.tertiaryWindow {
                    WeeklyCard(window: weeklySonnet,
                               title: "Weekly Sonnet",
                               subtitle: "Pro plan")
                }
                PaceRow(appState: appState)
                Spacer(minLength: 0)
                ActionsRow(appState: appState, controller: controller)
                FooterRow()
            }
            .padding(18)
        }
        .frame(width: 360, height: 320)
        .background(KeyEventCatcher { key in
            if key == "\u{1B}" { controller.userPressedEscape() }  // ESC
        })
    }
}

/// AppKit shim to catch the Escape key while the panel is up.
struct KeyEventCatcher: NSViewRepresentable {
    var handler: (String) -> Void
    func makeNSView(context: Context) -> NSView {
        let v = KeyView()
        v.handler = handler
        DispatchQueue.main.async { v.window?.makeFirstResponder(v) }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
    private final class KeyView: NSView {
        var handler: ((String) -> Void)?
        override var acceptsFirstResponder: Bool { true }
        override func keyDown(with event: NSEvent) {
            if let chars = event.charactersIgnoringModifiers { handler?(chars) }
        }
    }
}
