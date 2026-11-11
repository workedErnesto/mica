import AppKit
import SwiftUI
import AVFoundation
import MicaCore

struct StartSettings: View {
    @ObservedObject var store: Store
    @ObservedObject var browser: BrowserModel
    var body: some View {
        let start = browser.prefs.start
        let ordered = start.sections + StartSection.allCases.filter { !start.sections.contains($0) }
        VStack(alignment: .leading, spacing: Space.section) {
            ProfileScope(store: store, browser: browser)
            SettingsGroup(title: browser.text("приветствие", "Приветствие"), footnote: browser.text("с именем над поиском появляется приветствие, без имени остаётся знак mica. имя хранится только на этом Mac.", "С именем над поиском появляется приветствие, без имени остаётся знак mica. Имя хранится только на этом Mac.")) {
                NameSettingRows(store: store, browser: browser)
            }
            SettingsGroup(title: browser.text("что показывать", "Что показывать"), footnote: browser.text("стрелки меняют порядок разделов. частые сайты считаются по истории обычных окон и не показываются в окне инкогнито.", "Стрелки меняют порядок разделов. Частые сайты считаются по истории обычных окон и не показываются в окне инкогнито.")) {
                Toggle(browser.text("приветствие или знак mica", "Приветствие или знак mica"), isOn: $browser.prefs.start.wordmark).toggleStyle(MToggleStyle()).modifier(RowInset(divider: true))
                ForEach(ordered, id: \.self) { section in
                    let visible = start.sections.contains(section)
                    VStack(spacing: 0) {
                        HStack(spacing: Space.normal) {
                            Toggle(section.title(browser), isOn: Binding(get: { visible }, set: { value in withMotion(Motion.quick) { browser.prefs.start.setVisible(section, value) } })).toggleStyle(MToggleStyle())
                            HStack(spacing: 0) {
                                IconButton(symbol: "chevron.up", label: browser.text("выше", "Выше") + ": " + section.title(browser), size: 22) { withMotion(Motion.quick) { browser.prefs.start.shift(section, by: -1) } }.disabled(!visible || start.sections.first == section)
                                IconButton(symbol: "chevron.down", label: browser.text("ниже", "Ниже") + ": " + section.title(browser), size: 22) { withMotion(Motion.quick) { browser.prefs.start.shift(section, by: 1) } }.disabled(!visible || start.sections.last == section)
                            }
                        }
                        .font(.system(size: 13)).foregroundStyle(Palette.ink).padding(.horizontal, 14).padding(.vertical, 8)
                        Rectangle().fill(Palette.hairline).frame(height: 1).padding(.leading, 14)
                    }
                }
                SettingRow(title: browser.text("сайтов в разделе", "Сайтов в разделе"), detail: browser.text("во всех разделах, по столько же в ряд", "Во всех разделах, по столько же в ряд"), divider: false) {
                    Segmented(selection: $browser.prefs.start.frequentCount, options: StartPage.frequentChoices.map { ($0, String($0)) }, compact: true, width: 180, label: browser.text("сайтов в разделе", "Сайтов в разделе"))
                }
            }
            SettingsGroup(title: browser.text("свои сайты", "Свои сайты"), footnote: browser.text("на начальной странице плитки можно перетаскивать, контекстное меню изменяет и удаляет их.", "На начальной странице плитки можно перетаскивать, контекстное меню изменяет и удаляет их.")) {
                ForEach(Array(start.shortcuts.enumerated()), id: \.element.id) { index, shortcut in
                    SettingRow(title: shortcut.title.isEmpty ? (shortcut.url.host ?? shortcut.url.absoluteString) : shortcut.title, detail: shortcut.url.absoluteString, divider: true) {
                        HStack(spacing: 0) {
                            IconButton(symbol: "chevron.up", label: browser.text("выше", "Выше"), size: 22) { withMotion(Motion.quick) { browser.prefs.start.shiftShortcut(shortcut.id, by: -1) } }.disabled(index == 0)
                            IconButton(symbol: "chevron.down", label: browser.text("ниже", "Ниже"), size: 22) { withMotion(Motion.quick) { browser.prefs.start.shiftShortcut(shortcut.id, by: 1) } }.disabled(index == start.shortcuts.count - 1)
                            IconButton(symbol: "minus.circle", label: browser.text("удалить ", "Удалить ") + (shortcut.url.host ?? ""), size: 22) { withMotion(Motion.quick) { browser.prefs.start.shortcuts.removeAll { $0.id == shortcut.id } } }
                        }
                    }
                    .transition(.opacity)
                }
                ShortcutAddRow(store: store, browser: browser)
            }
            if !start.hiddenHosts.isEmpty {
                SettingsGroup(title: browser.text("скрытые из частых", "Скрытые из частых")) {
                    ForEach(Array(start.hiddenHosts.enumerated()), id: \.element) { index, host in
                        SettingRow(title: host, divider: index < start.hiddenHosts.count - 1) {
                            Button(browser.text("вернуть", "Вернуть")) { withMotion(Motion.quick) { browser.prefs.start.hiddenHosts.removeAll { $0 == host } } }.buttonStyle(MButtonStyle(kind: .ghost, compact: true))
                        }
                        .transition(.opacity)
                    }
                }
            }
        }
        .animation(Motion.quick, value: start)
    }
}

private struct ShortcutAddRow: View {
    @ObservedObject var store: Store
    @ObservedObject var browser: BrowserModel
    @State private var input = ""
    @State private var invalid = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Space.small) {
                MTextField(placeholder: browser.text("адрес сайта", "Адрес сайта"), text: $input, symbol: "plus") { add() }
                    .onChange(of: input) { _, value in store.settingsDraft = value; invalid = false }
                Button(browser.text("добавить", "Добавить")) { add() }.buttonStyle(MButtonStyle(kind: .secondary, compact: true)).disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if invalid { Text(browser.text("нужен адрес сайта, а не поисковый запрос", "Нужен адрес сайта, а не поисковый запрос")).font(.system(size: 11.5)).foregroundStyle(Palette.danger).transition(.opacity) }
        }
        .padding(10)
        .animation(Motion.hover, value: invalid)
    }
    private func add() {
        guard let url = StartPage.shortcutURL(input, engine: store.preferences.search) else { invalid = true; return }
        withMotion(Motion.quick) {
            browser.prefs.start.shortcuts.append(StartShortcut(title: "", url: url))
            browser.prefs.start.setVisible(.custom, true)
        }
        input = ""; store.settingsDraft = ""
    }
}
