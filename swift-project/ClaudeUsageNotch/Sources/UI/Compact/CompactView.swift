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
    @State private var appeared = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // Full-height black fill — top portion invisible (inside notch).
            NotchPillShape(topRadius: 0, bottomRadius: 14)
                .fill(Color.black)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Visible content strip (bottom 22 pt, below the notch edge).
            HStack(spacing: 7) {
                // Which provider this pill is showing (switch via the expanded panel).
                ProviderIconView(id: appState.activeProviderId, size: 13, fallbackColor: Theme.textLabel)

                // Outage badge — appears only when the active provider has an incident.
                if let incident = appState.activeIncident {
                    Image(systemName: incident.level.glyph)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(incident.level.tint)
                }

                if appState.activeShowsPercentBar {
                    VStack(spacing: 3) {
                        // Session row
                        HStack(spacing: 6) {
                            CompactProgressBar(
                                progress: appState.sessionPercent,
                                color: statusColor,
                                expectedProgress: appState.activeSnapshot?.sessionWindow.expectedProgress()
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
                        if let weekly = appState.activeSnapshot?.weeklyWindow {
                            HStack(spacing: 6) {
                                CompactProgressBar(
                                    progress: weekly.percentUsed,
                                    color: weeklyColor,
                                    expectedProgress: weekly.expectedProgress()
                                )
                                    .frame(height: Theme.barHeightNotch)
                                Text("\(Int((weekly.percentUsed * 100).rounded()))%")
                                    .font(Theme.notchFont)
                                    .foregroundColor(Theme.textLabel)
                                    .frame(minWidth: 25, alignment: .trailing)
                            }
                        }
                    }
                } else {
                    // Balance ("$110.00") or connected-only ("Active") — no fake bar.
                    Text(appState.activeShortLabel)
                        .font(Theme.notchFont)
                        .foregroundColor(Theme.textLabel)
                        .frame(minWidth: 40, alignment: .trailing)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
        }
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: Theme.springResponse, dampingFraction: Theme.springDamping)) { appeared = true }
        }
        .help(appState.sessionResetString ?? "ClaudeUsageNotch")
    }

    private var statusColor: Color { appState.sessionStatus.color }
    private var weeklyColor: Color {
        (appState.activeSnapshot?.weeklyWindow?.status ?? .healthy).color
    }
}
