import AppKit
import SwiftUI

struct MToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: Space.normal) {
            configuration.label.frame(maxWidth: .infinity, alignment: .leading)
            SwitchKnob(isOn: configuration.$isOn)
        }
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }
}

struct SwitchKnob: View {
    @Binding var isOn: Bool
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.look) private var look
    @State private var hover = false
    var body: some View {
        Button { withMotion(reduced ? nil : Motion.snappySpring) { isOn.toggle() } } label: { EmptyView() }
            .buttonStyle(KnobStyle(isOn: isOn, hover: hover, reduced: reduced, look: look))
            .onHover { hover = $0 && enabled }
            .opacity(enabled ? 1 : 0.45)
    }
}

private struct KnobStyle: ButtonStyle {
    let isOn: Bool
    let hover: Bool
    let reduced: Bool
    let look: Look
    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule(style: .continuous).fill(isOn ? look.primary : Palette.switchOff)
                .overlay(Capsule(style: .continuous).fill(Color.white.opacity(hover && !isOn ? 0.06 : 0)))
            Capsule(style: .continuous).fill(isOn ? look.onPrimary : Palette.knobOff)
                .shadow(color: Palette.shadowStrong, radius: 1.5, y: 1)
                .frame(width: pressed && !reduced ? 21 : 16, height: 16)
                .padding(2)
        }
        .frame(width: 36, height: 20)
        .contentShape(Capsule())
        .animation(reduced ? nil : Motion.snappySpring, value: isOn)
        .animation(reduced ? nil : Motion.pressSpring, value: pressed)
        .animation(Motion.hover, value: hover)
    }
}

/// A switch without a visible label, for rows that already name what it controls (start page blocks while
/// customizing). The label becomes the tooltip, and VoiceOver gets a standard Toggle with it.
struct BareSwitch: View {
    let label: String
    @Binding var isOn: Bool
    var body: some View {
        SwitchKnob(isOn: $isOn)
            .help(label)
            .accessibilityRepresentation { Toggle(label, isOn: $isOn) }
    }
}
