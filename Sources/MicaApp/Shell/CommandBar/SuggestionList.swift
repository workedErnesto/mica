import AppKit
import SwiftUI
import WebKit
import MicaCore
import UniformTypeIdentifiers

struct SuggestionList: View {
    let items: [Suggestion]
    @Binding var highlighted: Int
    let choose: (Suggestion) -> Void
    var body: some View {
        VStack(spacing: 2) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                Button { choose(item) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.symbol).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.text2).frame(width: 22, height: 22)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Palette.track))
                        Text(item.title).font(.system(size: 13)).foregroundStyle(Palette.ink).lineLimit(1).truncationMode(.middle)
                        Text(item.detail).font(.system(size: 12)).foregroundStyle(Palette.text3).lineLimit(1)
                        Spacer(minLength: 0)
                        if index == highlighted { Image(systemName: "return").font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.text3) }
                    }
                    .padding(.horizontal, 8).frame(height: 34)
                    .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(index == highlighted ? Palette.hover : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle(scale: 0.99))
                .onHover { if $0 { highlighted = index } }
            }
        }
        .animation(Motion.hover, value: highlighted)
    }
}

/// Keyboard handling shared by the floating command bar and the start page field.
struct SuggestionKeys: ViewModifier {
    let count: Int
    @Binding var highlighted: Int
    func body(content: Content) -> some View {
        content
            .onKeyPress(.downArrow) { guard count > 0 else { return .ignored }; highlighted = min(count - 1, highlighted + 1); return .handled }
            .onKeyPress(.upArrow) { guard count > 0 else { return .ignored }; highlighted = max(0, highlighted - 1); return .handled }
    }
}
