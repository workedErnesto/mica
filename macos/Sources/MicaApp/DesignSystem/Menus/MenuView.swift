import AppKit
import SwiftUI
import MicaCore

struct MenuView: View {
    @ObservedObject var model: MenuModel
    let choose: (Int) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        let symbols = model.entries.contains { $0.symbol != nil || $0.profile != nil }
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(model.entries.enumerated()), id: \.element.id) { index, entry in
                if entry.kind == .divider {
                    Rectangle().fill(Palette.hairline).frame(height: 1).padding(.vertical, 4).padding(.horizontal, 8)
                } else {
                    MenuRow(entry: entry, highlighted: model.highlighted == index, symbols: symbols) { choose(index) }
                        .onHover { inside in
                            if inside { model.highlighted = entry.enabled ? index : nil } else if model.highlighted == index { model.highlighted = nil }
                        }
                }
            }
        }
        .padding(5)
        .frame(minWidth: 196, alignment: .leading)
        .fixedSize()
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.raised))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
        // The blur of a SwiftUI shadow reaches about twice its radius; with radius 8 and offset 3 it fades out inside
        // MicaMenu.margin, so the edge of the menu window never cuts it into a visible box.
        .shadow(color: Palette.menuShadow, radius: 8, y: 3)
        .scaleEffect(model.shown || reduced ? 1 : 0.95, anchor: model.anchor)
        .opacity(model.shown ? 1 : 0)
        .padding(MicaMenu.margin)
        .animation(Motion.hover, value: model.highlighted)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}

private struct MenuRow: View {
    let entry: MenuEntry
    let highlighted: Bool
    let symbols: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if symbols {
                    if let profile = entry.profile { ProfileMark(profile: profile, size: 16) }
                    else if let symbol = entry.symbol { Glyph(name: symbol, size: 12).frame(width: 16) }
                    else { Color.clear.frame(width: 16, height: 1) }
                }
                Text(entry.title).font(.system(size: 13)).lineLimit(1).fixedSize()
                if entry.checked {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold))
                }
                Spacer(minLength: 0)
                if !entry.submenu.isEmpty {
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.text3)
                }
            }
            .foregroundStyle(!entry.enabled ? Palette.text3.opacity(0.7) : entry.destructive ? Palette.danger : Palette.ink)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(highlighted && entry.enabled ? Palette.pressed : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!entry.enabled)
        .accessibilityLabel(entry.title)
        .accessibilityAddTraits(entry.checked ? .isSelected : [])
    }
}
