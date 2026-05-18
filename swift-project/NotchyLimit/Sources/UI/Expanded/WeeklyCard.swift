import SwiftUI

struct WeeklyCard: View {
    let window: UsageWindow
    var title: String = "This week"
    var subtitle: String? = nil

    var body: some View {
        let pct = window.percentUsed
        let status = window.status
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(Theme.captionFont.weight(.semibold))
                        .foregroundColor(Theme.textPrimary)
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(Theme.captionFont)
                            .foregroundColor(Theme.textSecondary)
                    }
                }
                CompactProgressBar(progress: pct, color: status.color)
                    .frame(height: 4)
                Text(window.timeToResetString() ?? " ")
                    .font(Theme.captionFont)
                    .foregroundColor(Theme.textSecondary)
            }
            Spacer()
            Text("\(Int((pct * 100).rounded()))%")
                .font(Theme.numericFont)
                .foregroundColor(status.color)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.surface.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.stroke))
        )
    }
}
