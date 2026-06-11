import SwiftUI

struct HeaderRow: View {
    @ObservedObject var appState: AppState
    let controller: NotchWindowController
    let refreshAction: () -> Void

    @State private var quitHovered = false
    @State private var quitPressed = false
    @State private var refreshRotation: Double = 0
    @State private var refreshBright = false

    var body: some View {
        // Mode buttons sit LEFT of the spacer so they stay in the left "ear"
        // (clear of the hardware notch). Eye and power anchor the right "ear".
        // The spacer spans the notch dead-zone in between.
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                ProviderIconView(size: 14, fallbackColor: Theme.textPrimary)
                if appState.notchState == .expandedPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(Theme.textSecondary.opacity(0.6))
                        .transition(.opacity.combined(with: .scale(scale: 0.7)))
                }
            }
            .animation(.easeInOut(duration: 0.15), value: appState.notchState)

            Button {
                withAnimation(.easeOut(duration: 0.5)) { refreshRotation += 360 }
                withAnimation(.easeOut(duration: 0.15)) { refreshBright = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    withAnimation(.easeIn(duration: 0.25)) { refreshBright = false }
                }
                refreshAction()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
                    .foregroundColor(refreshBright ? Theme.accentWarm : Theme.textSecondary.opacity(0.6))
                    .rotationEffect(.degrees(refreshRotation))
            }
            .buttonStyle(.borderless)
            .padding(.trailing, 2)

            modeButton(.usage,     icon: "gauge.medium")
            modeButton(.analytics, icon: "chart.bar.fill")

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

            modeButton(.settings, icon: "gearshape.fill")

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
            .accessibilityLabel("Quit ClaudeUsageNotch")
            .onHover { hovering in quitHovered = hovering }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in quitPressed = true }
                    .onEnded { _ in quitPressed = false }
            )
        }
    }

    private func modeButton(_ mode: ExpandedMode, icon: String) -> some View {
        Button { appState.expandedMode = mode } label: {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(appState.expandedMode == mode
                    ? Theme.accentWarm
                    : Theme.textSecondary.opacity(0.6))
        }
        .buttonStyle(.borderless)
        .padding(.trailing, 6)
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
