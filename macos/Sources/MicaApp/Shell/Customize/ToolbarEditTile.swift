import AppKit
import SwiftUI
import MicaCore

/// A control as it looks while customizing: same size as the live button, draggable, with an insertion caret
/// on its leading edge while another control hovers over it.
struct ToolbarEditTile: View {
    let item: ToolbarControl
    @ObservedObject var store: Store
    @ObservedObject var browser: BrowserModel
    let layout: TabLayout
    @State private var targeted = false
    @State private var hover = false
    @Environment(\.look) private var look
    var body: some View {
        let moves = ToolbarMoves(store: store, browser: browser)
        Glyph(name: item == .sidebar && layout == .right ? "sidebar.right" : item.symbol, size: 13.5)
            .foregroundStyle(Palette.ink)
            .frame(width: 28, height: 28)
            .background(RoundedRectangle(cornerRadius: Radius.icon, style: .continuous).fill(hover ? Palette.pressed : Palette.hover))
            .overlay(alignment: .leading) {
                Capsule().fill(look.focus).frame(width: 2, height: 22).offset(x: -2).opacity(targeted ? 1 : 0)
            }
            .contentShape(RoundedRectangle(cornerRadius: Radius.icon, style: .continuous))
            .onHover { hover = $0 }
            // The top bar lies in the title bar band, where SwiftUI drags never start; an AppKit source does.
            .overlay { TitlebarDragSource(payload: ToolbarDrag.payload(item)) { moves.menu(item, layout: layout) } }
            .dropDestination(for: String.self) { payloads, _ in
                guard let dragged = payloads.first.flatMap(ToolbarDrag.item), dragged != item else { return false }
                moves.move(dragged, to: browser.prefs.toolbar.zone(of: item), before: item)
                return true
            } isTargeted: { targeted = $0 }
            .animation(Motion.hover, value: targeted)
            .animation(Motion.hover, value: hover)
            .help(item.title(store))
            .accessibilityElement()
            .accessibilityLabel(item.title(store))
            .accessibilityHint(store.text("перетащите или откройте меню действий", "Перетащите или откройте меню действий"))
            .accessibilityAction(named: ToolbarZone.leading.title(store)) { moves.move(item, to: .leading) }
            .accessibilityAction(named: ToolbarZone.leadingInner.title(store)) { moves.move(item, to: .leadingInner) }
            .accessibilityAction(named: ToolbarZone.trailingInner.title(store)) { moves.move(item, to: .trailingInner) }
            .accessibilityAction(named: ToolbarZone.trailing.title(store)) { moves.move(item, to: .trailing) }
            .accessibilityAction(named: store.text("убрать", "Убрать")) { moves.move(item, to: .hidden) }
    }
}

/// AppKit drag source with mica's context menu, for tiles in the title bar band.
struct TitlebarDragSource: NSViewRepresentable {
    let payload: String
    let menu: () -> [MenuEntry]
    final class Source: MenuCatcherView, NSDraggingSource {
        var payload = ""
        private var start: NSPoint?
        override var mouseDownCanMoveWindow: Bool { false }
        override func passThrough() -> NSView? { self }
        override func mouseDown(with event: NSEvent) {
            if MenuCatcherView.secondary(event) { present(event); return }
            start = convert(event.locationInWindow, from: nil)
        }
        override func mouseUp(with event: NSEvent) { start = nil }
        override func mouseDragged(with event: NSEvent) {
            guard let start else { return }
            let point = convert(event.locationInWindow, from: nil)
            guard hypot(point.x - start.x, point.y - start.y) > 3 else { return }
            self.start = nil
            let item = NSDraggingItem(pasteboardWriter: payload as NSString)
            let image = NSImage(size: bounds.size)
            if let rep = bitmapImageRepForCachingDisplay(in: bounds), let host = superview {
                host.cacheDisplay(in: convert(bounds, to: host), to: rep); image.addRepresentation(rep)
            }
            item.setDraggingFrame(bounds, contents: image)
            beginDraggingSession(with: [item], event: event, source: self)
        }
        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { context == .withinApplication ? .move : [] }
    }
    func makeNSView(context: Context) -> Source { let view = Source(); update(view); return view }
    func updateNSView(_ view: Source, context: Context) { update(view) }
    private func update(_ view: Source) { view.payload = payload; view.entries = menu; view.activeWhileCustomizing = true }
}

/// Drag preview: the glyph on a raised tile.
struct EditGlyph: View {
    let item: ToolbarControl
    var body: some View {
        Glyph(name: item.symbol, size: 14).foregroundStyle(Palette.ink)
            .frame(width: 34, height: 34)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Palette.raised))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Palette.hairlineStrong, lineWidth: 1))
    }
}
