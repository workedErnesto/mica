import AppKit
import SwiftUI
import AVFoundation
import MicaCore

struct StartSettings: View {
    @ObservedObject var store: Store
    var body: some View {
        let start = store.preferences.start
        let ordered = start.sections + StartSection.allCases.filter { !start.sections.contains($0) }
        VStack(alignment: .leading, spacing: Space.section) {
            SettingsGroup(title: store.text("приветствие", "Приветствие"), footnote: store.text("с именем над поиском появляется приветствие, без имени остаётся знак mica. имя хранится только на этом Mac.", "С именем над поиском появляется приветствие, без имени остаётся знак mica. Имя хранится только на этом Mac.")) {
                NameSettingRows(store: store)
            }
            SettingsGroup(title: store.text("что показывать", "Что показывать"), footnote: store.text("стрелки меняют порядок разделов. частые сайты считаются по истории обычных окон и не показываются в окне инкогнито.", "Стрелки меняют порядок разделов. Частые сайты считаются по истории обычных окон и не показываются в окне инкогнито.")) {
                Toggle(store.text("приветствие или знак mica", "Приветствие или знак mica"), isOn: $store.preferences.start.wordmark).toggleStyle(MToggleStyle()).modifier(RowInset(divider: true))
                ForEach(ordered, id: \.self) { section in
                    let visible = start.sections.contains(section)
                    VStack(spacing: 0) {
                        HStack(spacing: Space.normal) {
                            Toggle(section.title(store), isOn: Binding(get: { visible }, set: { value in withMotion(Motion.quick) { store.preferences.start.setVisible(section, value) } })).toggleStyle(MToggleStyle())
                            HStack(spacing: 0) {
                                IconButton(symbol: "chevron.up", label: store.text("выше", "Выше") + ": " + section.title(store), size: 22) { withMotion(Motion.quick) { store.preferences.start.shift(section, by: -1) } }.disabled(!visible || start.sections.first == section)
                                IconButton(symbol: "chevron.down", label: store.text("ниже", "Ниже") + ": " + section.title(store), size: 22) { withMotion(Motion.quick) { store.preferences.start.shift(section, by: 1) } }.disabled(!visible || start.sections.last == section)
                            }
                        }
                        .font(.system(size: 13)).foregroundStyle(Palette.ink).padding(.horizontal, 14).padding(.vertical, 8)
                        Rectangle().fill(Palette.hairline).frame(height: 1).padding(.leading, 14)
                    }
                }
                SettingRow(title: store.text("сайтов в разделе", "Сайтов в разделе"), detail: store.text("для частых сайтов и закладок", "Для частых сайтов и закладок"), divider: false) {
                    Segmented(selection: $store.preferences.start.frequentCount, options: StartPage.frequentChoices.map { ($0, String($0)) }, compact: true, width: 180, label: store.text("сайтов в разделе", "Сайтов в разделе"))
                }
            }
            SettingsGroup(title: store.text("свои сайты", "Свои сайты"), footnote: store.text("на начальной странице плитки можно перетаскивать, контекстное меню изменяет и удаляет их.", "На начальной странице плитки можно перетаскивать, контекстное меню изменяет и удаляет их.")) {
                ForEach(Array(start.shortcuts.enumerated()), id: \.element.id) { index, shortcut in
                    SettingRow(title: shortcut.title.isEmpty ? (shortcut.url.host ?? shortcut.url.absoluteString) : shortcut.title, detail: shortcut.url.absoluteString, divider: true) {
                        HStack(spacing: 0) {
                            IconButton(symbol: "chevron.up", label: store.text("выше", "Выше"), size: 22) { withMotion(Motion.quick) { store.preferences.start.shiftShortcut(shortcut.id, by: -1) } }.disabled(index == 0)
                            IconButton(symbol: "chevron.down", label: store.text("ниже", "Ниже"), size: 22) { withMotion(Motion.quick) { store.preferences.start.shiftShortcut(shortcut.id, by: 1) } }.disabled(index == start.shortcuts.count - 1)
                            IconButton(symbol: "minus.circle", label: store.text("удалить ", "Удалить ") + (shortcut.url.host ?? ""), size: 22) { withMotion(Motion.quick) { store.preferences.start.shortcuts.removeAll { $0.id == shortcut.id } } }
                        }
                    }
                    .transition(.opacity)
                }
                ShortcutAddRow(store: store)
            }
            if !start.hiddenHosts.isEmpty {
                SettingsGroup(title: store.text("скрытые из частых", "Скрытые из частых")) {
                    ForEach(Array(start.hiddenHosts.enumerated()), id: \.element) { index, host in
                        SettingRow(title: host, divider: index < start.hiddenHosts.count - 1) {
                            Button(store.text("вернуть", "Вернуть")) { withMotion(Motion.quick) { store.preferences.start.hiddenHosts.removeAll { $0 == host } } }.buttonStyle(MButtonStyle(kind: .ghost, compact: true))
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
    @State private var input = ""
    @State private var invalid = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Space.small) {
                MTextField(placeholder: store.text("адрес сайта", "Адрес сайта"), text: $input, symbol: "plus") { add() }
                    .onChange(of: input) { _, value in store.settingsDraft = value; invalid = false }
                Button(store.text("добавить", "Добавить")) { add() }.buttonStyle(MButtonStyle(kind: .secondary, compact: true)).disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if invalid { Text(store.text("нужен адрес сайта, а не поисковый запрос", "Нужен адрес сайта, а не поисковый запрос")).font(.system(size: 11.5)).foregroundStyle(Palette.danger).transition(.opacity) }
        }
        .padding(10)
        .animation(Motion.hover, value: invalid)
    }
    private func add() {
        guard let url = StartPage.shortcutURL(input, engine: store.preferences.search) else { invalid = true; return }
        withMotion(Motion.quick) {
            store.preferences.start.shortcuts.append(StartShortcut(title: "", url: url))
            store.preferences.start.setVisible(.custom, true)
        }
        input = ""; store.settingsDraft = ""
    }
}
