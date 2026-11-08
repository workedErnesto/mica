import AppKit
import SwiftUI
import AVFoundation
import MicaCore

struct SpaceSettings: View {
    @ObservedObject var store: Store
    @ObservedObject var browser: BrowserModel
    let dismiss: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: Space.section) {
            DefaultBrowserSetting(store: store)
            LayoutPreview(store: store).frame(height: 168)
            SettingsGroup(title: store.text("раскладка", "Раскладка"), footnote: store.text("при ширине окна меньше 760 pt вкладки временно переходят наверх. в свёрнутой боковой панели остаются иконки сайтов, ⌃⌘S.", "При ширине окна меньше 760 pt вкладки временно переходят наверх. В свёрнутой боковой панели остаются иконки сайтов, ⌃⌘S.")) {
                SettingRow(title: store.text("вкладки", "Вкладки")) { LayoutPicker(store: store, width: 260) }
                Toggle(store.text("свернуть боковую панель до иконок", "Свернуть боковую панель до иконок"), isOn: Binding(get: { store.preferences.sidebarCollapsed }, set: { value in withMotion(Motion.panel) { store.preferences.sidebarCollapsed = value } })).toggleStyle(MToggleStyle()).modifier(RowInset(divider: false)).disabled(store.preferences.layout.horizontal)
            }
            SettingsGroup(title: store.text("панель инструментов", "Панель инструментов"), footnote: store.text("кнопки расставляются перетаскиванием прямо в окне: в шапку, вниз боковой панели или обратно в набор. то же меню есть по правому клику на шапке.", "Кнопки расставляются перетаскиванием прямо в окне: в шапку, вниз боковой панели или обратно в набор. То же меню есть по правому клику на шапке.")) {
                SettingRow(title: store.text("кнопки и адресная строка", "Кнопки и адресная строка"), detail: store.text("порядок, сторона и длина строки", "Порядок, сторона и длина строки"), divider: false) {
                    Button(store.text("настроить", "Настроить")) { dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { browser.customizingToolbar = true } }.buttonStyle(MButtonStyle(kind: .secondary, compact: true))
                }
            }
        }
    }
}
