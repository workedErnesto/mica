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
            DefaultBrowserSetting(store: store, browser: browser)
            ProfileScope(store: store, browser: browser)
            LayoutPreview(store: store, browser: browser).frame(height: 168)
            SettingsGroup(title: browser.text("раскладка", "Раскладка"), footnote: browser.text("при ширине окна меньше 760 pt вкладки временно переходят наверх. в свёрнутой боковой панели остаются иконки сайтов, ⌃⌘S.", "При ширине окна меньше 760 pt вкладки временно переходят наверх. В свёрнутой боковой панели остаются иконки сайтов, ⌃⌘S.")) {
                SettingRow(title: browser.text("вкладки", "Вкладки")) { LayoutPicker(store: store, browser: browser, width: 260) }
                Toggle(browser.text("свернуть боковую панель до иконок", "Свернуть боковую панель до иконок"), isOn: Binding(get: { browser.prefs.sidebarCollapsed }, set: { value in withMotion(Motion.panel) { browser.prefs.sidebarCollapsed = value } })).toggleStyle(MToggleStyle()).modifier(RowInset(divider: false)).disabled(browser.prefs.layout.horizontal)
            }
            SettingsGroup(title: browser.text("панель инструментов", "Панель инструментов"), footnote: browser.text("кнопки расставляются перетаскиванием прямо в окне: в шапку, вниз боковой панели или обратно в набор. то же меню есть по правому клику на шапке.", "Кнопки расставляются перетаскиванием прямо в окне: в шапку, вниз боковой панели или обратно в набор. То же меню есть по правому клику на шапке.")) {
                SettingRow(title: browser.text("кнопки и адресная строка", "Кнопки и адресная строка"), detail: browser.text("порядок, сторона и длина строки", "Порядок, сторона и длина строки"), divider: false) {
                    Button(browser.text("настроить", "Настроить")) { dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { browser.customizingToolbar = true } }.buttonStyle(MButtonStyle(kind: .secondary, compact: true))
                }
            }
            AddressSettings(browser: browser)
        }
    }
}

/// What the address field shows. The sample above the options is drawn by the same view as the field itself, and the
/// field in the window changes along with it.
struct AddressSettings: View {
    @ObservedObject var browser: BrowserModel
    static let sample = "https://shop.example.com/shoes/running?size=42"
    var body: some View {
        let style = browser.prefs.address
        SettingsGroup(title: browser.text("адресная строка", "Адресная строка"), footnote: browser.text("домен сайта всегда остаётся основным цветом, по нему видно, чей это адрес.", "Домен сайта всегда остаётся основным цветом, по нему видно, чей это адрес.")) {
            sample(style).modifier(RowInset(divider: true))
            SettingRow(title: browser.text("показывать", "Показывать")) {
                Segmented(selection: binding(\.full), options: [(false, browser.text("сайт", "Сайт")), (true, browser.text("полный адрес", "Полный адрес"))], width: 260, label: browser.text("что показывать в адресной строке", "Что показывать в адресной строке"))
            }
            toggle(browser.text("приглушать поддомен", "Приглушать поддомен"), detail: style.full ? browser.text("www и всё, что стоит перед доменом", "www и всё, что стоит перед доменом") : browser.text("всё, что стоит перед доменом", "Всё, что стоит перед доменом"), value: binding(\.dimSubdomain), divider: style.full)
            if style.full {
                toggle(browser.text("приглушать путь", "Приглушать путь"), detail: browser.text("всё, что после домена: /shoes, ?size и #", "Всё, что после домена: /shoes, ?size и #"), value: binding(\.dimPath), divider: false)
                    .transition(.opacity)
            }
        }
        .animation(Motion.quick, value: style.full)
    }
    /// The sample sits in a copy of the address field so it reads at the same size and on the same fill.
    private func sample(_ style: AddressStyle) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill").font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.text3)
            AddressText(address: Self.sample, style: style).font(.system(size: 12.5)).lineLimit(1).truncationMode(.middle)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: Chrome.field)
        .background(RoundedRectangle(cornerRadius: Radius.icon, style: .continuous).fill(Palette.field))
        .overlay(RoundedRectangle(cornerRadius: Radius.icon, style: .continuous).strokeBorder(Palette.fieldBorder, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(browser.text("пример адресной строки", "Пример адресной строки"))
    }
    private func toggle(_ title: String, detail: String, value: Binding<Bool>, divider: Bool) -> some View {
        Toggle(isOn: value) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.system(size: 11.5)).foregroundStyle(Palette.text3)
            }
        }
        .toggleStyle(MToggleStyle()).modifier(RowInset(divider: divider))
    }
    private func binding(_ key: WritableKeyPath<AddressStyle, Bool>) -> Binding<Bool> {
        Binding(get: { browser.prefs.address[keyPath: key] }, set: { value in browser.prefs.address[keyPath: key] = value })
    }
}
