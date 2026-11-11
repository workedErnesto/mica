import AppKit
import SwiftUI
import WebKit
import MicaCore
import UniformTypeIdentifiers

/// Adds or edits a custom start page site. Plain words are refused instead of becoming a search shortcut.
/// Opened from the address bar it comes with the page's address filled in, and the name field takes the focus.
struct ShortcutEditor: View {
    @ObservedObject var store: Store
    @ObservedObject var browser: BrowserModel
    let editing: UUID?
    var page: URL? = nil
    let done: () -> Void
    @State private var address = ""
    @State private var title = ""
    @State private var invalid = false
    var body: some View {
        VStack(alignment: .leading, spacing: Space.normal) {
            Text(editing == nil ? browser.text("новый сайт", "Новый сайт") : browser.text("изменить сайт", "Изменить сайт")).font(.system(size: 14, weight: .medium)).foregroundStyle(Palette.ink)
            VStack(alignment: .leading, spacing: Space.small) {
                MTextField(placeholder: browser.text("адрес, например github.com", "Адрес, например github.com"), text: $address, symbol: "globe", autofocus: page == nil) { save() }
                if invalid { Text(browser.text("нужен адрес сайта, а не поисковый запрос", "Нужен адрес сайта, а не поисковый запрос")).font(.system(size: 11.5)).foregroundStyle(Palette.danger).transition(.opacity) }
                MTextField(placeholder: browser.text("название, необязательно", "Название, необязательно"), text: $title, symbol: "textformat", autofocus: page != nil) { save() }
            }
            HStack(spacing: Space.small) {
                Spacer()
                Button(browser.text("отмена", "Отмена")) { done() }.buttonStyle(MButtonStyle(kind: .ghost, compact: true)).keyboardShortcut(.cancelAction)
                Button(editing == nil ? browser.text("добавить", "Добавить") : browser.text("сохранить", "Сохранить")) { save() }.buttonStyle(MButtonStyle(kind: .primary, compact: true)).disabled(address.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 300)
        .animation(Motion.hover, value: invalid)
        .onAppear {
            if let page { address = page.absoluteString }
            if let editing, let item = browser.prefs.start.shortcuts.first(where: { $0.id == editing }) { address = item.url.absoluteString; title = item.title }
        }
    }
    private func save() {
        // The page's own address is kept as it is, so the address bar finds the page pinned afterwards.
        let unchanged = page.flatMap { address.trimmingCharacters(in: .whitespacesAndNewlines) == $0.absoluteString ? $0 : nil }
        guard let url = unchanged ?? StartPage.shortcutURL(address, engine: store.preferences.search) else { invalid = true; return }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        withMotion(Motion.quick) {
            if let editing, let index = browser.prefs.start.shortcuts.firstIndex(where: { $0.id == editing }) {
                browser.prefs.start.shortcuts[index].url = url; browser.prefs.start.shortcuts[index].title = name
            } else {
                browser.prefs.start.shortcuts.append(StartShortcut(title: name, url: url))
                browser.prefs.start.setVisible(.custom, true)
            }
        }
        done()
    }
}
