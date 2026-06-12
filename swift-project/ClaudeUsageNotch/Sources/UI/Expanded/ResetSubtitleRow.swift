import SwiftUI

/// Reset countdown, reset moment, and pace line below usage cards.
struct ResetSubtitleRow: View {
    let window: UsageWindow

    var body: some View {
        if let subtitle = window.resetAndExpectedSubtitle() {
            Text(subtitle)
                .font(Theme.cardSubtitleFont)
                .foregroundColor(Theme.textSecondary)
        }
    }
}
