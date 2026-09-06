import SwiftUI

/// Switch and checkbox styles for the notch panel.
///
/// The panel never takes key focus, and AppKit draws controls in their *inactive*
/// appearance whenever their window isn't key — a stock `.switch` renders its "on"
/// track desaturated, and `.tint` can't override it. These reproduce the intended
/// appearance, pinned to the accent and the panel's dark surface. Both wrap their
/// content in a `Button` so hit testing, keyboard activation and press feedback
/// stay the platform's.

// MARK: - Switch

struct NotchSwitchStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 6) {
                configuration.label
                track(isOn: configuration.isOn)
            }
        }
        .buttonStyle(PressableToggleButtonStyle())
    }

    private func track(isOn: Bool) -> some View {
        let size = Theme.switchTrackSize
        let knob = size.height - Theme.switchKnobInset * 2

        return Capsule()
            .fill(trackFill(isOn: isOn))
            .overlay(
                Capsule().strokeBorder(isOn ? .clear : Theme.toggleOffStroke, lineWidth: Theme.cardStrokeWidth)
            )
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(isEnabled ? Color.white : Theme.toggleDisabledKnob)
                    .frame(width: knob, height: knob)
                    .shadow(color: .black.opacity(0.28), radius: Theme.switchKnobShadow, y: 0.5)
                    .padding(Theme.switchKnobInset)
            }
            .frame(width: size.width, height: size.height)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: isOn)
    }

    private func trackFill(isOn: Bool) -> Color {
        guard isEnabled else { return isOn ? Theme.toggleDisabledOnFill : Theme.toggleDisabledOffFill }
        return isOn ? Theme.accentWarm : Theme.toggleOffFill
    }
}

// MARK: - Checkbox

struct NotchCheckboxStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 5) {
                box(isOn: configuration.isOn)
                configuration.label
            }
        }
        .buttonStyle(PressableToggleButtonStyle())
    }

    private func box(isOn: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.checkboxRadius, style: .continuous)

        return shape
            .fill(boxFill(isOn: isOn))
            .overlay(
                shape.strokeBorder(isOn ? .clear : Theme.toggleOffStroke, lineWidth: Theme.cardStrokeWidth)
            )
            // The checkmark carries the state, so "on" never rests on colour
            // alone (HIG > Toggles).
            .overlay {
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: Theme.checkmarkSize, weight: .bold))
                        .foregroundColor(isEnabled ? .white : Theme.toggleDisabledKnob)
                }
            }
            .frame(width: Theme.checkboxSize, height: Theme.checkboxSize)
    }

    private func boxFill(isOn: Bool) -> Color {
        guard isEnabled else { return isOn ? Theme.toggleDisabledOnFill : Theme.toggleDisabledOffFill }
        return isOn ? Theme.accentWarm : Theme.toggleOffFill
    }
}

// MARK: - Shared press feedback

/// Borderless button that dips slightly while held. `.plain` alone gives no
/// visible press state on a custom label.
private struct PressableToggleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? Theme.togglePressedScale : 1)
            .animation(.spring(response: 0.18, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

extension ToggleStyle where Self == NotchSwitchStyle {
    static var notchSwitch: NotchSwitchStyle { NotchSwitchStyle() }
}

extension ToggleStyle where Self == NotchCheckboxStyle {
    static var notchCheckbox: NotchCheckboxStyle { NotchCheckboxStyle() }
}
