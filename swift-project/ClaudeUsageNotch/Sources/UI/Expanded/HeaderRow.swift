import SwiftUI

struct HeaderRow: View {
    @ObservedObject var appState: AppState
    let controller: NotchWindowController

    @State private var quitHovered = false
    @State private var quitPressed = false

    var body: some View {
        HStack(spacing: 6) {
            Text(appState.activeProviderId.displayName)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.textPrimary)

            Text("·")
                .foregroundColor(Theme.textSecondary.opacity(0.5))

            Text(syncSubtitle)
                .font(.system(size: 11, design: .rounded))
                .foregroundColor(Theme.textSecondary)
                .lineLimit(1)

            Spacer()

            Button {
                appState.showSettings = true
                controller.userPressedEscape()
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textSecondary.opacity(0.6))
            }
            .buttonStyle(.borderless)
            .padding(.trailing, 6)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 11))
                    .foregroundColor(quitHovered ? Color.red.opacity(0.85) : Theme.textSecondary.opacity(0.6))
                    .scaleEffect(quitPressed ? 0.82 : 1.0)
                    .animation(.spring(response: 0.2, dampingFraction: 0.6), value: quitPressed)
                    .animation(.easeInOut(duration: 0.18), value: quitHovered)
            }
            .buttonStyle(.borderless)
            .onHover { hovering in
                quitHovered = hovering
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in quitPressed = true }
                    .onEnded { _ in quitPressed = false }
            )
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
        if secs < 60    { return "just now" }
        if secs < 3600  { return "\(secs / 60)m ago" }
        if secs < 86400 { return "\(secs / 3600)h ago" }
        return "\(secs / 86400)d ago"
    }
}
