import SwiftUI

struct SessionCard: View {
    @ObservedObject var appState: AppState

    var body: some View {
        let pct = appState.sessionPercent
        let status = appState.sessionStatus
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Session")
                    .font(Theme.bodyFont.weight(.semibold))
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                Text("\(Int((pct * 100).rounded()))%")
                    .font(Theme.numericFont)
                    .foregroundColor(status.color)
            }
            CompactProgressBar(progress: pct, color: status.color)
                .frame(height: 6)
            HStack {
                Text(resetCopy)
                    .font(Theme.captionFont)
                    .foregroundColor(Theme.textSecondary)
                Spacer()
                Text(urgencyCopy)
                    .font(Theme.captionFont.weight(.medium))
                    .foregroundColor(status.color.opacity(0.9))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Theme.surface)
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.stroke))
        )
    }

    private var resetCopy: String {
        appState.sessionResetString ?? "No reset time yet"
    }

    private var urgencyCopy: String {
        switch appState.sessionStatus {
        case .critical: return "At limit"
        case .warning:  return "Approaching"
        case .healthy:  return "On track"
        case .unknown:  return "—"
        }
    }
}
