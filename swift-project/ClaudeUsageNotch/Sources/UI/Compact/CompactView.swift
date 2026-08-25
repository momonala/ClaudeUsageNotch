import SwiftUI

/// Compact island pill.
///
/// The panel that hosts this view is taller than what's visible: the top
/// `safeAreaInsets.top` points sit inside the physical notch hardware
/// (invisible — black fill blends with the camera housing).  Content is
/// pushed to the bottom of the view with a Spacer so it appears in the
/// visible 22 pt strip just below the notch.  The result looks like the
/// notch grew a thin glowing status strip — identical to the Dynamic Island.
struct CompactView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var appSettings: AppSettings
    @State private var appeared = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // Full-height black fill — top portion invisible (inside notch).
            NotchPillShape(topRadius: 0, bottomRadius: 14)
                .fill(Color.black)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showAgentGlow {
                // Traces the black pill's own perimeter (no separate width) —
                // the pill is sized to the hardware notch, so the ring lands
                // flush with the physical cutout edges instead of curving in
                // somewhere inside it.
                AgentStatusGlow(status: appState.agentStatus, justCompleted: appState.agentJustCompleted)
            }

            // Visible content strip (bottom 22 pt, below the notch edge).
            HStack(spacing: 7) {
                if appState.showsPercentBar {
                    VStack(spacing: 3) {
                        // Session row
                        HStack(spacing: 6) {
                            CompactProgressBar(
                                progress: appState.sessionPercent,
                                color: statusColor,
                                expectedProgress: appState.snapshot?.sessionWindow.expectedProgress()
                            )
                                .frame(height: Theme.barHeightNotch)
                            if appState.isAtSessionLimit {
                                Text(appState.sessionResetShortString ?? "LIMIT")
                                    .font(Theme.notchFontBold)
                                    .foregroundColor(Theme.textPrimary)
                                    .frame(minWidth: 40, alignment: .trailing)
                            } else {
                                Text("\(Int((appState.sessionPercent * 100).rounded()))%")
                                    .font(Theme.notchFont)
                                    .foregroundColor(Theme.textLabel)
                                    .frame(minWidth: 25, alignment: .trailing)
                            }
                        }
                        // Weekly row
                        if let weekly = appState.snapshot?.weeklyWindow {
                            HStack(spacing: 6) {
                                CompactProgressBar(
                                    progress: weekly.effectivePercentUsed(),
                                    color: weeklyColor,
                                    expectedProgress: weekly.expectedProgress()
                                )
                                    .frame(height: Theme.barHeightNotch)
                                Text("\(Int((weekly.effectivePercentUsed() * 100).rounded()))%")
                                    .font(Theme.notchFont)
                                    .foregroundColor(Theme.textLabel)
                                    .frame(minWidth: 25, alignment: .trailing)
                            }
                        }
                        // Credit row (Team plans only)
                        if let credit = appState.snapshot?.creditWindow {
                            HStack(spacing: 6) {
                                CompactProgressBar(
                                    progress: credit.effectivePercentUsed(),
                                    color: creditColor,
                                    expectedProgress: credit.expectedProgress()
                                )
                                    .frame(height: Theme.barHeightNotch)
                                Text("\(Int((credit.effectivePercentUsed() * 100).rounded()))%")
                                    .font(Theme.notchFont)
                                    .foregroundColor(Theme.textLabel)
                                    .frame(minWidth: 25, alignment: .trailing)
                            }
                        }
                    }
                } else {
                    // Balance ("$110.00") or connected-only ("Active") — no fake bar.
                    Text(appState.shortLabel)
                        .font(Theme.notchFont)
                        .foregroundColor(Theme.textLabel)
                        .frame(minWidth: 40, alignment: .trailing)
                }
            }
            .padding(.horizontal, 10)
            // Anchored to the bottom with a real inset rather than centred in
            // the strip: centring left the last row hard against the pill's
            // curved bottom edge. The strip constants already account for this
            // inset, so the rows aren't squeezed to make room for it.
            .padding(.bottom, Theme.compactContentBottomInset)
            .frame(height: Theme.compactStripHeight
                + (appState.snapshot?.creditWindow != nil ? Theme.compactStripHeightCredit : 0),
                   alignment: .bottom)
        }
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: Theme.springResponse, dampingFraction: Theme.springDamping)) { appeared = true }
        }
        .help(appState.sessionResetString ?? "ClaudeUsageNotch")
    }

    private var statusColor: Color { appState.sessionStatus.color }
    private var weeklyColor: Color {
        (appState.snapshot?.weeklyWindow?.effectiveStatus() ?? .healthy).color
    }
    private var creditColor: Color {
        (appState.snapshot?.creditWindow?.effectiveStatus() ?? .healthy).color
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
