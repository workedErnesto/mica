import AppKit
import SwiftUI
import MicaCore

/// Clears browsing data of regular windows for a chosen period. Opens from the history panel, the Library menu
/// (⌘⇧⌫) and settings; the last choice is remembered. Incognito windows keep nothing here to clear.
struct ClearDataPanel: View {
    @ObservedObject var store: Store
    @ObservedObject var browser: BrowserModel
    @State private var working = false
    private var choice: Binding<ClearChoice> { $store.preferences.clearing }
    var body: some View {
        let current = store.preferences.clearing
        let visits = History.count(store.history, since: current.period.start(before: Date()))
        VStack(alignment: .leading, spacing: Space.section) {
            VStack(alignment: .leading, spacing: Space.micro) {
                Text(browser.text("очистить данные", "Очистить данные")).font(.system(size: 20, weight: .regular)).tracking(-0.4).foregroundStyle(Palette.ink)
                Text(browser.text("только обычные окна. закладки и открытые вкладки останутся", "Только обычные окна. Закладки и открытые вкладки останутся")).font(.system(size: 12.5)).foregroundStyle(Palette.text2)
            }
            VStack(alignment: .leading, spacing: Space.small) {
                Text(browser.text("период", "Период")).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.text2)
                Segmented(selection: choice.period, options: [
                    (.hour, browser.text("час", "Час")),
                    (.day, browser.text("сутки", "Сутки")),
                    (.week, browser.text("неделя", "Неделя")),
                    (.month, browser.text("4 недели", "4 недели")),
                    (.all, browser.text("всё время", "Всё время")),
                ], width: 424, label: browser.text("период", "Период"))
            }
            SettingsGroup {
                option(choice.history, browser.text("история посещений", "История посещений"), visits == 0 ? browser.text("за этот период записей нет", "За этот период записей нет") : count(visits), divider: true)
                option(choice.siteData, browser.text("cookie и данные сайтов", "Cookie и данные сайтов"), browser.text("вы выйдете из аккаунтов на сайтах, открытых за этот период", "Вы выйдете из аккаунтов на сайтах, открытых за этот период"), divider: true)
                option(choice.cache, browser.text("кэш", "Кэш"), browser.text("страницы загрузятся заново, это безопасно", "Страницы загрузятся заново, это безопасно"), divider: true)
                option(choice.permissions, browser.text("разрешения сайтов", "Разрешения сайтов"), browser.text("камера, микрофон и уведомления, за всё время: у решений нет даты", "Камера, микрофон и уведомления, за всё время: у решений нет даты"), divider: false)
            }
            HStack(spacing: Space.small) {
                Spacer()
                Button(browser.text("отмена", "Отмена")) { close() }.buttonStyle(MButtonStyle(kind: .ghost)).keyboardShortcut(.cancelAction)
                Button(working ? browser.text("очищаем…", "Очищаем…") : browser.text("очистить", "Очистить")) { run() }
                    .buttonStyle(MButtonStyle(kind: .destructive))
                    .disabled(current.isEmpty || working)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .animation(Motion.hover, value: visits)
    }

    private func option(_ value: Binding<Bool>, _ title: String, _ detail: String, divider: Bool) -> some View {
        Toggle(isOn: value) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.system(size: 11.5)).foregroundStyle(Palette.text3).contentTransition(.opacity)
            }
        }
        .toggleStyle(MToggleStyle()).modifier(RowInset(divider: divider))
    }

    private func count(_ n: Int) -> String {
        if browser.prefs.language == .en { return "\(n) " + (n == 1 ? "entry" : "entries") }
        let ten = n % 10, hundred = n % 100
        let word = ten == 1 && hundred != 11 ? "запись" : (2...4).contains(ten) && !(12...14).contains(hundred) ? "записи" : "записей"
        return "\(n) " + word
    }

    private func close() { browser.showClearData = false }

    private func run() {
        working = true
        let selected = store.preferences.clearing
        Task {
            await store.clear(selected)
            working = false
            close()
        }
    }
}
