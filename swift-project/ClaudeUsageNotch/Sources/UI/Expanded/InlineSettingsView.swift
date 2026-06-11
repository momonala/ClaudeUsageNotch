import SwiftUI

struct InlineSettingsView: View {
    @ObservedObject var appSettings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Settings")
                .font(Theme.headerFont)
                .foregroundColor(Theme.textPrimary)
                .padding(.bottom, 8)

            sectionTitle("Notifications")
            row {
                Toggle("", isOn: $appSettings.notificationsEnabled)
                    .toggleStyle(.switch)
                    .tint(Color(nsColor: .controlAccentColor))
                    .labelsHidden()
                    .fixedSize()
                    .scaleEffect(0.75, anchor: .leading)
                thresholdButtons
                    .disabled(!appSettings.notificationsEnabled)
                    .opacity(appSettings.notificationsEnabled ? 1 : 0.4)
                Spacer()
                Button("Test") { NotificationService.shared.sendTest() }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .font(.system(size: 11, design: .rounded))
                    .disabled(!appSettings.notificationsEnabled)
                    .opacity(appSettings.notificationsEnabled ? 1 : 0.4)
            }

            rowDivider

            sectionTitle("Poll Frequency")
            row {
                Picker("", selection: $appSettings.pollIntervalSeconds) {
                    Text("1 min").tag(TimeInterval(60))
                    Text("5 min").tag(TimeInterval(300))
                    Text("15 min").tag(TimeInterval(900))
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 150)
                .padding(.leading, 2)
            }

            rowDivider

            sectionTitle("Launch at Login")
            row {
                Toggle("", isOn: $appSettings.launchAtLogin)
                    .toggleStyle(.switch)
                    .tint(Color(nsColor: .controlAccentColor))
                    .labelsHidden()
                    .fixedSize()
                    .scaleEffect(0.75, anchor: .leading)
            }

            rowDivider

            sectionTitle("Sync Server")
            row {
                TextField("http://host:5014", text: $appSettings.apiBaseURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: 220)
            }
            row {
                Picker("", selection: $appSettings.syncIntervalSeconds) {
                    Text("1 min").tag(TimeInterval(60))
                    Text("5 min").tag(TimeInterval(300))
                    Text("15 min").tag(TimeInterval(900))
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 180)
                .disabled(syncDisabled)
                .opacity(syncDisabled ? 0.4 : 1)
            }
        }
    }

    private var syncDisabled: Bool {
        appSettings.apiBaseURL.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundColor(Theme.textSecondary.opacity(0.7))
            .textCase(.uppercase)
            .kerning(0.5)
            .padding(.bottom, 2)
    }

    @ViewBuilder
    private func row<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
    }

    private var rowDivider: some View {
        Divider()
            .background(Theme.stroke.opacity(0.4))
            .padding(.vertical, 5)
    }

    private var thresholdButtons: some View {
        HStack(spacing: 3) {
            ForEach([0.25, 0.5, 0.75, 0.9], id: \.self) { t in
                let on = appSettings.thresholds.contains(t)
                Button("\(Int(t * 100))%") {
                    if on { appSettings.thresholds.removeAll { $0 == t } }
                    else  { appSettings.thresholds.append(t) }
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11, design: .rounded))
                .foregroundColor(on ? Theme.accentWarm : Theme.textSecondary.opacity(0.6))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(on ? Theme.accentWarm.opacity(0.15) : Color.clear)
                )
            }
        }
    }
}
