import SwiftUI

/// Compact notch pill. Shown when idle/hover. ~220x30.
struct CompactView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        ZStack {
            GlassBackground(cornerRadius: 14)
            HStack(spacing: 8) {
                StatusDot(status: statusForCompact)
                CompactProgressBar(
                    progress: appState.sessionPercent,
                    color: statusForCompact.color
                )
                .frame(width: 80, height: 5)
                Text("\(Int((appState.sessionPercent * 100).rounded()))%")
                    .font(Theme.numericFont)
                    .foregroundColor(Theme.textPrimary)
                    .frame(minWidth: 32, alignment: .trailing)
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 30)
        .help(appState.sessionResetString ?? "Notchy Limit")
    }

    private var statusForCompact: UsageStatus {
        appState.sessionStatus
    }
}
