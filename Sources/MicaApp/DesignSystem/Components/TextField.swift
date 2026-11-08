import AppKit
import SwiftUI

struct FieldChrome: ViewModifier {
    var focused: Bool
    var radius: CGFloat = Radius.row
    @Environment(\.look) private var look
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(focused ? Palette.surface : Palette.track))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(focused ? look.focus : Palette.hairline, lineWidth: focused ? 1.5 : 1))
            .animation(Motion.hover, value: focused)
    }
}

struct MTextField: View {
    let placeholder: String
    @Binding var text: String
    var symbol: String?
    var onSubmit: () -> Void = {}
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: Space.small) {
            if let symbol { Image(systemName: symbol).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.text3) }
            TextField(placeholder, text: $text).textFieldStyle(.plain).font(.system(size: 13)).focused($focused).onSubmit(onSubmit)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundStyle(Palette.text3) }
                    .buttonStyle(PressStyle(scale: 0.85)).transition(.opacity).accessibilityLabel(Store.shared.text("очистить", "Очистить"))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .modifier(FieldChrome(focused: focused))
        .animation(Motion.hover, value: text.isEmpty)
    }
}
