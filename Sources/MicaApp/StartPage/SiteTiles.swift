import AppKit
import SwiftUI
import WebKit
import MicaCore
import UniformTypeIdentifiers

/// Custom sites reorder by dragging one tile onto another.
struct ShortcutDrag: ViewModifier {
    let site: StartSite
    @ObservedObject var store: Store
    func body(content: Content) -> some View {
        if let id = site.shortcut {
            content
                .onDrag { NSItemProvider(object: ("mica-shortcut:" + id.uuidString) as NSString) }
                .onDrop(of: [.text], isTargeted: nil) { providers in
                    guard let provider = providers.first else { return false }
                    _ = provider.loadObject(ofClass: String.self) { string, _ in
                        guard let string, string.hasPrefix("mica-shortcut:"), let source = UUID(uuidString: String(string.dropFirst("mica-shortcut:".count))) else { return }
                        Task { @MainActor in withMotion(Motion.quick) { store.preferences.start.moveShortcut(source, before: id) } }
                    }
                    return true
                }
        } else { content }
    }
}

struct SiteTile: View {
    let title: String
    let host: String
    let action: () -> Void
    @State private var hover = false
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        Button(action: action) {
            VStack(spacing: Space.small) {
                Monogram(host: host, size: 30)
                    .modifier(TileBox(hover: hover))
                Text(label).font(.system(size: 11.5)).foregroundStyle(hover ? Palette.ink : Palette.text2).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.95))
        .onHover { hover = $0 }
        .animation(reduced ? Motion.hover : Motion.snappySpring, value: hover)
        .help(host)
        .accessibilityLabel(label)
    }
    private var label: String { title.isEmpty ? (host.hasPrefix("www.") ? String(host.dropFirst(4)) : host) : title }
}

/// 60 pt tile shared by site tiles and the add tile, so both line up in the grid.
struct TileBox: ViewModifier {
    let hover: Bool
    var dashed = false
    @Environment(\.accessibilityReduceMotion) private var reduced
    func body(content: Content) -> some View {
        content
            .frame(width: 60, height: 60)
            .background(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous).fill(dashed ? (hover ? Palette.hover : .clear) : Palette.surface).shadow(color: dashed ? .clear : hover ? Palette.shadowStrong : Palette.shadow, radius: hover ? 10 : 3, y: hover ? 4 : 1))
            .overlay(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous).strokeBorder(dashed ? Palette.hairlineStrong : Palette.hairline, style: StrokeStyle(lineWidth: 1, dash: dashed ? [4, 3] : [])))
            .offset(y: hover && !reduced ? -2 : 0)
    }
}

struct AddShortcutTile: View {
    @ObservedObject var store: Store
    @State private var hover = false
    @State private var adding = false
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        Button { adding = true } label: {
            VStack(spacing: Space.small) {
                Image(systemName: "plus").font(.system(size: 16, weight: .regular)).foregroundStyle(hover ? Palette.ink : Palette.text2)
                    .modifier(TileBox(hover: hover, dashed: true))
                Text(store.text("добавить", "Добавить")).font(.system(size: 11.5)).foregroundStyle(hover ? Palette.ink : Palette.text3).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.95))
        .onHover { hover = $0 }
        .animation(reduced ? Motion.hover : Motion.snappySpring, value: hover)
        .popover(isPresented: $adding, arrowEdge: .bottom) { ShortcutEditor(store: store, editing: nil) { adding = false } }
        .accessibilityLabel(store.text("добавить сайт на начальную страницу", "Добавить сайт на начальную страницу"))
    }
}
