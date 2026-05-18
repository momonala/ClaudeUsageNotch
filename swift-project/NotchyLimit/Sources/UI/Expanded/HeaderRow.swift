import SwiftUI

struct HeaderRow: View {
    @ObservedObject var appState: AppState
    let controller: NotchWindowController

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            RetroMascot(size: 28)
            VStack(alignment: .leading, spacing: 0) {
                Text("Notchy Limit")
                    .font(Theme.bodyFont.weight(.semibold))
                    .foregroundColor(Theme.textPrimary)
                Text(syncSubtitle)
                    .font(Theme.captionFont)
                    .foregroundColor(Theme.textSecondary)
            }
            Spacer()
            Button { appState.showSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .foregroundColor(Theme.textSecondary)
            }
            .buttonStyle(.borderless)
        }
    }

    private var syncSubtitle: String {
        switch appState.syncStatus {
        case .idle:           return "Idle"
        case .syncing:        return "Syncing…"
        case .ok(let at):     return "Updated \(relative(at))"
        case .error(let e):   return e.description
        }
    }

    private func relative(_ date: Date) -> String {
        let secs = Int(Date().timeIntervalSince(date))
        if secs < 60 { return "just now" }
        if secs < 3600 { return "\(secs/60)m ago" }
        if secs < 86400 { return "\(secs/3600)h ago" }
        return "\(secs/86400)d ago"
    }
}
