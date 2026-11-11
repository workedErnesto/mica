import AppKit
import SwiftUI

/// Field background and border. Tonal: field fill with a focus ring in the main colour, for settings rows and panels.
/// Prominent: the start page search field at field size, surface fill, hairline that strengthens on focus and a soft
/// shadow that grows with it, for the main input of a small form standing on the canvas.
struct FieldChrome: ViewModifier {
    var focused: Bool
    var prominent = false
    var radius: CGFloat = Radius.row
    @Environment(\.look) private var look
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                if prominent {
                    shape.fill(Palette.surface).shadow(color: focused ? Palette.shadowStrong : Palette.shadow, radius: focused ? 10 : 4, y: focused ? 3 : 1)
                } else {
                    shape.fill(Palette.field)
                }
            }
            .overlay {
                if prominent {
                    shape.strokeBorder(focused ? Palette.hairlineStrong : Palette.hairline, lineWidth: 1)
                } else {
                    shape.strokeBorder(focused ? look.primary : Palette.hairlineStrong, lineWidth: focused ? 1.5 : 1)
                }
            }
            .animation(prominent ? Motion.quick : Motion.hover, value: focused)
    }
}

struct MTextField: View {
    let placeholder: String
    @Binding var text: String
    var symbol: String?
    /// Search field look (surface, shadow, larger text) instead of the tonal field.
    var prominent = false
    /// Takes the focus when it appears, for the first field of a form in a popover.
    var autofocus = false
    var onSubmit: () -> Void = {}
    @FocusState private var focused: Bool
    @Environment(\.look) private var look
    var body: some View {
        let size: CGFloat = prominent ? 13.5 : 13
        HStack(spacing: Space.small) {
            if let symbol { Image(systemName: symbol).font(.system(size: 12, weight: .medium)).foregroundStyle(prominent ? Palette.text2 : Palette.text3) }
            // SwiftUI on macOS ignores the colour of a TextField prompt and uses the system placeholder colour, which
            // nearly disappears on tonal fills and popovers, so the placeholder is drawn here in text3.
            TextField("", text: $text).textFieldStyle(.plain).font(.system(size: size))
                .foregroundStyle(Palette.ink).tint(look.primary).focused($focused).onSubmit(onSubmit)
                .onExitCommand { focused = false }
                .background(alignment: .leading) {
                    if text.isEmpty {
                        Text(placeholder).font(.system(size: size)).foregroundStyle(Palette.text3).lineLimit(1)
                            .allowsHitTesting(false).accessibilityHidden(true).transition(.identity)
                    }
                }
                .accessibilityLabel(placeholder)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundStyle(Palette.text3) }
                    .buttonStyle(PressStyle(scale: 0.85)).transition(.opacity).accessibilityLabel(Store.shared.text("очистить", "Очистить"))
            }
        }
        .padding(.horizontal, prominent ? 12 : 10)
        .frame(height: prominent ? 36 : 32)
        .modifier(FieldChrome(focused: focused, prominent: prominent))
        .animation(Motion.hover, value: text.isEmpty)
        .onAppear { if autofocus { DispatchQueue.main.async { focused = true } } }
    }
}
