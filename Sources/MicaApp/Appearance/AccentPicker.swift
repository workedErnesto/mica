import AppKit
import SwiftUI
import ImageIO
import MicaCore

/// Preset accents plus the system colour panel for anything else; every change applies immediately.
struct AccentPicker: View {
    @ObservedObject var store: Store
    static let presets = ["#6E56CF", "#3E7BFA", "#1F9D8B", "#3FA34D", "#E8A33D", "#E5484D", "#D6409F", "#8D7B6A"]
    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            ForEach(Self.presets, id: \.self) { hex in Swatch(hex: hex, store: store) }
            ColorPicker(store.text("другой цвет", "Другой цвет"), selection: Binding(get: {
                let c = HexColor.parse(store.preferences.accent) ?? (0.43, 0.34, 0.81)
                return Color(.sRGB, red: c.red, green: c.green, blue: c.blue)
            }, set: { color in
                guard let c = NSColor(color).usingColorSpace(.sRGB) else { return }
                store.preferences.accent = HexColor.string(red: c.redComponent, green: c.greenComponent, blue: c.blueComponent)
            }), supportsOpacity: false)
            .labelsHidden()
            .frame(width: 40, height: 22)
            .fixedSize()
            .help(store.text("другой цвет", "Другой цвет"))
            Text(store.preferences.accent).font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.text3).textSelection(.enabled)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(store.text("акцентный цвет", "Акцентный цвет"))
    }
}

private struct Swatch: View {
    let hex: String
    @ObservedObject var store: Store
    @State private var hover = false
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        let selected = store.preferences.accent.uppercased() == hex
        let c = HexColor.parse(hex)!
        Button { withMotion(Motion.quick) { store.preferences.accent = hex } } label: {
            Circle().fill(Color(.sRGB, red: c.red, green: c.green, blue: c.blue))
                .frame(width: 20, height: 20)
                .padding(3)
                .overlay(Circle().strokeBorder(selected ? Palette.ink : hover ? Palette.hairlineStrong : .clear, lineWidth: 1.5))
                .scaleEffect(hover && !reduced ? 1.08 : 1)
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle(scale: 0.88))
        .onHover { hover = $0 }
        .animation(Motion.hover, value: hover)
        .animation(Motion.hover, value: selected)
        .help(hex).accessibilityLabel(hex).accessibilityAddTraits(selected ? .isSelected : [])
    }
}
