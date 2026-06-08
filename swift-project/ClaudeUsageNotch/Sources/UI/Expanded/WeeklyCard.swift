import SwiftUI

struct WeeklyCard: View {
    let window: UsageWindow
    var title: String   = "This week"
    var subtitle: String? = nil

    var body: some View {
        let pct    = window.percentUsed
        let status = window.status
        let color  = status.color

        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(title)
                        .font(Theme.cardTitleFont)
                        .foregroundColor(Theme.textPrimary)
                    if let sub = subtitle {
                        Text(sub)
                            .font(Theme.cardSubtitleFont)
                            .foregroundColor(Theme.textSecondary)
                    }
                }
                CompactProgressBar(progress: pct, color: color, expectedProgress: window.expectedProgress())
                    .frame(height: Theme.barHeightExpanded)
                Text(window.timeToResetString() ?? " ")
                    .font(Theme.cardSubtitleFont)
                    .foregroundColor(Theme.textSecondary)
            }
            Spacer()
            Text("\(Int((pct * 100).rounded()))%")
                .font(Theme.weeklyValueFont)
                .foregroundColor(color)
        }
        .padding(.horizontal, Theme.cardPaddingH)
        .padding(.vertical, Theme.cardPaddingV)
        .statusCardStyle(color: color)
    }
}
