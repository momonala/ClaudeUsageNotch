import SwiftUI
import AppKit

/// Multi-step onboarding for Claude.
///
/// If Claude CLI credentials are present on disk, the cookie step is skipped and OAuth is used automatically.
struct OnboardingView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var appSettings: AppSettings
    let onCredentialsSaved: () -> Void
    private func close() { appState.showOnboarding = false }

    @State private var step: Step = .welcome
    @State private var selectedProvider: ProviderId = .claude
    @State private var credentialInput: String = ""
    @State private var validating: Bool = false
    @State private var validateError: String?

    enum Step: Int, CaseIterable {
        case welcome, provider, credential, validate, notifications
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 18) {
                HStack {
                    RetroMascot(size: 32)
                    Text("Welcome to ClaudeUsageNotch")
                        .font(Theme.displayFont)
                        .foregroundColor(Theme.textPrimary)
                    Spacer()
                    Button("Skip") { close() }
                        .buttonStyle(.borderless)
                        .foregroundColor(Theme.textSecondary)
                }
                progressDots
                Group {
                    switch step {
                    case .welcome:       welcomeStep
                    case .provider:      providerStep
                    case .credential:    credentialStep
                    case .validate:      validateStep
                    case .notifications: notificationsStep
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
                navButtons
            }
            .padding(20)
        }
    }

    // MARK: - Step views

    private var progressDots: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases, id: \.self) { s in
                Circle()
                    .fill(s == step ? Theme.accentWarm : Theme.stroke)
                    .frame(width: 7, height: 7)
            }
        }
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("See your AI limits at a glance.")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(Theme.textPrimary)
                Text("A tiny pill lives in your notch or menu bar. Hover for details. Everything stays on your Mac.")
                    .font(Theme.bodyFont)
                    .foregroundColor(Theme.textSecondary)
            }
            pillPreviewCard
        }
    }

    private var providerStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose a provider")
                .font(.title3.weight(.semibold))
                .foregroundColor(Theme.textPrimary)
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(ProviderId.allCases, id: \.self) { p in
                        providerRow(p)
                    }
                }
            }
            .frame(maxHeight: 280)
        }
    }

    @ViewBuilder
    private func providerRow(_ p: ProviderId) -> some View {
        let isSelected = selectedProvider == p
        Button { selectedProvider = p } label: {
            HStack {
                ProviderIconView(id: p, size: 18, fallbackColor: isSelected ? Theme.accentWarm : Theme.textSecondary,
                                accessibilityLabel: p.displayName)
                    .frame(width: 22)
                Text(p.displayName)
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                if usesDetectedOAuth(p) {
                    Text("CLI detected")
                        .font(Theme.captionFont)
                        .foregroundColor(Theme.statusHealthy)
                } else if isSelected {
                    Text("Selected")
                        .font(Theme.captionFont)
                        .foregroundColor(Theme.textSecondary)
                }
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Theme.accentWarm)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Theme.surfaceElevated : Theme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(isSelected ? Theme.accentWarm.opacity(0.35) : Theme.stroke, lineWidth: 0.75)
                    )
            )
        }
        .buttonStyle(.borderless)
    }

    /// True when the provider is authenticated from a CLI-written OAuth file
    /// that's present on disk — no credential entry needed.
    private func usesDetectedOAuth(_ p: ProviderId) -> Bool {
        AuthService.shared.cliOAuthAvailable(for: p)
    }

    /// True when this step shows a key/cookie text field the user must fill.
    private func needsTextInput(_ p: ProviderId) -> Bool {
        !usesDetectedOAuth(p)
    }

    @ViewBuilder
    private var credentialStep: some View {
        if usesDetectedOAuth(.claude) { oauthDetectedStep }
        else { claudeCookieStep }
    }

    @ViewBuilder
    private var oauthDetectedStep: some View {
        let info = (tool: "Claude CLI", path: "~/.claude/credentials.json", scope: "Scoped OAuth token — not your full session cookie")
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 20))
                    .foregroundColor(Theme.statusHealthy)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(info.tool) detected")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(Theme.textPrimary)
                    Text("ClaudeUsageNotch will use your existing CLI credentials.")
                        .font(Theme.captionFont)
                        .foregroundColor(Theme.textSecondary)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Theme.statusHealthy.opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Theme.statusHealthy.opacity(0.25)))
            )

            VStack(alignment: .leading, spacing: 6) {
                featureRow("shield.fill", info.scope, Theme.statusHealthy)
                featureRow("key.fill", "Token lives in \(info.path)", Theme.textSecondary)
                featureRow("arrow.clockwise", "Auto-refreshed — no action needed", Theme.textSecondary)
            }
        }
    }

    private var claudeCookieStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Paste your claude.ai session cookie")
                .font(.title3.weight(.semibold))
                .foregroundColor(Theme.textPrimary)

            // Security disclosure — honest about the tradeoff
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(Theme.statusWarning)
                    .font(.system(size: 12))
                    .padding(.top, 1)
                Text("This is a full browser session cookie with complete account access. It stays device-only in the macOS Keychain and is never sent anywhere except directly to claude.ai for usage requests. Install Claude CLI to use a safer, scoped token instead.")
                    .font(Theme.captionFont)
                    .foregroundColor(Theme.textSecondary)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.statusWarning.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Theme.statusWarning.opacity(0.20)))
            )

            Text("In claude.ai, open DevTools (⌘⌥I) → Network → find 'usage' request → copy the Cookie header.")
                .font(Theme.captionFont)
                .foregroundColor(Theme.textSecondary)

            SecureCookieEditor(text: $credentialInput)
                .frame(height: 90)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface))

            if let err = validateError {
                Text(err).font(Theme.captionFont).foregroundColor(Theme.statusCritical)
            }
        }
    }

    private var validateHeadline: String {
        if validating { return "Validating…" }
        if validateError != nil { return "Couldn't validate" }
        return "Credentials validated ✓"
    }

    private var validateStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(validateHeadline)
                .font(.title3.weight(.semibold))
                .foregroundColor(validateError == nil ? Theme.textPrimary : Theme.statusCritical)
            Text("Checking that the credentials can reach \(selectedProvider.displayName)'s usage endpoint.")
                .font(Theme.captionFont)
                .foregroundColor(Theme.textSecondary)
            if let err = validateError {
                Text(err).font(Theme.captionFont).foregroundColor(Theme.statusCritical)
            }
        }
    }

    private var notificationsStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notifications")
                .font(.title3.weight(.semibold))
                .foregroundColor(Theme.textPrimary)
            Toggle("Alert me at 25/50/75/90% usage", isOn: $appSettings.notificationsEnabled)
                .toggleStyle(.switch)
                .foregroundColor(Theme.textPrimary)
            Text("You can change this any time from Settings.")
                .font(Theme.captionFont)
                .foregroundColor(Theme.textSecondary)
        }
    }

    // MARK: - Navigation

    private var navButtons: some View {
        HStack {
            if step != .welcome {
                Button("Back") { goBack() }.buttonStyle(.bordered)
            }
            Spacer()
            Button(primaryLabel) { goNext() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
                .disabled(nextDisabled)
        }
    }

    private var primaryLabel: String {
        switch step {
        case .welcome:        return "Get started"
        case .provider:       return "Continue"
        case .credential:
            return usesDetectedOAuth(selectedProvider) ? "Continue" : "Validate"
        case .validate:       return validating ? "…" : "Continue"
        case .notifications:  return "Finish"
        }
    }

    private var nextDisabled: Bool {
        switch step {
        case .credential:
            return needsTextInput(selectedProvider) && credentialInput.trimmingCharacters(in: .whitespaces).isEmpty
        case .validate:
            return validating
        default:
            return false
        }
    }

    private func goBack() {
        if let prev = Step(rawValue: step.rawValue - 1) { step = prev }
    }

    private func goNext() {
        switch step {
        case .credential:
            startValidation()
        case .validate:
            if !validating && validateError == nil { step = .notifications }
        case .notifications:
            close()
        default:
            if let next = Step(rawValue: step.rawValue + 1) { step = next }
        }
    }

    private func startValidation() {
        validateError = nil
        validating = true

        // Save credential before validating (only providers with a text field).
        if needsTextInput(selectedProvider) {
            if let saveError = saveCredential() {
                validateError = saveError
                validating = false
                return
            }
        }

        step = .validate

        Task {
            do {
                let provider = ClaudeProvider()
                try await provider.validateCredentials()
                let snapshot = try await provider.fetchUsage()
                await MainActor.run {
                    appState.snapshots[selectedProvider] = snapshot
                    appState.authStatus = .valid
                    onCredentialsSaved()
                    validating = false
                }
            } catch let err as ProviderError {
                await MainActor.run {
                    validateError = err.description
                    validating = false
                }
            } catch {
                await MainActor.run {
                    validateError = error.localizedDescription
                    validating = false
                }
            }
        }
    }

    private func saveCredential() -> String? {
        let trimmed = credentialInput.trimmingCharacters(in: .whitespacesAndNewlines)
        return AuthService.shared.saveClaudeCredential(ClaudeCredential(cookie: trimmed))
    }

    // MARK: - Helper sub-views

    @ViewBuilder
    private func featureRow(_ icon: String, _ text: String, _ color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 18)
            Text(text)
                .font(Theme.captionFont)
                .foregroundColor(Theme.textSecondary)
        }
    }

    private var pillPreviewCard: some View {
        VStack(spacing: 8) {
            Text("This will live in your notch or menu bar:")
                .font(Theme.captionFont)
                .foregroundColor(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.black)
                        .frame(width: 130, height: 22)
                        .overlay(
                            Text("camera")
                                .font(.system(size: 7))
                                .foregroundColor(Color.white.opacity(0.15))
                        )
                    OnboardingPillPreview()
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            Text("Hover to expand. Click to pin.")
                .font(Theme.captionFont)
                .foregroundColor(Theme.textSecondary.opacity(0.6))
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.surface)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.stroke))
        )
    }
}

// MARK: - Secure text editor (handles both cookie and API key)

private struct SecureCookieEditor: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""
    private static let maxLength = 65_536

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let tv = scrollView.documentView as? NSTextView else { return scrollView }
        tv.isAutomaticSpellingCorrectionEnabled  = false
        tv.isAutomaticDataDetectionEnabled       = false
        tv.isAutomaticLinkDetectionEnabled       = false
        tv.isAutomaticTextReplacementEnabled     = false
        tv.isAutomaticQuoteSubstitutionEnabled   = false
        tv.isAutomaticDashSubstitutionEnabled    = false
        tv.isContinuousSpellCheckingEnabled      = false
        tv.isGrammarCheckingEnabled              = false
        tv.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        tv.textColor = NSColor.white.withAlphaComponent(0.88)
        tv.backgroundColor = .clear
        tv.drawsBackground = false
        tv.delegate = context.coordinator
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tv = scrollView.documentView as? NSTextView else { return }
        if tv.string != text { tv.string = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SecureCookieEditor
        init(_ parent: SecureCookieEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            if tv.string.count > SecureCookieEditor.maxLength {
                tv.string = String(tv.string.prefix(SecureCookieEditor.maxLength))
            }
            parent.text = tv.string
        }
    }
}

// MARK: - Animated pill preview (same as original)

private struct OnboardingPillPreview: View {
    @State private var demoPercent: Double = 0.42
    private let demoValues: [Double] = [0.42, 0.71, 0.88, 0.42]
    @State private var demoIndex = 0

    var body: some View {
        let status: UsageStatus = demoPercent >= 0.9 ? .critical : demoPercent >= 0.7 ? .warning : .healthy
        let color = status.color

        HStack(spacing: 7) {
            Circle().fill(color).frame(width: 5, height: 5)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(color)
                    .frame(width: max(4, CGFloat(demoPercent) * 80))
            }
            .frame(width: 80, height: 3)
            Text("\(Int((demoPercent * 100).rounded()))%")
                .font(Theme.notchFont)
                .foregroundColor(Theme.textLabel)
                .frame(minWidth: 25, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .frame(width: 220, height: 22)
        .background(NotchPillShape(topRadius: 0, bottomRadius: 12).fill(Color.black))
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { break }
                demoIndex = (demoIndex + 1) % demoValues.count
                withAnimation(.spring(response: Theme.springResponse, dampingFraction: Theme.springDamping)) {
                    demoPercent = demoValues[demoIndex]
                }
            }
        }
    }
}
