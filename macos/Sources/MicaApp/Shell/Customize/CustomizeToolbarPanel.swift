import AppKit
import SwiftUI
import MicaCore

/// The palette over the page: every control, the address field length and the finish action.
struct CustomizeToolbarPanel: View {
    @ObservedObject var store: Store
    @ObservedObject var browser: BrowserModel
    let layout: TabLayout
    let maxHeight: CGFloat
    @State private var targeted = false
    @State private var shown = false
    /// Height of the panel content. A ScrollView takes all the height it is offered, so the panel is sized to its
    /// content and scrolls only when the window is too short for it.
    @State private var contentHeight: CGFloat = 0
    var body: some View {
        let toolbar = browser.prefs.toolbar
        let moves = ToolbarMoves(store: store, browser: browser)
        ScrollView {
        VStack(alignment: .leading, spacing: Space.section) {
            VStack(alignment: .leading, spacing: 4) {
                Text(browser.text("перетащите кнопки на панель", "Перетащите кнопки на панель")).font(.system(size: 15, weight: .medium)).foregroundStyle(Palette.ink)
                Text(layout.horizontal
                     ? browser.text("в шапке четыре места: у краёв окна и рядом с адресом. чтобы убрать кнопку, верните её сюда.", "В шапке четыре места: у краёв окна и рядом с адресом. Чтобы убрать кнопку, верните её сюда.")
                     : browser.text("в шапке четыре места: у краёв окна и рядом с адресом, ещё одно внизу боковой панели. чтобы убрать кнопку, верните её сюда.", "В шапке четыре места: у краёв окна и рядом с адресом, ещё одно внизу боковой панели. Чтобы убрать кнопку, верните её сюда."))
                    .font(.system(size: 12)).foregroundStyle(Palette.text3).fixedSize(horizontal: false, vertical: true)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96, maximum: 140), spacing: Space.small)], spacing: Space.small) {
                ForEach(ToolbarControl.allCases, id: \.self) { item in
                    PaletteTile(item: item, zone: toolbar.zone(of: item), store: store, browser: browser, layout: layout)
                }
            }
            .padding(Space.small)
            .background {
                RoundedRectangle(cornerRadius: Radius.panel - 4, style: .continuous).fill(targeted ? Palette.hover : Palette.track.opacity(0.5))
                RoundedRectangle(cornerRadius: Radius.panel - 4, style: .continuous).strokeBorder(targeted ? Palette.focusRing : .clear, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            VStack(alignment: .leading, spacing: Space.normal) {
                HStack(spacing: Space.normal) {
                    Text(browser.text("длина адресной строки", "Длина адресной строки")).font(.system(size: 12.5)).foregroundStyle(Palette.text2)
                    MSlider(value: $browser.prefs.toolbar.addressWidth, range: ToolbarLayout.addressRange, label: browser.text("длина адресной строки", "Длина адресной строки")).frame(maxWidth: 180)
                    Text(String(Int(toolbar.addressWidth.rounded())) + " pt").font(.system(size: 11.5).monospacedDigit()).foregroundStyle(Palette.text3).fixedSize()
                }
                HStack(spacing: Space.small) {
                    Button(browser.text("вернуть как было", "Вернуть как было")) { withMotion(Motion.quick) { browser.prefs.toolbar = ToolbarLayout() } }
                        .buttonStyle(MButtonStyle(kind: .ghost)).disabled(toolbar == ToolbarLayout()).fixedSize()
                    Spacer(minLength: 0)
                    Button(browser.text("готово", "Готово")) { browser.customizingToolbar = false }
                        .buttonStyle(MButtonStyle(kind: .primary)).keyboardShortcut(.defaultAction).fixedSize()
                }
            }
        }
        .padding(Space.section)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: min(contentHeight, maxHeight))
        .frame(maxWidth: 820)
        .modifier(RaisedSurface(radius: Radius.panel))
        // The whole panel takes a control back; a drop target on the lazy grid alone never received drops.
        .contentShape(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
        .dropDestination(for: String.self) { payloads, _ in
            guard let dragged = payloads.first.flatMap(ToolbarDrag.item) else { return false }
            moves.move(dragged, to: .hidden)
            return true
        } isTargeted: { targeted = $0 }
        .scaleEffect(shown || Motion.reduced ? 1 : 0.98, anchor: .top)
        .offset(y: shown || Motion.reduced ? 0 : -8)
        .opacity(shown ? 1 : 0)
        .animation(Motion.hover, value: targeted)
        .onAppear { withMotion(Motion.panel ?? Motion.hover) { shown = true } }
        .onExitCommand { browser.customizingToolbar = false }
    }
}

/// A control in the palette with where it currently lives. Placed controls stay draggable, so the palette
/// is also the way to move a control from one area to another.
private struct PaletteTile: View {
    let item: ToolbarControl
    let zone: ToolbarZone
    @ObservedObject var store: Store
    @ObservedObject var browser: BrowserModel
    let layout: TabLayout
    @State private var hover = false
    var body: some View {
        let moves = ToolbarMoves(store: store, browser: browser)
        let placed = zone != .hidden
        VStack(spacing: 6) {
            Glyph(name: item.symbol, size: 14)
                .foregroundStyle(placed ? Palette.text3 : Palette.ink)
                .frame(width: 40, height: 32)
                .background(RoundedRectangle(cornerRadius: Radius.icon, style: .continuous).fill(placed ? Color.clear : Palette.surface))
                .overlay(RoundedRectangle(cornerRadius: Radius.icon, style: .continuous).strokeBorder(placed ? Palette.hairlineStrong : Palette.hairline, style: StrokeStyle(lineWidth: 1, dash: placed ? [3, 2] : [])))
                .shadow(color: placed ? .clear : Palette.shadow, radius: hover ? 4 : 2, y: 1)
            VStack(spacing: 1) {
                Text(item.title(browser)).font(.system(size: 11.5)).foregroundStyle(Palette.ink).lineLimit(1)
                Text(placed ? zone.title(browser) : browser.text("можно добавить", "Можно добавить")).font(.system(size: 10.5)).foregroundStyle(Palette.text3).lineLimit(1)
            }
        }
        .padding(.vertical, Space.small).padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(hover ? Palette.hover : .clear))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .draggable(ToolbarDrag.payload(item)) { EditGlyph(item: item) }
        .micaContextMenu(activeWhileCustomizing: true) { moves.menu(item, layout: layout) }
        .animation(Motion.hover, value: hover)
        .animation(Motion.hover, value: zone)
        .accessibilityElement()
        .accessibilityLabel(item.title(browser) + ", " + zone.title(browser))
        .accessibilityAction(named: ToolbarZone.leading.title(browser)) { moves.move(item, to: .leading) }
        .accessibilityAction(named: ToolbarZone.leadingInner.title(browser)) { moves.move(item, to: .leadingInner) }
        .accessibilityAction(named: ToolbarZone.trailingInner.title(browser)) { moves.move(item, to: .trailingInner) }
        .accessibilityAction(named: ToolbarZone.trailing.title(browser)) { moves.move(item, to: .trailing) }
        .accessibilityAction(named: ToolbarZone.sidebar.title(browser)) { moves.move(item, to: .sidebar) }
        .accessibilityAction(named: browser.text("убрать", "Убрать")) { moves.move(item, to: .hidden) }
    }
}
