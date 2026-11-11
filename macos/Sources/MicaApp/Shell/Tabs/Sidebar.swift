import AppKit
import SwiftUI
import WebKit
import MicaCore
import UniformTypeIdentifiers

struct Sidebar: View {
    @ObservedObject var browser: BrowserModel
    @ObservedObject var store: Store
    /// Collapsed sidebar keeps a rail of site icons instead of disappearing.
    let compact: Bool
    let edge: TabLayout
    var body: some View {
        let pinned = browser.tabs.filter(\.pinned)
        let regular = browser.tabs.filter { !$0.pinned }
        let footer = browser.prefs.toolbar.resolved(sidebarAvailable: true).sidebar
        SwiftUI.Group {
            if compact { rail(pinned: pinned, regular: regular, footer: footer).transition(.opacity) }
            else { full(pinned: pinned, regular: regular, footer: footer).transition(.opacity) }
        }
        .animation(Motion.quick, value: pinned.map(\.id))
        .animation(Motion.quick, value: regular.map(\.id))
        .animation(Motion.quick, value: browser.customizingToolbar)
        .micaContextMenu {
            MenuEntry.item(browser.text("новая вкладка", "Новая вкладка"), symbol: "plus") { _ = browser.add(); browser.focusAddress += 1 }
            MenuEntry.item(browser.prefs.sidebarCollapsed ? browser.text("развернуть боковую панель", "Развернуть боковую панель") : browser.text("свернуть боковую панель", "Свернуть боковую панель"), symbol: edge == .right ? "sidebar.right" : "sidebar.left") {
                withMotion(Motion.panel) { browser.prefs.sidebarCollapsed.toggle() }
            }
            MenuEntry.divider
            LayoutMenu.entries(store: store, browser: browser)
            MenuEntry.divider
            MenuEntry.item(browser.text("настроить панель инструментов…", "Настроить панель инструментов…"), symbol: "slider.horizontal.3") { browser.customizingToolbar = true }
        }
    }

    private func full(pinned: [Tab], regular: [Tab], footer: [ToolbarControl]) -> some View {
        VStack(alignment: .leading, spacing: Space.small) {
            if !pinned.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 6)], spacing: 6) {
                    ForEach(pinned) { tab in PinnedTile(tab: tab, browser: browser).transition(Motion.pop) }
                }
            }
            NewTabRow(browser: browser)
            Hairline().padding(.horizontal, Space.small)
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(regular) { tab in TabRow(tab: tab, browser: browser, horizontal: false).transition(Motion.pop) }
                }
            }
            .scrollIndicators(.never)
            Spacer(minLength: 0)
            if footer.contains(.extensions) && !browser.customizingToolbar { ExtensionStrip(manager: store.extensions, browser: browser) }
            if browser.customizingToolbar {
                ToolbarDropZone(zone: .sidebar, items: footer, store: store, browser: browser, layout: edge).transition(.opacity)
            } else if !footer.isEmpty {
                // The incognito badge lives in the top bar only, so it is not mistaken for the incognito button here.
                HStack(spacing: 2) {
                    ForEach(footer, id: \.self) { item in ToolbarButton(item: item, browser: browser, store: store, edge: edge, inSidebar: true) }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, Space.small)
        .padding(.bottom, Space.small)
    }

    private func rail(pinned: [Tab], regular: [Tab], footer: [ToolbarControl]) -> some View {
        VStack(spacing: 6) {
            ForEach(pinned) { tab in RailTile(tab: tab, browser: browser).transition(Motion.pop) }
            if !pinned.isEmpty { Hairline().frame(width: 20) }
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(regular) { tab in RailTile(tab: tab, browser: browser).transition(Motion.pop) }
                    RailPlus(browser: browser)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, TileCloseBadge.overhang)
            }
            // The scroll view clips; it reaches up by the badge overhang so the first tile's close badge is whole,
            // while the tiles stay where they were.
            .padding(.top, -TileCloseBadge.overhang)
            .scrollIndicators(.never)
            Spacer(minLength: 0)
            if footer.contains(.extensions) && !browser.customizingToolbar { ExtensionStrip(manager: store.extensions, browser: browser, vertical: true) }
            if browser.customizingToolbar {
                ToolbarDropZone(zone: .sidebar, items: footer, store: store, browser: browser, layout: edge, vertical: true, alignment: .top)
            } else {
                ForEach(footer, id: \.self) { item in ToolbarButton(item: item, browser: browser, store: store, edge: edge, inSidebar: true) }
            }
        }
        .frame(width: Chrome.rail)
        .padding(.bottom, Space.small)
    }
}

struct NewTabRow: View {
    @ObservedObject var browser: BrowserModel
    @State private var hover = false
    var body: some View {
        Button { _ = browser.add(); browser.focusAddress += 1 } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus").font(.system(size: 12, weight: .medium)).frame(width: 18)
                Text(browser.text("новая вкладка", "Новая вкладка")).font(.system(size: 12.5))
                Spacer(minLength: 0)
                KeyHint(keys: "⌘T").opacity(hover ? 1 : 0)
            }
            .foregroundStyle(hover ? Palette.ink : Palette.text2)
            .padding(.horizontal, 8).frame(height: 32)
            .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(hover ? Palette.hover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.98))
        .onHover { hover = $0 }.animation(Motion.hover, value: hover)
    }
}
