import SwiftUI

/// Expanded notch panel.
///
/// Panel frame is `notchH + 184` tall, anchored at screen top.
/// The top `notchH` points are pure black and overlap the hardware notch.
/// A 28 pt transparent gap separates the notch from the 156 pt glass card.
struct ExpandedPanelView: View {
    @ObservedObject var appState: AppState
    let controller: NotchWindowController
    @State private var appeared = false

    var body: some View {
        let notchH = ScreenUtils.notchHeight

        ZStack(alignment: .bottom) {
            // Glass card — 156 pt visible portion, with a 12 pt transparent gap above it.
            ZStack(alignment: .topLeading) {
                NotchPillShape(topRadius: 10, bottomRadius: 20)
                    .fill(Color.black)
                    .shadow(color: .black.opacity(0.55), radius: 28, y: 10)

                VStack(alignment: .leading, spacing: 8) {
                    HeaderRow(appState: appState, controller: controller)

                    if appState.showAnalyticsChart {
                        UsageChartView(appState: appState)
                    } else {
                        if let incident = appState.activeIncident {
                            IncidentBanner(providerName: appState.activeProviderId.displayName,
                                           incident: incident)
                        }

                        SessionCard(appState: appState)

                        if let weekly = appState.activeSnapshot?.weeklyWindow {
                            WeeklyCard(window: weekly)
                        }
                        if let weeklySonnet = appState.activeSnapshot?.weeklySonnetWindow {
                            WeeklyCard(window: weeklySonnet,
                                       title: "Weekly Sonnet",
                                       subtitle: "Pro plan")
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(.top, 12)
                .padding([.horizontal, .bottom], 12)
            }
            .frame(width: appState.showAnalyticsChart ? 450 : 380,
                   height: appState.showAnalyticsChart ? 308 : 156)
            .scaleEffect(appeared ? 1 : 0.90, anchor: .top)
            .opacity(appeared ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Only paint black behind the hardware notch zone — the card manages its own background.
        .background(
            VStack(spacing: 0) {
                Color.black.frame(height: notchH)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        )
        .task {
            try? await Task.sleep(nanoseconds: 140_000_000)
            withAnimation(.spring(response: Theme.springResponse, dampingFraction: Theme.springDamping)) {
                appeared = true
            }
        }
        .background(KeyEventCatcher { key in
            if key == "\u{1B}" { controller.userPressedEscape() }
        })
    }
}

struct KeyEventCatcher: NSViewRepresentable {
    var handler: (String) -> Void
    func makeNSView(context: Context) -> NSView {
        let v = KeyView()
        v.handler = handler
        v.wantsLayer = true
        v.layer?.backgroundColor = .clear
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
