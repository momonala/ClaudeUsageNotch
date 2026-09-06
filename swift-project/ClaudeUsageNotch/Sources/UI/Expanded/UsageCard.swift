import SwiftUI

/// One quota window in the expanded panel: title, reset info, bar, percentage.
/// The session card is `emphasized`, giving it a larger animated value.
struct UsageCard: View {
    let window: UsageWindow?
    let title: String
    var subtitle: String? = nil
    var emphasized = false

    var body: some View {
        let pct   = window?.effectivePercentUsed() ?? 0
        let color = (window?.effectiveStatus() ?? .unknown).color

        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: emphasized ? 5 : 3) {
                HStack(spacing: 5) {
                    Text(title)
                        .font(Theme.cardTitleFont)
                        .foregroundColor(Theme.textPrimary)
                    if let subtitle {
                        Text(subtitle)
                            .font(Theme.cardSubtitleFont)
                            .foregroundColor(Theme.textSecondary)
                    }
                    if let window {
                        ResetHeaderLabel(window: window)
                    }
                }
                CompactProgressBar(progress: pct, color: color, expectedProgress: window?.expectedProgress())
                    .frame(height: Theme.barHeightExpanded)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(Int((pct * 100).rounded()))%")
                .font(emphasized ? Theme.cardValueFont : Theme.weeklyValueFont)
                .foregroundColor(color)
                .contentTransition(.numericText())
                .animation(emphasized ? .spring(response: Theme.springResponse) : nil, value: pct)
        }
        .padding(.horizontal, Theme.cardPaddingH)
        .padding(.vertical, Theme.cardPaddingV)
    }
}
