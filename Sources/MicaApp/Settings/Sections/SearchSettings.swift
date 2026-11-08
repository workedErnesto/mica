import AppKit
import SwiftUI
import AVFoundation
import MicaCore

struct SearchSettings: View {
    @ObservedObject var store: Store
    @ObservedObject var browser: BrowserModel
    var body: some View {
        VStack(alignment: .leading, spacing: Space.section) {
            SettingsGroup(title: store.text("поиск", "Поиск"), footnote: store.text("запрос из адресной строки уходит только выбранному поисковику", "Запрос из адресной строки уходит только выбранному поисковику")) {
                SearchPicker(store: store).padding(10)
            }
            SettingsGroup(title: store.text("блокировка", "Блокировка")) {
                Toggle(isOn: $store.preferences.blocking) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.text("блокировать рекламу и трекеры", "Блокировать рекламу и трекеры"))
                        Text(store.text("только сторонние запросы, без косметических фильтров", "Только сторонние запросы, без косметических фильтров")).font(.system(size: 11.5)).foregroundStyle(Palette.text3)
                    }
                }.toggleStyle(MToggleStyle()).modifier(RowInset(divider: true))
                BlockerSettings(blocker: store.blocker, store: store)
            }
            if !store.preferences.blockingExceptions.isEmpty {
                SettingsGroup(title: store.text("сайты без блокировки", "Сайты без блокировки")) {
                    ForEach(Array(store.preferences.blockingExceptions.enumerated()), id: \.element) { index, host in
                        SettingRow(title: host, divider: index < store.preferences.blockingExceptions.count - 1) {
                            Button(store.text("вернуть блокировку", "Вернуть блокировку")) { withMotion(Motion.quick) { store.preferences.blockingExceptions.removeAll { $0 == host } } }.buttonStyle(MButtonStyle(kind: .ghost, compact: true))
                        }
                        .transition(.opacity)
                    }
                }
            }
            SettingsGroup(title: store.text("данные", "Данные")) {
                SettingRow(title: store.text("история и данные сайтов", "История и данные сайтов"), detail: store.text("cookie, кэш и локальное хранилище обычных окон", "Cookie, кэш и локальное хранилище обычных окон"), divider: false) {
                    Button(store.text("очистить…", "Очистить…")) { browser.showClearData = true }.buttonStyle(MButtonStyle(kind: .destructive, compact: true))
                }
            }
        }
    }
}

struct BlockerSettings: View {
    @ObservedObject var blocker: Blocker
    @ObservedObject var store: Store
    var body: some View {
        SettingRow(title: store.text("список Peter Lowe", "Список Peter Lowe"), info: store.text("открытый список доменов рекламных сетей и счётчиков, который Peter Lowe ведёт на pgl.yoyo.org. mica превращает его в правила WebKit, и страницы не могут загрузить с этих доменов баннеры, пиксели и скрипты слежки. блокируются только запросы к чужим доменам, сам сайт открывается как обычно. список встроен в приложение и работает без сети. «обновить» скачивает свежую версию, по расписанию mica в сеть не ходит.", "Открытый список доменов рекламных сетей и счётчиков, который Peter Lowe ведёт на pgl.yoyo.org. mica превращает его в правила WebKit, и страницы не могут загрузить с этих доменов баннеры, пиксели и скрипты слежки. Блокируются только запросы к чужим доменам, сам сайт открывается как обычно. Список встроен в приложение и работает без сети. «Обновить» скачивает свежую версию, по расписанию mica в сеть не ходит."), detail: String(blocker.count) + store.text(" доменов. ", " доменов. ") + (blocker.status.isEmpty ? store.text("обновление только по кнопке, запрос к pgl.yoyo.org", "Обновление только по кнопке, запрос к pgl.yoyo.org") : blocker.status), divider: false) {
            Button { Task { await blocker.update() } } label: {
                Text(blocker.updating ? store.text("обновление…", "Обновление…") : store.text("обновить", "Обновить"))
            }
            .buttonStyle(MButtonStyle(kind: .secondary, compact: true)).disabled(blocker.updating)
        }
    }
}
