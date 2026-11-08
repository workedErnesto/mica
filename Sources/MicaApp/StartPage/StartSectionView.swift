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
        let start = store.preferences.start
        let visible = start.sections.contains(section)
        VStack(alignment: .leading, spacing: Space.normal) {
            HStack(spacing: Space.small) {
                Text(section.title(store)).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.text3)
                if editing && !visible {
                    Text(store.text("скрыто", "Скрыто")).font(.system(size: 11)).foregroundStyle(Palette.text3)
                        .padding(.horizontal, 6).frame(height: 18)
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Palette.track))
                        .transition(.opacity)
                }
                Spacer(minLength: 0)
                if editing {
                    HStack(spacing: 0) {
                        IconButton(symbol: "chevron.up", label: store.text("выше", "Выше") + ": " + section.title(store), size: 24) { withMotion(Motion.quick) { store.preferences.start.shift(section, by: -1) } }
                            .disabled(!visible || start.sections.first == section)
                        IconButton(symbol: "chevron.down", label: store.text("ниже", "Ниже") + ": " + section.title(store), size: 24) { withMotion(Motion.quick) { store.preferences.start.shift(section, by: 1) } }
                            .disabled(!visible || start.sections.last == section)
                        IconButton(symbol: visible ? "eye" : "eye.slash", label: (visible ? store.text("скрыть", "Скрыть") : store.text("показать", "Показать")) + ": " + section.title(store), selected: !visible, size: 24) {
                            withMotion(Motion.quick) { store.preferences.start.setVisible(section, !visible) }
                        }
                        .contentTransition(.symbolEffect(.replace))
                    }
                    .transition(.opacity)
                }
            }
            .frame(minHeight: 24)
            if editing && sites.isEmpty && section != .custom {
                Text(placeholder).font(.system(size: 12)).foregroundStyle(Palette.text3)
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .background(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous).strokeBorder(Palette.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 88, maximum: 120), spacing: Space.normal)], spacing: Space.normal) {
                ForEach(sites) { site in
                    SiteTile(title: site.title, host: site.host) { browser.selected?.load(site.url) }
                        .micaContextMenu { menu(site) }
                        .modifier(ShortcutDrag(site: site, store: store))
                        .popover(isPresented: Binding(get: { editingSite == site }, set: { if !$0 { editingSite = nil } }), arrowEdge: .bottom) {
                            ShortcutEditor(store: store, editing: site.shortcut) { editingSite = nil }
                        }
                        .transition(Motion.pop)
                }
                if section == .custom { AddShortcutTile(store: store).transition(Motion.pop) }
            }
            .animation(Motion.quick, value: sites.map(\.id))
            }
        }
        .modifier(StartEditFrame(editing: editing, visible: visible, store: store))
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
            MenuEntry.item(browser.text("переместить левее", "Переместить левее"), symbol: "arrow.left", enabled: store.preferences.start.shortcuts.first?.id != id) { withMotion(Motion.quick) { store.preferences.start.shiftShortcut(id, by: -1) } }
            MenuEntry.item(browser.text("переместить правее", "Переместить правее"), symbol: "arrow.right", enabled: store.preferences.start.shortcuts.last?.id != id) { withMotion(Motion.quick) { store.preferences.start.shiftShortcut(id, by: 1) } }
            MenuEntry.divider
            MenuEntry.item(browser.text("удалить с начальной страницы", "Удалить с начальной страницы"), symbol: "trash", destructive: true) { withMotion(Motion.quick) { store.preferences.start.shortcuts.removeAll { $0.id == id } } }
        } else {
            MenuEntry.item(browser.text("закрепить в своих сайтах", "Закрепить в своих сайтах"), symbol: "pin") {
                withMotion(Motion.quick) {
                    store.preferences.start.shortcuts.append(StartShortcut(title: site.title, url: site.url))
                    store.preferences.start.setVisible(.custom, true)
                }
            }
            if section == .frequent, let host = site.url.host?.lowercased() {
                MenuEntry.item(browser.text("скрыть из частых", "Скрыть из частых"), symbol: "eye.slash") { withMotion(Motion.quick) { store.preferences.start.hiddenHosts.append(host) } }
            }
        }
        MenuEntry.divider
        MenuEntry.item(browser.text("настроить начальную страницу…", "Настроить начальную страницу…"), symbol: "slider.horizontal.3") { withMotion(Motion.panel) { browser.customizingStart = true } }
    }
}
