import SwiftUI

struct SessionCard: View {
    @ObservedObject var appState: AppState
    @State private var displayedPercent: Int = 0
    @State private var animationEpoch: Int = 0

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
                    CompactProgressBar(progress: pct, color: color)
                        .frame(height: Theme.barHeightExpanded)
                    Text(appState.sessionResetString ?? " ")
                        .font(Theme.cardSubtitleFont)
                        .foregroundColor(Theme.textSecondary)
                }
            }
            Spacer()
            if !appState.activeIsBalance && !appState.activeIsStatusOnly {
                Text("\(displayedPercent)%")
                    .font(Theme.cardValueFont)
                    .foregroundColor(color)
                    .onAppear { animateTo(Int((pct * 100).rounded())) }
                    .onChange(of: pct) { _, newValue in animateTo(Int((newValue * 100).rounded())) }
            }
        }
        .padding(.horizontal, Theme.cardPaddingH)
        .padding(.vertical, Theme.cardPaddingV)
        .statusCardStyle(color: color)
    }

    private var statusColor: Color { appState.sessionStatus.color }

    private var windowTitle: String {
        switch appState.latestSnapshot?.primaryWindow.type {
        case .monthly:              return "This month"
        case .daily:                return "Today"
        case .weekly, .weeklyModel: return "This week"
        default:                    return "This session"
        }
    }

    private func animateTo(_ target: Int) {
        let start = displayedPercent
        let delta = target - start
        guard delta != 0 else { return }
        let steps    = max(abs(delta), 1)
        let interval = min(0.6 / Double(steps), 0.04)
        var current  = start
        animationEpoch += 1
        let epoch = animationEpoch
        func step() {
            guard current != target, animationEpoch == epoch else { return }
            current += delta > 0 ? 1 : -1
            displayedPercent = current
            DispatchQueue.main.asyncAfter(deadline: .now() + interval) { step() }
        }
        step()
    }
}
