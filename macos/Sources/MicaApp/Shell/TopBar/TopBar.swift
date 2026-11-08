import AppKit
import SwiftUI
import WebKit
import MicaCore
import UniformTypeIdentifiers

/// Top bar across the whole window. The address field is centred on the window, wherever the tabs are;
/// with the tabs above the address (`tabsAbove`) this is the second row, under the tab strip.
/// the controls come from the user's toolbar layout: at each window edge and right next to the field.
struct TopBar: View {
    @ObservedObject var browser: BrowserModel
    @ObservedObject var store: Store
    let layout: TabLayout
    let windowWidth: CGFloat
    let leadingInset: CGFloat
    private let gap = Space.small
    var body: some View {
        let toolbar = store.preferences.toolbar
        let items = toolbar.resolved(sidebarAvailable: !layout.horizontal)
        let edge = layout.sidebarEdge
        let editing = browser.customizingToolbar
        // Running extensions add their own buttons next to the puzzle.
        let extras = editing ? 0 : store.extensions.actionable(privateWindow: browser.privateMode).count
        let badge: CGFloat = browser.privateMode && !editing ? Chrome.item : 0
        // Controls next to the field get the same width on both sides, so the field stays on the centre line.
        let inner = editing ? max(44, max(span(items.leadingInner, 0), span(items.trailingInner, 0)) + 4) : max(span(items.leadingInner, extras), span(items.trailingInner, extras))
        let innerRoom = inner > 0 || editing ? inner + gap : 0
        let edgeLeading = editing ? max(48, span(items.leading, 0) + 4 + Chrome.item) : span(items.leading, extras)
        let edgeTrailing = editing ? max(48, span(items.trailing, 0) + 4 + Chrome.item) : span(items.trailing, extras) + badge
        let leading = leadingInset + edgeLeading + gap + innerRoom
        let trailing = Space.small + edgeTrailing + gap + innerRoom
        // Equal room on both sides keeps the field on the window's centre line; it narrows before it moves.
        let room = windowWidth - 2 * max(leading, trailing)
        let width = max(0, min(CGFloat(toolbar.addressWidth), room))
        let centred = width >= 200 || editing
        ZStack {
            if editing {
                let half = windowWidth / 2 - width / 2 - gap - inner - gap
                HStack(spacing: 0) {
                    Color.clear.frame(width: leadingInset)
                    zone(.leading, items, alignment: .leading).frame(width: max(0, half - leadingInset))
                    Color.clear.frame(width: gap)
                    zone(.leadingInner, items, alignment: .trailing).frame(width: inner)
                    Color.clear.frame(width: width + 2 * gap)
                    zone(.trailingInner, items, alignment: .leading).frame(width: inner)
                    Color.clear.frame(width: gap)
                    zone(.trailing, items, alignment: .trailing).frame(width: max(0, half - Space.small))
                    Color.clear.frame(width: Space.small)
                }
                .frame(width: windowWidth)
                .transition(.opacity)
            } else {
                HStack(spacing: 2) {
                    Color.clear.frame(width: leadingInset)
                    buttons(items.leading, edge)
                    if !centred { buttons(items.leadingInner, edge) }
                    Spacer(minLength: 0)
                    if !centred { buttons(items.trailingInner, edge) }
                    buttons(items.trailing, edge)
                    if browser.privateMode { PrivateBadge(browser: browser) }
                }
                .padding(.trailing, Space.small)
                .transition(.opacity)
                if centred && inner > 0 {
                    HStack(spacing: 0) {
                        HStack(spacing: 2) { buttons(items.leadingInner, edge) }.frame(width: inner, alignment: .trailing)
                        Color.clear.frame(width: width + 2 * gap)
                        HStack(spacing: 2) { buttons(items.trailingInner, edge) }.frame(width: inner, alignment: .leading)
                    }
                    .transition(.opacity)
                }
            }
            if let tab = browser.selected {
                SwiftUI.Group {
                    if centred {
                        AddressPill(tab: tab, browser: browser, store: store).frame(width: width)
                    } else {
                        // Too narrow to centre: the field takes the space between the side groups.
                        let flowLeading = leadingInset + span(items.leading, extras) + span(items.leadingInner, extras)
                        let flowTrailing = Space.small + span(items.trailing, extras) + span(items.trailingInner, extras) + badge
                        AddressPill(tab: tab, browser: browser, store: store)
                            .padding(.leading, flowLeading + gap).padding(.trailing, flowTrailing + gap)
                    }
                }
                .allowsHitTesting(!editing)
                .opacity(editing ? 0.55 : 1)
            }
        }
        .frame(height: Chrome.bar)
        // The drag area is an AppKit view and would take mouse downs from the draggable tiles while customizing.
        .background { if !editing { WindowDragArea() } }
        .micaContextMenu {
            if !editing {
                MenuEntry.item(store.text("настроить панель инструментов…", "Настроить панель инструментов…"), symbol: "slider.horizontal.3") { browser.customizingToolbar = true }
                MenuEntry.divider
                LayoutMenu.entries(store: store)
            }
        }
        .animation(Motion.quick, value: toolbar)
        .animation(Motion.quick, value: editing)
    }
    private func zone(_ zone: ToolbarZone, _ items: ToolbarLayout.Resolved, alignment: Alignment) -> some View {
        ToolbarDropZone(zone: zone, items: items.items(in: zone), store: store, layout: layout, alignment: alignment, minWidth: 0)
    }
    private func buttons(_ list: [ToolbarControl], _ edge: TabLayout?) -> some View {
        ForEach(list, id: \.self) { ToolbarButton(item: $0, browser: browser, store: store, edge: edge).transition(Motion.pop) }
    }
    private func span(_ list: [ToolbarControl], _ extras: Int) -> CGFloat { CGFloat(list.count + (list.contains(.extensions) ? extras : 0)) * Chrome.item }
}
