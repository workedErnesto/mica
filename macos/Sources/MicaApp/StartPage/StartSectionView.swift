import AppKit
import SwiftUI
import WebKit
import MicaCore
import UniformTypeIdentifiers

struct StartSite: Identifiable, Equatable {
    let id: String
    let title: String
    let url: URL
    var shortcut: UUID?
    var host: String { url.host ?? url.absoluteString }
}

extension StartSection {
    @MainActor func title(_ browser: BrowserModel) -> String {
        switch self {
        case .custom: return browser.text("свои сайты", "Свои сайты")
        case .frequent: return browser.text("часто открываете", "Часто открываете")
        case .bookmarks: return browser.text("закладки", "Закладки")
        }
    }
}

struct StartSectionView: View {
    let section: StartSection
    let sites: [StartSite]
    @ObservedObject var browser: BrowserModel
    @ObservedObject var store: Store
    var editing = false
    /// Tiles in a row (StartLayout.columns).
    var columns = 8
    @State private var editingSite: StartSite?
    var body: some View {
        let start = browser.prefs.start
        let visible = start.sections.contains(section)
        // A row never holds more columns than the section has tiles, so the block keeps to its own content.
        let tiles = sites.count + (section == .custom ? 1 : 0)
        let grid = Array(repeating: GridItem(.fixed(StartLayout.column), spacing: Space.micro), count: max(1, min(columns, tiles)))
        StartBlockStack {
            StartBlockHeader(title: section.title(browser), editing: editing, shown: Binding(get: { visible }, set: { browser.prefs.start.setVisible(section, $0) }), store: store, browser: browser) {
                HStack(spacing: 0) {
                    IconButton(symbol: "chevron.up", label: browser.text("выше", "Выше") + ": " + section.title(browser), size: 24) { withMotion(Motion.quick) { browser.prefs.start.shift(section, by: -1) } }
                        .disabled(!visible || start.sections.first == section)
                    IconButton(symbol: "chevron.down", label: browser.text("ниже", "Ниже") + ": " + section.title(browser), size: 24) { withMotion(Motion.quick) { browser.prefs.start.shift(section, by: 1) } }
                        .disabled(!visible || start.sections.last == section)
                }
            }
            SwiftUI.Group {
                if editing && sites.isEmpty && section != .custom {
                    Text(placeholder).font(.system(size: 12)).foregroundStyle(Palette.text3)
                        .multilineTextAlignment(.center).padding(.horizontal, Space.normal)
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).strokeBorder(Palette.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                        .padding(.horizontal, StartLayout.inset)
                } else {
                    LazyVGrid(columns: grid, alignment: .leading, spacing: Space.normal) {
                        ForEach(sites) { site in
                            SiteTile(title: site.title, host: site.host, url: site.url, favicons: browser.favicons) { open(site.url) }
                                .micaContextMenu { menu(site) }
                                .modifier(ShortcutDrag(site: site, store: store, browser: browser))
                                .stickyPopover(isPresented: Binding(get: { editingSite == site }, set: { if !$0 { editingSite = nil } })) {
                                    ShortcutEditor(store: store, browser: browser, editing: site.shortcut) { editingSite = nil }
                                }
                                .transition(Motion.pop)
                        }
                        if section == .custom { AddShortcutTile(store: store, browser: browser).transition(Motion.pop) }
                    }
                    .animation(Motion.quick, value: sites.map(\.id))
                }
            }
            .opacity(editing && !visible ? 0.4 : 1)
        }
        .modifier(StartEditFrame(editing: editing))
        .animation(Motion.quick, value: visible)
    }
    private var placeholder: String {
        switch section {
        case .frequent: return browser.privateMode ? browser.text("в окне инкогнито частые сайты не показываются", "В окне инкогнито частые сайты не показываются") : browser.text("появятся, когда вы начнёте открывать сайты", "Появятся, когда вы начнёте открывать сайты")
        case .bookmarks: return browser.text("здесь будут закладки, ⌘D добавляет страницу", "Здесь будут закладки, ⌘D добавляет страницу")
        case .custom: return ""
        }
    }
    /// A click opens the site in this tab; with ⌘ held it opens in a new window of the same profile and mode.
    private func open(_ url: URL) {
        if NSEvent.modifierFlags.contains(.command) { openInWindow(url) } else { browser.selected?.load(url) }
    }
    private func openInWindow(_ url: URL) {
        browser.store.newWindow(privateMode: browser.privateMode, profile: browser.profileID).selected?.load(url)
    }
    @MenuBuilder private func menu(_ site: StartSite) -> [MenuEntry] {
        MenuEntry.item(browser.text("открыть в новой вкладке", "Открыть в новой вкладке"), symbol: "plus.square") { browser.open(site.url) }
        MenuEntry.item(browser.text("открыть в новом окне", "Открыть в новом окне"), symbol: "macwindow") { openInWindow(site.url) }
        MenuEntry.divider
        if let id = site.shortcut {
            MenuEntry.item(browser.text("изменить…", "Изменить…"), symbol: "pencil") { editingSite = site }
            MenuEntry.item(browser.text("переместить левее", "Переместить левее"), symbol: "arrow.left", enabled: browser.prefs.start.shortcuts.first?.id != id) { withMotion(Motion.quick) { browser.prefs.start.shiftShortcut(id, by: -1) } }
            MenuEntry.item(browser.text("переместить правее", "Переместить правее"), symbol: "arrow.right", enabled: browser.prefs.start.shortcuts.last?.id != id) { withMotion(Motion.quick) { browser.prefs.start.shiftShortcut(id, by: 1) } }
            MenuEntry.divider
            MenuEntry.item(browser.text("удалить с начальной страницы", "Удалить с начальной страницы"), symbol: "trash", destructive: true) { withMotion(Motion.quick) { browser.prefs.start.shortcuts.removeAll { $0.id == id } } }
        } else {
            MenuEntry.item(browser.text("закрепить в своих сайтах", "Закрепить в своих сайтах"), symbol: "pin") {
                withMotion(Motion.quick) {
                    browser.prefs.start.shortcuts.append(StartShortcut(title: site.title, url: site.url))
                    browser.prefs.start.setVisible(.custom, true)
                }
            }
            if section == .frequent, let host = site.url.host?.lowercased() {
                MenuEntry.item(browser.text("скрыть из частых", "Скрыть из частых"), symbol: "eye.slash") { withMotion(Motion.quick) { browser.prefs.start.hiddenHosts.append(host) } }
            }
        }
        MenuEntry.divider
        MenuEntry.item(browser.text("настроить начальную страницу…", "Настроить начальную страницу…"), symbol: "slider.horizontal.3") { withMotion(Motion.panel) { browser.customizingStart = true } }
    }
}
