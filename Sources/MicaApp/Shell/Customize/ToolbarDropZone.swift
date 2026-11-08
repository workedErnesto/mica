import AppKit
import SwiftUI
import MicaCore

/// One area that accepts controls: a side of the top bar or the bottom of the sidebar.
struct ToolbarDropZone: View {
    let zone: ToolbarZone
    let items: [ToolbarControl]
    @ObservedObject var store: Store
    let layout: TabLayout
    var vertical = false
    var alignment: Alignment = .leading
    var minWidth: CGFloat = 64
    @State private var targeted = false
    var body: some View {
        let moves = ToolbarMoves(store: store)
        let tiles = ForEach(items, id: \.self) { ToolbarEditTile(item: $0, store: store, layout: layout).transition(Motion.pop) }
        SwiftUI.Group {
            if vertical { VStack(spacing: 2) { tiles } } else { HStack(spacing: 2) { tiles } }
        }
        .padding(2)
        .frame(minWidth: vertical ? 36 : minWidth, maxWidth: vertical ? nil : .infinity, minHeight: 32, alignment: alignment)
        .background {
            RoundedRectangle(cornerRadius: Radius.icon + 2, style: .continuous)
                .fill(targeted ? Palette.hover : .clear)
            RoundedRectangle(cornerRadius: Radius.icon + 2, style: .continuous)
                .strokeBorder(targeted ? Palette.focusRing : Palette.hairlineStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { payloads, _ in
            guard let dragged = payloads.first.flatMap(ToolbarDrag.item) else { return false }
            moves.append(dragged, to: zone, layout: layout)
            return true
        } isTargeted: { targeted = $0 }
        .animation(Motion.quick, value: items)
        .animation(Motion.hover, value: targeted)
        .help(zone.title(store))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(zone.title(store))
    }
}
