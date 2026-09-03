import SwiftUI

/// Expanded notch panel: a black strip overlapping the hardware notch, a
/// transparent gap, then the card. Every size comes from
/// `ExpandedPanelGeometry`, shared with the window controller.
struct ExpandedPanelView: View {
    @ObservedObject var appState: AppState
    let appSettings: AppSettings
    let controller: NotchWindowController
    @State private var appeared = false

    var body: some View {
        let notchH = ScreenUtils.notchHeight

        ZStack(alignment: .bottom) {
            ZStack(alignment: .topLeading) {
                NotchPillShape(topRadius: Theme.panelTopRadius,
                               bottomRadius: Theme.panelBottomRadius)
                    .fill(Color.black)
                    .shadow(color: .black.opacity(0.55), radius: 28, y: 10)

                VStack(alignment: .leading, spacing: 8) {
                    HeaderRow(appState: appState, controller: controller)

                    switch appState.expandedMode {
                    case .usage:
                        statusRow
                        UsageCard(window: appState.snapshot?.sessionWindow,
                                  title: "This session", emphasized: true)
                        if let weekly = appState.snapshot?.weeklyWindow {
                            UsageCard(window: weekly, title: "This week")
                        }
                        if let weeklySonnet = appState.snapshot?.weeklySonnetWindow {
                            UsageCard(window: weeklySonnet, title: "Weekly Sonnet", subtitle: "Pro plan")
                        }
                        if let credit = appState.snapshot?.creditWindow {
                            UsageCard(window: credit, title: "Usage credits")
                        }
                    case .analytics:
                        UsageChartView(appState: appState, appSettings: appSettings)
                    case .settings:
                        InlineSettingsView(appSettings: appSettings, appState: appState)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.top, 12)
                .padding([.horizontal, .bottom], Theme.panelContentMargin)
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

    /// Outage (if any) and last-synced status share one compact row instead
    /// of each claiming a full-width banner — the outage text is short and
    /// doesn't need the whole row.
    @ViewBuilder
    private var statusRow: some View {
        HStack(spacing: 6) {
            if let incident = appState.activeIncident {
                StatusBubble(icon: incident.level.glyph, text: incident.summary, tint: incident.level.tint)
            }
            Spacer(minLength: 0)
            StatusBubble(icon: nil, text: lastUpdatedText, tint: Theme.accentCool)
        }
    }

    private var lastUpdatedText: String {
        if case .ok(let at) = appState.syncStatus {
            let secs = Int(Date().timeIntervalSince(at))
            if secs < 5 { return "Updated just now" }
            return "Updated \(Self.relativeDateFormatter.localizedString(for: at, relativeTo: Date()))"
        }
        if case .syncing = appState.syncStatus { return "Syncing…" }
        return "Not synced"
    }

    private var panelWidth: CGFloat {
        ExpandedPanelGeometry.width(for: appState.expandedMode)
    }

    /// Card height only — the notch overlap and the gap below it are the
    /// window's business, not the card's.
    private var panelHeight: CGFloat {
        let mode = appState.expandedMode
        let creditExtra = (mode == .usage && appState.snapshot?.creditWindow != nil)
            ? ExpandedPanelGeometry.usageCreditExtra : 0
        return ExpandedPanelGeometry.cardHeight(for: mode) + creditExtra
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
