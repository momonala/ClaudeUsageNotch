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
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.textPrimary)
                    if let sub = subtitle {
                        Text(sub)
                            .font(.system(size: 10, design: .rounded))
                            .foregroundColor(Theme.textSecondary)
                    }
                }
                CompactProgressBar(progress: pct, color: color)
                    .frame(height: 3)
                Text(window.timeToResetString() ?? " ")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundColor(Theme.textSecondary)
            }
            Spacer()
            Text("\(Int((pct * 100).rounded()))%")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(color)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(color.opacity(0.18), lineWidth: 0.75)
                )
        )
    }
}
