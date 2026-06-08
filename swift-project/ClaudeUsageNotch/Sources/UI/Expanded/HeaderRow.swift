import SwiftUI

struct HeaderRow: View {
    @ObservedObject var appState: AppState
    let controller: NotchWindowController

    @State private var quitHovered = false
    @State private var quitPressed = false

    var body: some View {
        HStack(spacing: 6) {
            // Provider name + pin indicator (U6)
            HStack(spacing: 4) {
                Text(appState.activeProviderId.displayName)
                    .font(Theme.headerFont)
                    .foregroundColor(Theme.textPrimary)
                if appState.notchState == .expandedPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(Theme.textSecondary.opacity(0.6))
                        .transition(.opacity.combined(with: .scale(scale: 0.7)))
                }
            }
            .animation(.easeInOut(duration: 0.15), value: appState.notchState)

            Text("·")
                .foregroundColor(Theme.textSecondary.opacity(0.5))

            Text(syncSubtitle)
                .font(Theme.headerFontRegular)
                .foregroundColor(Theme.textSecondary)
                .lineLimit(1)

            Spacer()

            Button {
                appState.isNotchUIHidden.toggle()
                controller.userPressedEscape()
            } label: {
                Image(systemName: appState.isNotchUIHidden ? "eye.slash" : "eye")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textSecondary.opacity(0.6))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(appState.isNotchUIHidden ? "Show notch" : "Hide notch")
            .padding(.trailing, 6)

            Button {
                appState.showSettings = true
                controller.userPressedEscape()
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textSecondary.opacity(0.6))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Settings")
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
            .accessibilityLabel("Quit Notchy Limit")
            .onHover { hovering in quitHovered = hovering }
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
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }
}
