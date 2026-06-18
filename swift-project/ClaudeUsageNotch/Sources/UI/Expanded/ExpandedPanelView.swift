import SwiftUI

/// Expanded notch panel.
///
/// Panel frame is `notchH + content` tall, anchored at screen top.
/// The top `notchH` points are pure black and overlap the hardware notch.
/// A 28 pt transparent gap separates the notch from the glass card.
struct ExpandedPanelView: View {
    @ObservedObject var appState: AppState
    let appSettings: AppSettings
    let controller: NotchWindowController
    let refreshAction: () -> Void
    @State private var appeared = false

    var body: some View {
        let notchH = ScreenUtils.notchHeight

        ZStack(alignment: .bottom) {
            ZStack(alignment: .topLeading) {
                NotchPillShape(topRadius: 10, bottomRadius: 20)
                    .fill(Color.black)
                    .shadow(color: .black.opacity(0.55), radius: 28, y: 10)

                VStack(alignment: .leading, spacing: 8) {
                    HeaderRow(appState: appState, controller: controller, refreshAction: refreshAction)

                    switch appState.expandedMode {
                    case .usage:
                        if let incident = appState.activeIncident {
                            IncidentBanner(providerName: "Claude",
                                           incident: incident)
                        }
                        SessionCard(appState: appState)
                        if let weekly = appState.snapshot?.weeklyWindow {
                            WeeklyCard(window: weekly)
                        }
                        if let weeklySonnet = appState.snapshot?.weeklySonnetWindow {
                            WeeklyCard(window: weeklySonnet,
                                       title: "Weekly Sonnet",
                                       subtitle: "Pro plan")
                        }
                        lastUpdatedFooter
                    case .analytics:
                        UsageChartView(appState: appState, appSettings: appSettings)
                    case .settings:
                        InlineSettingsView(appSettings: appSettings)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.top, 12)
                .padding([.horizontal, .bottom], 12)
            }
            .frame(width: panelWidth, height: panelHeight)
            .scaleEffect(appeared ? 1 : 0.90, anchor: .top)
            .opacity(appeared ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(alignment: .top) {
            Color.black.frame(height: notchH)
        }
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

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    @ViewBuilder
    private var lastUpdatedFooter: some View {
        let label: String = {
            if case .ok(let at) = appState.syncStatus {
                let secs = Int(Date().timeIntervalSince(at))
                if secs < 5 { return "Last updated just now" }
                return "Last updated \(Self.relativeDateFormatter.localizedString(for: at, relativeTo: Date()))"
            }
            if case .syncing = appState.syncStatus { return "Syncing…" }
            return "Not yet synced"
        }()
        Text(label)
            .font(.system(size: 9))
            .foregroundColor(Theme.textSecondary.opacity(0.4))
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var panelWidth: CGFloat {
        appState.expandedMode == .analytics ? 1090 : 380
    }

    private var panelHeight: CGFloat {
        let notchH = ScreenUtils.notchHeight
        switch appState.expandedMode {
        case .usage:
            let base: CGFloat = 120
            let incidentExtra: CGFloat = appState.activeIncident != nil ? 32 : 0
            return base + incidentExtra
        case .analytics: return 590
        case .settings:  return notchH + 303
        }
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
