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
    @MainActor func title(_ store: Store) -> String {
        switch self {
        case .custom: return store.text("свои сайты", "Свои сайты")
        case .frequent: return store.text("часто открываете", "Часто открываете")
        case .bookmarks: return store.text("закладки", "Закладки")
        }
    }
}

struct StartSectionView: View {
    let section: StartSection
    let sites: [StartSite]
    @ObservedObject var browser: BrowserModel
    @ObservedObject var store: Store
    var editing = false
    @State private var editingSite: StartSite?
    var body: some View {
        let start = browser.prefs.start
        let visible = start.sections.contains(section)
        VStack(alignment: .leading, spacing: Space.normal) {
            StartBlockHeader(title: section.title(store), editing: editing, shown: Binding(get: { visible }, set: { browser.prefs.start.setVisible(section, $0) }), store: store) {
                HStack(spacing: 0) {
                    IconButton(symbol: "chevron.up", label: store.text("выше", "Выше") + ": " + section.title(store), size: 24) { withMotion(Motion.quick) { browser.prefs.start.shift(section, by: -1) } }
                        .disabled(!visible || start.sections.first == section)
                    IconButton(symbol: "chevron.down", label: store.text("ниже", "Ниже") + ": " + section.title(store), size: 24) { withMotion(Motion.quick) { browser.prefs.start.shift(section, by: 1) } }
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
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: StartLayout.column, maximum: StartLayout.column), spacing: Space.micro)], alignment: .leading, spacing: Space.normal) {
                        ForEach(sites) { site in
                            SiteTile(title: site.title, host: site.host, url: site.url, favicons: browser.favicons) { browser.selected?.load(site.url) }
                                .micaContextMenu { menu(site) }
                                .modifier(ShortcutDrag(site: site, store: store, browser: browser))
                                .popover(isPresented: Binding(get: { editingSite == site }, set: { if !$0 { editingSite = nil } }), arrowEdge: .bottom) {
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
        case .frequent: return browser.privateMode ? store.text("в окне инкогнито частые сайты не показываются", "В окне инкогнито частые сайты не показываются") : store.text("появятся, когда вы начнёте открывать сайты", "Появятся, когда вы начнёте открывать сайты")
        case .bookmarks: return store.text("здесь будут закладки, ⌘D добавляет страницу", "Здесь будут закладки, ⌘D добавляет страницу")
        case .custom: return ""
        }
    }
    @MenuBuilder private func menu(_ site: StartSite) -> [MenuEntry] {
        MenuEntry.item(browser.text("открыть в новой вкладке", "Открыть в новой вкладке"), symbol: "plus.square") { browser.open(site.url) }
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
