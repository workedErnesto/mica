import AppKit
import SwiftUI
import AVFoundation
import MicaCore

struct SearchSettings: View {
    @ObservedObject var store: Store
    @ObservedObject var browser: BrowserModel
    var body: some View {
        VStack(alignment: .leading, spacing: Space.section) {
            SettingsGroup(title: browser.text("поиск", "Поиск"), footnote: browser.text("запрос из адресной строки уходит только выбранному поисковику", "Запрос из адресной строки уходит только выбранному поисковику")) {
                SearchPicker(store: store, browser: browser).padding(10)
            }
            SettingsGroup(title: browser.text("блокировка", "Блокировка")) {
                Toggle(isOn: $store.preferences.blocking) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(browser.text("блокировать рекламу и трекеры", "Блокировать рекламу и трекеры"))
                        Text(browser.text("только сторонние запросы, без косметических фильтров", "Только сторонние запросы, без косметических фильтров")).font(.system(size: 11.5)).foregroundStyle(Palette.text3)
                    }
                }.toggleStyle(MToggleStyle()).modifier(RowInset(divider: true))
                BlockerSettings(blocker: store.blocker, store: store, browser: browser)
            }
            if !store.preferences.blockingExceptions.isEmpty {
                SettingsGroup(title: browser.text("сайты без блокировки", "Сайты без блокировки")) {
                    ForEach(Array(store.preferences.blockingExceptions.enumerated()), id: \.element) { index, host in
                        SettingRow(title: host, divider: index < store.preferences.blockingExceptions.count - 1) {
                            Button(browser.text("вернуть блокировку", "Вернуть блокировку")) { withMotion(Motion.quick) { store.preferences.blockingExceptions.removeAll { $0 == host } } }.buttonStyle(MButtonStyle(kind: .ghost, compact: true))
                        }
                        .transition(.opacity)
                    }
                }
            }
            SettingsGroup(title: browser.text("данные", "Данные")) {
                SettingRow(title: browser.text("история и данные сайтов", "История и данные сайтов"), detail: browser.text("cookie, кэш и локальное хранилище обычных окон", "Cookie, кэш и локальное хранилище обычных окон"), divider: false) {
                    Button(browser.text("очистить…", "Очистить…")) { browser.showClearData = true }.buttonStyle(MButtonStyle(kind: .destructive, compact: true))
                }
            }
        }
    }
}

struct BlockerSettings: View {
    @ObservedObject var blocker: Blocker
    @ObservedObject var store: Store
    @ObservedObject var browser: BrowserModel
    var body: some View {
        SettingRow(title: browser.text("список Peter Lowe", "Список Peter Lowe"), info: browser.text("открытый список доменов рекламных сетей и счётчиков, который Peter Lowe ведёт на pgl.yoyo.org. mica превращает его в правила WebKit, и страницы не могут загрузить с этих доменов баннеры, пиксели и скрипты слежки. блокируются только запросы к чужим доменам, сам сайт открывается как обычно. список встроен в приложение и работает без сети. «обновить» скачивает свежую версию, по расписанию mica в сеть не ходит.", "Открытый список доменов рекламных сетей и счётчиков, который Peter Lowe ведёт на pgl.yoyo.org. mica превращает его в правила WebKit, и страницы не могут загрузить с этих доменов баннеры, пиксели и скрипты слежки. Блокируются только запросы к чужим доменам, сам сайт открывается как обычно. Список встроен в приложение и работает без сети. «Обновить» скачивает свежую версию, по расписанию mica в сеть не ходит."), detail: String(blocker.count) + browser.text(" доменов. ", " доменов. ") + (blocker.status.isEmpty ? browser.text("обновление только по кнопке, запрос к pgl.yoyo.org", "Обновление только по кнопке, запрос к pgl.yoyo.org") : blocker.status), divider: false) {
            Button { Task { await blocker.update() } } label: {
                Text(blocker.updating ? browser.text("обновление…", "Обновление…") : browser.text("обновить", "Обновить"))
            }
            .buttonStyle(MButtonStyle(kind: .secondary, compact: true)).disabled(blocker.updating)
        }
    }
}
