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

    private var notchH: CGFloat { ScreenUtils.notchScreen().safeAreaInsets.top }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Glass card — 156 pt visible portion, with a 12 pt transparent gap above it.
            ZStack(alignment: .topTrailing) {
                NotchGlassBackground(topRadius: 10, bottomRadius: 20)
                    .shadow(color: .black.opacity(0.55), radius: 28, y: 10)

                if appState.notchState == .expandedPinned {
                    HStack(spacing: 3) {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 8, weight: .semibold))
                        Text("Pinned")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(Theme.textSecondary.opacity(0.7))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Theme.surface))
                    .padding(.top, 8)
                    .padding(.trailing, 10)
                    .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .topTrailing)))
                }

                VStack(alignment: .leading, spacing: 8) {
                    HeaderRow(appState: appState, controller: controller)

                    if let incident = appState.activeIncident {
                        IncidentBanner(providerName: appState.activeProviderId.displayName,
                                       incident: incident)
                    }

                    SessionCard(appState: appState)

                    if let weekly = appState.latestSnapshot?.secondaryWindow {
                        WeeklyCard(window: weekly)
                    }
                    if let weeklySonnet = appState.latestSnapshot?.tertiaryWindow {
                        WeeklyCard(window: weeklySonnet,
                                   title: "Weekly Sonnet",
                                   subtitle: "Pro plan")
                    }

                    Spacer(minLength: 0)
                }
                .padding(.top, 12)
                .padding([.horizontal, .bottom], 12)
            }
            .frame(width: 380, height: 156)
            .scaleEffect(appeared ? 1 : 0.90, anchor: .top)
            .opacity(appeared ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Only paint black behind the hardware notch zone — the card manages its own background.
        // This prevents a harsh black rectangle showing through the card's rounded corners.
        .background(
            VStack(spacing: 0) {
                Color.black.frame(height: notchH)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        )
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                withAnimation(.spring(response: Theme.springResponse, dampingFraction: Theme.springDamping)) {
                    appeared = true
                }
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
