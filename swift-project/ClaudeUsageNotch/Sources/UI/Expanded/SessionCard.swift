import SwiftUI

struct SessionCard: View {
    @ObservedObject var appState: AppState

    var body: some View {
        let pct   = appState.sessionPercent
        let color = statusColor

        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text(windowTitle)
                    .font(Theme.cardTitleFont)
                    .foregroundColor(Theme.textPrimary)
                if appState.activeIsBalance {
                    Text(appState.activeShortLabel)
                        .font(Theme.cardTitleFont)
                        .foregroundColor(color)
                    Text("Credit balance — usage % not provided")
                        .font(Theme.cardSubtitleFont)
                        .foregroundColor(Theme.textSecondary)
                } else if appState.activeIsStatusOnly {
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
                        expectedProgress: appState.activeSnapshot?.sessionWindow.expectedProgress()
                    )
                        .frame(height: Theme.barHeightExpanded)
                    Text(appState.sessionResetString ?? " ")
                        .font(Theme.cardSubtitleFont)
                        .foregroundColor(Theme.textSecondary)
                }
            }
            Spacer()
            if !appState.activeIsBalance && !appState.activeIsStatusOnly {
                Text("\(Int((pct * 100).rounded()))%")
                    .font(Theme.cardValueFont)
                    .foregroundColor(color)
                    .contentTransition(.numericText())
                    .animation(.spring(response: Theme.springResponse), value: pct)
            }
        }
        .padding(.horizontal, Theme.cardPaddingH)
        .padding(.vertical, Theme.cardPaddingV)
        .statusCardStyle(color: color)
    }

    private var statusColor: Color { appState.sessionStatus.color }

    private var windowTitle: String {
        switch appState.activeSnapshot?.sessionWindow.type {
        case .monthly:              return "This month"
        case .daily:                return "Today"
        case .weekly, .weeklyModel: return "This week"
        default:                    return "This session"
        }
    }
}
