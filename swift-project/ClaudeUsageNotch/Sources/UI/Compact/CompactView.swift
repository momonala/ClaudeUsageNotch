import SwiftUI

/// Compact island pill.
///
/// The panel hosting this view is taller than what's visible: the top
/// `safeAreaInsets.top` points sit inside the physical notch hardware, where
/// the black fill blends with the camera housing. Content is pushed to the
/// bottom so it lands in the visible strip just below the notch.
struct CompactView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var appSettings: AppSettings
    @State private var appeared = false

    var body: some View {
        ZStack(alignment: .bottom) {
            pill
            if showAgentGlow {
                AgentStatusGlow(status: appState.agentStatus, justCompleted: appState.agentJustCompleted)
            }
        }
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: Theme.springResponse, dampingFraction: Theme.springDamping)) { appeared = true }
        }
        .help(appState.sessionResetString ?? "ClaudeUsageNotch")
    }

    /// The pill proper: black fill plus the visible content strip, inset from
    /// the panel by the status ring's margin so the fill measures exactly one
    /// hardware cutout.
    private var pill: some View {
        ZStack(alignment: .bottom) {
            NotchPillShape(topRadius: 0, bottomRadius: Theme.compactPillBottomRadius)
                .fill(Color.black)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Away from the app you run Claude Code in, the pill collapses to
            // the cutout itself — see `AppState.showsCompactContent`.
            if appState.showsCompactContent {
                strip
            }
        }
        .padding(EdgeInsets(top: 0,
                            leading: AgentStatusGlow.outset,
                            bottom: AgentStatusGlow.outset,
                            trailing: AgentStatusGlow.outset))
    }

    private var strip: some View {
        VStack(spacing: 3) {
            barRow(window: appState.snapshot?.sessionWindow, label: sessionLabel)
            if let weekly = appState.snapshot?.weeklyWindow {
                barRow(window: weekly)
            }
            if let credit = appState.snapshot?.creditWindow {
                barRow(window: credit)
            }
        }
        .padding(.horizontal, 10)
        // Anchored to the bottom with a real inset rather than centred: centring
        // left the last row hard against the pill's curved bottom edge. The
        // strip constants already account for this inset.
        .padding(.bottom, Theme.compactContentBottomInset)
        .frame(height: Theme.compactStripHeight
            + (appState.snapshot?.creditWindow != nil ? Theme.compactStripHeightCredit : 0),
               alignment: .bottom)
    }

    /// One bar plus its readout. `label` overrides the default percentage —
    /// used for the session row, which shows a reset countdown at the limit.
    /// Both occupy the same slot width, so what the label says can change
    /// without the pill's width moving off the cutout.
    private func barRow(window: UsageWindow?, label: String? = nil) -> some View {
        let pct = window?.effectivePercentUsed() ?? 0
        return HStack(spacing: 6) {
            CompactProgressBar(
                progress: pct,
                color: (window?.effectiveStatus() ?? .unknown).color,
                expectedProgress: window?.expectedProgress()
            )
                .frame(height: Theme.barHeightNotch)
            Text(label ?? "\(Int((pct * 100).rounded()))%")
                .font(label == nil ? Theme.notchFont : Theme.notchFontBold)
                .foregroundColor(label == nil ? Theme.textLabel : Theme.textPrimary)
                .frame(minWidth: 25, alignment: .trailing)
        }
    }

    private var sessionLabel: String? {
        guard appState.isAtSessionLimit else { return nil }
        return appState.sessionResetCompactString ?? "MAX"
    }

    /// Only in the untouched idle state — `.compactHover` is a brief transient
    /// en route to `.expandedHover`, so this hides the glow the instant the
    /// mouse arrives rather than waiting for the expansion animation.
    private var showAgentGlow: Bool {
        appSettings.showAgentStatusPulse
            && appState.notchState == .compactIdle
            && (appState.agentStatus != .idle || appState.agentJustCompleted)
    }
}
