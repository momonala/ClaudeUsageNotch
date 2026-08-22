import SwiftUI

/// Inline reset info for a card's title line — countdown, reset date/time,
/// and expected pace — e.g. "· Resets in 1h 12m · 3:45 PM · (20%)".
struct ResetHeaderLabel: View {
    let window: UsageWindow

    var body: some View {
        if window.resetAt != nil {
            let countdown = window.timeToResetShortString()
            let dateLabel = window.resetAtLabel()
            HStack(spacing: 3) {
                Text("·")
                if let countdown {
                    Text("Resets in \(countdown)")
                }
                if countdown != nil, dateLabel != nil {
                    Text("·")
                }
                if let dateLabel {
                    Text(dateLabel)
                }
                if let expected = window.expectedProgress() {
                    Text("· (\(Int((expected * 100).rounded()))%)")
                }
            }
            .font(Theme.cardResetDateFont)
            .foregroundColor(Theme.textSecondary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
        }
    }
}
