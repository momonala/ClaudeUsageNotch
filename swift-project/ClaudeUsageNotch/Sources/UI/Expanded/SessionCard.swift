import SwiftUI

struct SessionCard: View {
    @ObservedObject var appState: AppState

    var body: some View {
        let pct   = appState.sessionPercent
        let color = statusColor

        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(windowTitle)
                        .font(Theme.cardTitleFont)
                        .foregroundColor(Theme.textPrimary)
                    if appState.isBalance {
                        Text(appState.shortLabel)
                            .font(Theme.cardTitleFont)
                            .foregroundColor(color)
                        Text("Credit balance — usage % not provided")
                            .font(Theme.cardSubtitleFont)
                            .foregroundColor(Theme.textSecondary)
                    } else if appState.isStatusOnly {
                        Text("Connected")
                            .font(Theme.cardTitleFont)
                            .foregroundColor(color)
                        Text("No usage quota exposed")
                            .font(Theme.cardSubtitleFont)
                            .foregroundColor(Theme.textSecondary)
                    } else {
                        CompactProgressBar(
                            progress: pct,
                            color: color,
                            expectedProgress: appState.snapshot?.sessionWindow.expectedProgress()
                        )
                            .frame(height: Theme.barHeightExpanded)
                    }
                }
                Spacer()
                if !appState.isBalance && !appState.isStatusOnly {
                    Text("\(Int((pct * 100).rounded()))%")
                        .font(Theme.cardValueFont)
                        .foregroundColor(color)
                        .contentTransition(.numericText())
                        .animation(.spring(response: Theme.springResponse), value: pct)
                }
            }
            if let window = appState.snapshot?.sessionWindow,
               !appState.isBalance, !appState.isStatusOnly {
                ResetSubtitleRow(window: window)
            } else if let reset = appState.sessionResetString {
                Text(reset)
                    .font(Theme.cardSubtitleFont)
                    .foregroundColor(Theme.textSecondary)
            }
        }
        .padding(.horizontal, Theme.cardPaddingH)
        .padding(.vertical, Theme.cardPaddingV)
        .statusCardStyle(color: color)
    }

    private var statusColor: Color { appState.sessionStatus.color }

    private var windowTitle: String {
        switch appState.snapshot?.sessionWindow.type {
        case .monthly:              return "This month"
        case .daily:                return "Today"
        case .weekly, .weeklyModel: return "This week"
        default:                    return "This session"
        }
    }
}
