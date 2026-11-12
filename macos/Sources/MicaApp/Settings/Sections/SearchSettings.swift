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
                        Text(browser.text("встроенные фильтры uBlock Origin", "Встроенные фильтры uBlock Origin")).font(.system(size: 11.5)).foregroundStyle(Palette.text3)
                    }
                }.toggleStyle(MToggleStyle()).modifier(RowInset(divider: true))
                BlockerSettings(engine: store.ublock, store: store, browser: browser)
            }
            SettingsGroup(title: browser.text("сайты без блокировки", "Сайты без блокировки"), footnote: browser.text("добавьте домен: блокировка отключится для него и его поддоменов. после изменения перезагрузите сайт.", "Добавьте домен: блокировка отключится для него и его поддоменов. После изменения перезагрузите сайт.")) {
                HostListEditor(hosts: $store.preferences.blockingExceptions, store: store, browser: browser)
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
    @ObservedObject var engine: UBlockEngine
    @ObservedObject var store: Store
    @ObservedObject var browser: BrowserModel
    private var status: String {
        if !store.preferences.blocking { return browser.text("блокировка выключена", "Блокировка выключена") }
        if engine.compiling { return browser.text("подготовка фильтров…", "Подготовка фильтров…") }
        if engine.updating { return browser.text("обновление…", "Обновление…") }
        if !engine.status.isEmpty && engine.status != engine.summary { return engine.status }
        if let date = engine.listsUpdated {
            return browser.text("обновлены ", "Обновлены ") + date.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(browser.locale))
        }
        return browser.text("встроенные списки готовы", "Встроенные списки готовы")
    }
    var body: some View {
        SettingRow(title: browser.text("списки фильтров", "Списки фильтров"), info: browser.text("mica обновляет списки каждый день без cookie. блокировка работает и в инкогнито. отключить её для отдельного сайта можно в сведениях о сайте. после изменения перезагрузите страницу.", "mica обновляет списки каждый день без cookie. Блокировка работает и в инкогнито. Отключить её для отдельного сайта можно в сведениях о сайте. После изменения перезагрузите страницу."), detail: status, divider: false) {
            Button(browser.text("обновить", "Обновить")) { Task { await engine.updateLists() } }
                .buttonStyle(MButtonStyle(kind: .ghost, compact: true))
                .disabled(!store.preferences.blocking || engine.updating || engine.compiling || engine.package == nil)
        }
        .animation(Motion.quick, value: engine.compiling || engine.updating)
    }
}
