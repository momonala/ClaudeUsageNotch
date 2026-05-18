import SwiftUI

/// Five-step onboarding: Welcome → Provider → Cookie → Validate → Notifications.
struct OnboardingView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var step: Step = .welcome
    @State private var cookieInput: String = ""
    @State private var validating: Bool = false
    @State private var validateError: String?

    enum Step: Int, CaseIterable { case welcome, provider, cookie, validate, notifications }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 18) {
                HStack {
                    RetroMascot(size: 32)
                    Text("Welcome to Notchy Limit")
                        .font(Theme.displayFont)
                        .foregroundColor(Theme.textPrimary)
                    Spacer()
                    Button("Skip") { dismiss() }
                        .buttonStyle(.borderless)
                        .foregroundColor(Theme.textSecondary)
                }
                progressDots
                Group {
                    switch step {
                    case .welcome: welcomeStep
                    case .provider: providerStep
                    case .cookie: cookieStep
                    case .validate: validateStep
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
        VStack(alignment: .leading, spacing: 8) {
            Text("See your Claude limits at a glance.")
                .font(.title3.weight(.semibold))
                .foregroundColor(Theme.textPrimary)
            Text("A tiny pill lives in your notch. Hover for details. Everything stays on your Mac.")
                .font(Theme.bodyFont)
                .foregroundColor(Theme.textSecondary)
        }
    }

    private var providerStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose a provider")
                .font(.title3.weight(.semibold))
                .foregroundColor(Theme.textPrimary)
            ForEach(ProviderId.allCases, id: \.self) { p in
                HStack {
                    Text(p.displayName).foregroundColor(Theme.textPrimary)
                    Spacer()
                    Text(p.isAvailable ? "Available" : "Coming soon")
                        .font(Theme.captionFont)
                        .foregroundColor(p.isAvailable ? Theme.statusHealthy : Theme.textSecondary)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface))
                .opacity(p.isAvailable ? 1 : 0.6)
            }
        }
    }

    private var cookieStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Paste your claude.ai cookie")
                .font(.title3.weight(.semibold))
                .foregroundColor(Theme.textPrimary)
            Text("In claude.ai → DevTools → Network → 'usage' request → copy the full Cookie header.")
                .font(Theme.captionFont)
                .foregroundColor(Theme.textSecondary)
            TextEditor(text: $cookieInput)
                .font(.system(size: 11, design: .monospaced))
                .frame(height: 110)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface))
            if let err = validateError {
                Text(err).font(Theme.captionFont).foregroundColor(Theme.statusCritical)
            }
        }
    }

    private var validateStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(validating ? "Validating cookie…" : "Cookie validated ✓")
                .font(.title3.weight(.semibold))
                .foregroundColor(Theme.textPrimary)
            Text("We're checking that the cookie can reach the Claude usage endpoint.")
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
            Toggle("Alert me at 25/50/75/90% usage", isOn: $appState.notificationsEnabled)
                .toggleStyle(.switch)
                .foregroundColor(Theme.textPrimary)
            Text("You can change this any time from Settings.")
                .font(Theme.captionFont)
                .foregroundColor(Theme.textSecondary)
        }
    }

    private var navButtons: some View {
        HStack {
            if step != .welcome {
                Button("Back") { goBack() }.buttonStyle(.bordered)
            }
            Spacer()
            Button(primaryLabel) { goNext() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
                .disabled(step == .cookie && cookieInput.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private var primaryLabel: String {
        switch step {
        case .welcome:        return "Get started"
        case .provider:       return "Continue"
        case .cookie:         return "Validate"
        case .validate:       return validating ? "…" : "Continue"
        case .notifications:  return "Finish"
        }
    }

    private func goBack() {
        if let prev = Step(rawValue: step.rawValue - 1) { step = prev }
    }

    private func goNext() {
        switch step {
        case .cookie:
            startValidation()
        case .validate:
            if !validating && validateError == nil { step = .notifications }
        case .notifications:
            dismiss()
        default:
            if let next = Step(rawValue: step.rawValue + 1) { step = next }
        }
    }

    private func startValidation() {
        validateError = nil
        validating = true
        let credential = ClaudeCredential(cookie: cookieInput.trimmingCharacters(in: .whitespacesAndNewlines))
        AuthService.shared.saveClaudeCredential(credential)
        step = .validate
        Task {
            do {
                let provider = ProviderRegistry.shared.provider(for: .claude)!
                try await provider.validateCredentials()
                let snapshot = try await provider.fetchUsage()
                await MainActor.run {
                    appState.latestSnapshot = snapshot
                    appState.authStatus = .valid
                    (NSApp.delegate as? AppDelegate)?.coordinator?.onCredentialsSaved()
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
}
