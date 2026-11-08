import AppKit
import SwiftUI
import ImageIO
import MicaCore

struct IconPicker: View {
    @ObservedObject var store: Store
    var body: some View {
        VStack(alignment: .leading, spacing: Space.normal) {
            if !AppIcons.available {
                Text(store.text("в этой сборке нет набора иконок", "В этой сборке нет набора иконок")).font(.system(size: 12)).foregroundStyle(Palette.text3)
            } else {
                ForEach(AppIcons.sets) { set in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(store.text(set.low, set.regular)).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Palette.text3)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 46, maximum: 52), spacing: 6)], alignment: .leading, spacing: 6) {
                            ForEach(set.icons) { icon in IconChoice(id: icon.id, label: store.text(icon.low, icon.regular), store: store) }
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(store.text("иконка приложения", "Иконка приложения"))
    }
}

struct IconChoice: View {
    let id: String?
    let label: String
    @ObservedObject var store: Store
    @State private var hover = false
    @Environment(\.look) private var look
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        let selected = (store.preferences.appIcon ?? AppIcons.standard) == id
        Button {
            withMotion(Motion.quick) { store.preferences.appIcon = id == AppIcons.standard ? nil : id }
        } label: {
            SwiftUI.Group {
                if let image = AppIcons.thumbnail(id) { Image(nsImage: image).resizable().interpolation(.high) }
                else { RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Palette.track) }
            }
            .frame(width: 40, height: 40)
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(hover && !selected ? Palette.hover : .clear))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(selected ? look.focus : .clear, lineWidth: 2))
            .scaleEffect(hover && !reduced ? 1.04 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.92))
        .onHover { hover = $0 }
        .animation(Motion.hover, value: hover)
        .animation(Motion.hover, value: selected)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
