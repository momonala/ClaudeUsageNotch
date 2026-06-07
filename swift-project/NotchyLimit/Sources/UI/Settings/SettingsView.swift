import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                header
                Divider().background(Theme.stroke)
                settingsRows
            }
        }
        .frame(width: 480, height: 248)
    }

    // MARK: - Header

    private var header: some View {
        Text("Settings")
            .font(Theme.displayFont)
            .foregroundColor(Theme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)
    }

    // MARK: - Rows

    private var settingsRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            row {
                Toggle("", isOn: $appState.notificationsEnabled)
                    .toggleStyle(.switch)
                    .tint(Theme.accentWarm)
                    .labelsHidden()
                    .fixedSize()
                rowLabel("Enable notifications")
            }

            rowDivider

            row {
                thresholdButtons
                rowLabel("Notify at")
                Spacer()
                Button("Test") { NotificationService.shared.sendTest() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .font(.system(size: 12, design: .rounded))
            }
            .disabled(!appState.notificationsEnabled)
            .opacity(appState.notificationsEnabled ? 1 : 0.4)

            rowDivider

            row {
                Picker("", selection: $appState.pollIntervalSeconds) {
                    Text("1 min").tag(TimeInterval(60))
                    Text("5 min").tag(TimeInterval(300))
                    Text("15 min").tag(TimeInterval(900))
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 160)
                .onChange(of: appState.pollIntervalSeconds) { _, newValue in
                    UsageService.shared.updateInterval(newValue)
                }
                rowLabel("Poll every")
            }

            rowDivider

            row {
                Toggle("", isOn: $appState.launchAtLogin)
                    .toggleStyle(.switch)
                    .tint(Theme.accentWarm)
                    .labelsHidden()
                    .fixedSize()
                rowLabel("Launch at login")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func row<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
    }

    private func rowLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(.subheadline, design: .rounded))
            .foregroundColor(Theme.textPrimary)
    }

    private var rowDivider: some View {
        Divider()
            .background(Theme.stroke.opacity(0.5))
    }

    private var thresholdButtons: some View {
        HStack(spacing: 4) {
            ForEach([0.25, 0.5, 0.75, 0.9, 1.0], id: \.self) { t in
                let on = appState.thresholds.contains(t)
                Button("\(Int(t * 100))%") {
                    if on { appState.thresholds.removeAll { $0 == t } }
                    else  { appState.thresholds.append(t) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(on ? Theme.accentWarm : Theme.textSecondary)
                .font(.system(size: 12, design: .rounded))
            }
        }
    }
}
