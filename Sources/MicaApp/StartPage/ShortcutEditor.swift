import AppKit
import SwiftUI
import WebKit
import MicaCore
import UniformTypeIdentifiers

/// Adds or edits a custom start page site. Plain words are refused instead of becoming a search shortcut.
struct ShortcutEditor: View {
    @ObservedObject var store: Store
    let editing: UUID?
    let done: () -> Void
    @State private var address = ""
    @State private var title = ""
    @State private var invalid = false
    var body: some View {
        VStack(alignment: .leading, spacing: Space.normal) {
            Text(editing == nil ? store.text("новый сайт", "Новый сайт") : store.text("изменить сайт", "Изменить сайт")).font(.system(size: 14, weight: .medium)).foregroundStyle(Palette.ink)
            VStack(alignment: .leading, spacing: 6) {
                MTextField(placeholder: store.text("адрес, например github.com", "Адрес, например github.com"), text: $address, symbol: "globe") { save() }
                if invalid { Text(store.text("нужен адрес сайта, а не поисковый запрос", "Нужен адрес сайта, а не поисковый запрос")).font(.system(size: 11.5)).foregroundStyle(Palette.danger).transition(.opacity) }
                MTextField(placeholder: store.text("название, необязательно", "Название, необязательно"), text: $title, symbol: "textformat") { save() }
            }
            HStack(spacing: Space.small) {
                Spacer()
                Button(store.text("отмена", "Отмена")) { done() }.buttonStyle(MButtonStyle(kind: .ghost, compact: true)).keyboardShortcut(.cancelAction)
                Button(editing == nil ? store.text("добавить", "Добавить") : store.text("сохранить", "Сохранить")) { save() }.buttonStyle(MButtonStyle(kind: .primary, compact: true)).disabled(address.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 300)
        .animation(Motion.hover, value: invalid)
        .onAppear {
            if let editing, let item = store.preferences.start.shortcuts.first(where: { $0.id == editing }) { address = item.url.absoluteString; title = item.title }
        }
    }
    private func save() {
        guard let url = StartPage.shortcutURL(address, engine: store.preferences.search) else { invalid = true; return }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        withMotion(Motion.quick) {
            if let editing, let index = store.preferences.start.shortcuts.firstIndex(where: { $0.id == editing }) {
                store.preferences.start.shortcuts[index].url = url; store.preferences.start.shortcuts[index].title = name
            } else {
                store.preferences.start.shortcuts.append(StartShortcut(title: name, url: url))
            }
        }
        done()
    }
}
