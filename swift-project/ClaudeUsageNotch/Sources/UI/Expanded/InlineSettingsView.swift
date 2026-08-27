import SwiftUI

/// Settings pane of the expanded notch panel.
///
/// Laid out as a plain form: sentence-case section headers over unboxed
/// groups of same-height rows, each row a leading label describing the setting
/// and a trailing control. Buttons, pop-up buttons and the text field are stock
/// AppKit-backed controls at their `.small` size, so press feedback, keyboard
/// access and VoiceOver come from the platform. Switches and checkboxes use
/// `NotchToggleStyles`, which exists only because AppKit desaturates its own
/// controls on a panel that never takes key focus. See the HIG notes on
/// individual rows below.
struct InlineSettingsView: View {
    @ObservedObject var appSettings: AppSettings
    @ObservedObject var appState: AppState

    /// Set only once the field has been left with a bad value, so the pane
    /// doesn't scold anyone mid-keystroke. HIG > Text fields: "when entering an
    /// email address, it's best to validate when people switch to another
    /// field".
    @State private var urlIsInvalid = false
    @FocusState private var urlFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.settingsGroupSpacing) {
            Text("Settings")
                .font(Theme.settingsTitleFont)
                .foregroundColor(Theme.labelPrimary)

            accountSection
            notificationsSection
            generalSection
            syncSection
        }
    }

    // MARK: - Account

    private var accountSection: some View {
        let account = AccountRow(authStatus: appState.authStatus)
        return SettingsSection("Account") {
            SettingsRow(account.label, icon: account.icon, iconTint: account.tint) {
                Button(account.buttonTitle) { appState.showOnboarding = true }
                    .controlSize(.small)
            }
        }
    }

    // MARK: - Notifications

    /// The switch governs the two rows under it, which are indented and
    /// disabled together. HIG > Toggles > Checkboxes: alignment and indentation
    /// are how you "show dependencies, such as when the state of a checkbox
    /// governs the state of subordinate checkboxes".
    private var notificationsSection: some View {
        SettingsSection("Notifications") {
            SettingsRow("Usage alerts") {
                Toggle("", isOn: $appSettings.notificationsEnabled)
                    .toggleStyle(.notchSwitch)
                    .labelsHidden()
                    .accessibilityLabel("Usage alerts")
            }

            Group {
                SettingsRow("Alert at", indented: true) {
                    thresholdCheckboxes
                }

                SettingsRow("Test notification", indented: true) {
                    Button("Send") { NotificationService.shared.sendTest() }
                        .controlSize(.small)
                }
            }
            .disabled(!appSettings.notificationsEnabled)
        }
    }

    /// Multi-select, so checkboxes — HIG > Toggles > Radio buttons: "If you
    /// need to let people choose multiple options in a set, use checkboxes
    /// instead." Each gets the same fixed width so the column of boxes aligns.
    private var thresholdCheckboxes: some View {
        HStack(spacing: 0) {
            ForEach(AppSettings.availableThresholds, id: \.self) { threshold in
                Toggle(isOn: thresholdBinding(threshold)) {
                    // Locale percent formatting can carry a space ("100 %"),
                    // which is wide enough to wrap inside the fixed slot.
                    Text(threshold.formatted(.percent))
                        .font(Theme.settingsRowFont)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .toggleStyle(.notchCheckbox)
                .frame(width: Theme.settingsCheckboxWidth, alignment: .leading)
            }
        }
    }

    // MARK: - General

    private var generalSection: some View {
        SettingsSection("General") {
            SettingsRow("Launch at login") {
                Toggle("", isOn: $appSettings.launchAtLogin)
                    .toggleStyle(.notchSwitch)
                    .labelsHidden()
                    .accessibilityLabel("Launch at login")
            }

            SettingsRow("Agent status glow",
                        caption: "Pulse the notch when a session is working or needs input") {
                Toggle("", isOn: $appSettings.showAgentStatusPulse)
                    .toggleStyle(.notchSwitch)
                    .labelsHidden()
                    .accessibilityLabel("Agent status glow")
            }

            SettingsRow("Check usage every") {
                intervalPicker(selection: $appSettings.pollIntervalSeconds,
                               accessibilityLabel: "Check usage every")
            }
        }
    }

    // MARK: - Sync server

    private var syncSection: some View {
        SettingsSection("Sync server", footer: syncFooter) {
            SettingsRow("Address") {
                TextField("http://host:5014", text: $appSettings.apiBaseURL)
                    .textFieldStyle(.roundedBorder)
                    .font(Theme.settingsRowFont)
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                    .focused($urlFieldFocused)
                    .onSubmit { validateURL() }
                    .onChange(of: urlFieldFocused) { _, focused in
                        if focused { urlIsInvalid = false } else { validateURL() }
                    }
                    .accessibilityLabel("Sync server address")
            }

            SettingsRow("Upload every") {
                intervalPicker(selection: $appSettings.syncIntervalSeconds,
                               accessibilityLabel: "Upload every")
            }
            .disabled(syncDisabled)
        }
    }

    /// Validation message below the group rather than crammed beside the field —
    /// HIG > Pop-up buttons: "You can also display explanatory text below the
    /// list to help people understand how the options work."
    private var syncFooter: String? {
        urlIsInvalid ? "Enter a full address including http:// or https://." : nil
    }

    // MARK: - Interval pop-up buttons

    /// A flat list of mutually exclusive values in a tight pane is the pop-up
    /// button's job, not the segmented control's — HIG > Pop-up buttons: "Use a
    /// pop-up button to present a flat list of mutually exclusive options or
    /// states… Consider using a pop-up button when space is limited". It also
    /// lifts the cap of three choices the old segmented control imposed, which
    /// HIG > Segmented controls would have made awkward past ~5 segments.
    private func intervalPicker(selection: Binding<TimeInterval>,
                                accessibilityLabel: String) -> some View {
        Picker("", selection: selection) {
            ForEach(Self.intervalChoices(including: selection.wrappedValue), id: \.self) { seconds in
                Text(Self.intervalLabel(seconds)).tag(seconds)
            }
        }
        .pickerStyle(.menu)
        .controlSize(.small)
        .labelsHidden()
        .frame(width: Theme.settingsControlWidth)
        .accessibilityLabel(accessibilityLabel)
    }

    private static let intervalMinutes: [Int] = [1, 2, 5, 10, 15, 30, 60]

    /// A value persisted before this list existed would otherwise select no
    /// menu item and render the pop-up button blank, so it's folded in.
    private static func intervalChoices(including current: TimeInterval) -> [TimeInterval] {
        let known = intervalMinutes.map { TimeInterval($0 * 60) }
        guard !known.contains(current) else { return known }
        return (known + [current]).sorted()
    }

    private static let intervalFormatter: DateComponentsFormatter = {
        let f = DateComponentsFormatter()
        f.unitsStyle = .short
        f.allowedUnits = [.hour, .minute]
        return f
    }()

    private static func intervalLabel(_ seconds: TimeInterval) -> String {
        intervalFormatter.string(from: seconds) ?? "\(Int(seconds / 60)) min"
    }

    // MARK: - Thresholds

    /// Kept sorted on write so the stored order matches the order
    /// `NotificationService.evaluate` walks and the order shown here.
    private func thresholdBinding(_ threshold: Double) -> Binding<Bool> {
        Binding(
            get: { appSettings.thresholds.contains(threshold) },
            set: { isOn in
                var next = appSettings.thresholds.filter { $0 != threshold }
                if isOn { next.append(threshold) }
                appSettings.thresholds = next.sorted()
            }
        )
    }

    // MARK: - Account state

    private var syncDisabled: Bool {
        appSettings.apiBaseURL.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// An empty address is valid — it's how sync is switched off.
    private func validateURL() {
        let trimmed = appSettings.apiBaseURL.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            urlIsInvalid = false
            return
        }
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty
        else {
            urlIsInvalid = true
            return
        }
        urlIsInvalid = false
    }

}

// MARK: - Account row content

/// How one auth state presents in the Account row. One switch rather than four
/// parallel ones, so a new `AuthStatus` case can't pick up a label without a
/// matching symbol and tint.
///
/// The symbol accompanies the tint because HIG > Toggles warns against relying
/// "solely on different colors to communicate state" — the same reasoning
/// applies to a status indicator.
private struct AccountRow {
    let label: String
    let icon: String
    let tint: Color
    let buttonTitle: String

    init(authStatus: AuthStatus) {
        switch authStatus {
        case .valid:
            label = "Connected"
            icon = "checkmark.circle.fill"
            tint = Theme.statusHealthy
            buttonTitle = "Reconnect"
        case .expired:
            label = "Credentials expired"
            icon = "exclamationmark.triangle.fill"
            tint = Theme.statusWarning
            buttonTitle = "Sign In"
        case .notConfigured:
            label = "Not signed in"
            icon = "person.crop.circle.badge.questionmark"
            tint = Theme.statusUnknown
            buttonTitle = "Sign In"
        }
    }
}

// MARK: - Grouped form primitives

/// A sentence-case header over a group of rows, with optional explanatory text
/// below. Grouping is carried by negative space alone — no box, fill or
/// separators. HIG > Layout: "you might use negative space, background shapes,
/// colors, materials, or separator lines to show when elements are related and
/// to separate information into distinct areas."
private struct SettingsSection<Content: View>: View {
    let title: String
    /// Validation message shown under the group. Nil when the group is valid.
    var footer: String?
    @ViewBuilder let content: () -> Content

    init(_ title: String,
         footer: String? = nil,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Theme.settingsSectionFont)
                .foregroundColor(Theme.labelSecondary)

            VStack(alignment: .leading, spacing: 0) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)

            if let footer {
                Text(footer)
                    .font(Theme.settingsCaptionFont)
                    .foregroundColor(Theme.statusWarning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// One row: leading label (plus optional caption), trailing control, uniform
/// minimum height. Reads `isEnabled` so a disabled row's own text drops to the
/// tertiary label color the HIG reserves for unavailable items, instead of the
/// caller hand-applying an opacity to every subview.
private struct SettingsRow<Control: View>: View {
    @Environment(\.isEnabled) private var isEnabled

    let title: String
    var caption: String?
    var icon: String?
    var iconTint: Color?
    var indented: Bool
    @ViewBuilder let control: () -> Control

    init(_ title: String,
         caption: String? = nil,
         icon: String? = nil,
         iconTint: Color? = nil,
         indented: Bool = false,
         @ViewBuilder control: @escaping () -> Control) {
        self.title = title
        self.caption = caption
        self.icon = icon
        self.iconTint = iconTint
        self.indented = indented
        self.control = control
    }

    var body: some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(isEnabled ? (iconTint ?? Theme.labelSecondary) : Theme.labelTertiary)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Theme.settingsRowFont)
                    .foregroundColor(isEnabled ? Theme.labelPrimary : Theme.labelTertiary)
                if let caption {
                    Text(caption)
                        .font(Theme.settingsCaptionFont)
                        .foregroundColor(isEnabled ? Theme.labelSecondary : Theme.labelTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            control()
        }
        .padding(.leading, indented ? Theme.settingsRowIndent : 0)
        .padding(.vertical, Theme.settingsRowPaddingV)
        .frame(minHeight: Theme.settingsRowMinHeight)
    }
}

