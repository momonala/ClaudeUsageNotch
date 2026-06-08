import SwiftUI

/// Reset countdown, reset moment, and pace line below usage cards.
struct ResetSubtitleRow: View {
    let window: UsageWindow

    var body: some View {
        let parts: [String] = [
            window.timeToResetString(),
            window.resetAtLabel(),
            window.expectedUsageString(),
        ].compactMap { $0 }

        if !parts.isEmpty {
            HStack(spacing: 0) {
                ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                    if index > 0 {
                        Text("·")
                            .font(Theme.cardSubtitleFont)
                            .foregroundColor(Theme.textSecondary.opacity(0.5))
                            .padding(.horizontal, 7)
                    }
                    Text(part)
                        .font(Theme.cardSubtitleFont)
                        .foregroundColor(Theme.textSecondary)
                }
            }
        }
    }
}
