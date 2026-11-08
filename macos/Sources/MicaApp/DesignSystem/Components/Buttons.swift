import AppKit
import SwiftUI

enum ButtonKind { case primary, secondary, ghost, destructive }

struct MButtonStyle: ButtonStyle {
    var kind: ButtonKind = .secondary
    var compact = false
    var fill = false
    func makeBody(configuration: Configuration) -> some View { MButtonBody(configuration: configuration, kind: kind, compact: compact, fill: fill) }
}

private struct MButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: ButtonKind
    let compact: Bool
    let fill: Bool
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.look) private var look
    @State private var hover = false
    var body: some View {
        let pressed = configuration.isPressed
        // Filled rounded rectangles: an outline pill read as a placeholder control next to the grouped settings.
        let shape = RoundedRectangle(cornerRadius: compact ? Radius.icon - 1 : Radius.icon, style: .continuous)
        configuration.label
            .font(.system(size: compact ? 12 : 13, weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, compact ? 10 : 14)
            .frame(maxWidth: fill ? .infinity : nil)
            .frame(height: compact ? 26 : 32)
            .foregroundStyle(foreground)
            .background(shape.fill(background(pressed)))
            .contentShape(shape)
            .scaleEffect(pressed && !reduced ? 0.965 : 1)
            .opacity(enabled ? 1 : 0.42)
            .onHover { hover = $0 && enabled }
            .animation(Motion.hover, value: hover)
            .animation(reduced ? nil : Motion.pressSpring, value: pressed)
    }
    private var foreground: Color {
        switch kind { case .primary: return look.onPrimary; case .destructive: return Palette.danger; default: return Palette.ink }
    }
    private func background(_ pressed: Bool) -> Color {
        switch kind {
        case .primary: return look.accent.map { pressed ? $0.mix(with: .black, by: 0.18) : $0.opacity(hover ? 0.88 : 1) } ?? (pressed ? Palette.primaryPressed : Palette.primary.opacity(hover ? 0.86 : 1))
        case .secondary: return pressed ? Palette.secondaryPressed : hover ? Palette.secondaryHover : Palette.secondary
        case .ghost: return pressed ? Palette.pressed : hover ? Palette.hover : .clear
        case .destructive: return Palette.danger.opacity(pressed ? 0.2 : hover ? 0.15 : 0.1)
        }
    }
}

/// Plain press feedback for custom rows and tiles that draw their own resting and hover states.
struct PressStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    func makeBody(configuration: Configuration) -> some View { PressBody(configuration: configuration, scale: scale) }
}

private struct PressBody: View {
    let configuration: ButtonStyleConfiguration
    let scale: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduced ? scale : 1)
            .animation(reduced ? nil : Motion.pressSpring, value: configuration.isPressed)
    }
}

struct IconButton: View {
    let symbol: String
    let label: String
    var selected = false
    var size: CGFloat = 28
    var action: () -> Void
    @Environment(\.isEnabled) private var enabled
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Glyph(name: symbol, size: size * 0.48)
                .foregroundStyle(enabled ? (selected || hover ? Palette.ink : Palette.text2) : Palette.text3.opacity(0.6))
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: Radius.icon, style: .continuous).fill(selected ? Palette.pressed : hover ? Palette.hover : .clear))
                .contentShape(RoundedRectangle(cornerRadius: Radius.icon, style: .continuous))
        }
        .buttonStyle(PressStyle(scale: 0.9))
        .onHover { hover = $0 && enabled }
        .animation(Motion.hover, value: hover)
        .animation(Motion.hover, value: selected)
        .help(label).accessibilityLabel(label)
    }
}
