import AppKit
import SwiftUI
import AVFoundation
import MicaCore

struct AppearanceSettings: View {
    @ObservedObject var store: Store
    @ObservedObject var browser: BrowserModel
    var body: some View {
        VStack(alignment: .leading, spacing: Space.section) {
            ProfileScope(store: store, browser: browser)
            LayoutPreview(store: store, browser: browser).frame(height: 168)
            ThemeGroup(store: store, browser: browser)
            SettingsGroup(title: store.text("материал оболочки", "Материал оболочки"), footnote: store.text("размытие и прозрачность относятся только к оболочке, страницы остаются непрозрачными. системные «уменьшить прозрачность» и «увеличить контраст» имеют приоритет.", "Размытие и прозрачность относятся только к оболочке, страницы остаются непрозрачными. Системные «Уменьшить прозрачность» и «Увеличить контраст» имеют приоритет.")) {
                Toggle(store.text("матовое стекло", "Матовое стекло"), isOn: $browser.prefs.frosted).toggleStyle(MToggleStyle()).modifier(RowInset(divider: true))
                SettingRow(title: store.text("прозрачность", "Прозрачность"), divider: false) {
                    HStack(spacing: Space.small) {
                        MSlider(value: $browser.prefs.transparency, range: 0...1, label: store.text("прозрачность", "Прозрачность")).frame(width: 180)
                        Text(String(Int((browser.prefs.transparency * 100).rounded())) + "%").font(.system(size: 11.5).monospacedDigit()).foregroundStyle(Palette.text3).frame(width: 34, alignment: .trailing)
                    }
                    .disabled(!browser.prefs.frosted)
                }
            }
            SettingsGroup(title: store.text("иконка приложения", "Иконка приложения"), footnote: store.text("иконка меняется в Доке и переключателе приложений. если mica закреплена в Доке, иконка остаётся и после выхода. в Finder и Launchpad остаётся стандартная.", "Иконка меняется в Доке и переключателе приложений. Если mica закреплена в Доке, иконка остаётся и после выхода. В Finder и Launchpad остаётся стандартная.")) {
                IconPicker(store: store).padding(14)
            }
            SettingsGroup(title: store.text("язык и текст", "Язык и текст"), footnote: store.text("язык меняет только интерфейс mica. страницы сайтов, адреса и ваши данные не переводятся.", "Язык меняет только интерфейс mica. Страницы сайтов, адреса и ваши данные не переводятся.")) {
                SettingRow(title: store.text("язык", "Язык")) { LanguagePicker(store: store, width: 260) }
                SettingRow(title: store.text("текст интерфейса", "Текст интерфейса"), divider: false) { CasePicker(store: store, width: 260) }
            }
        }
    }
}

/// Theme, and for the custom theme its light or dark base and accent. The shell behind and the preview update live.
struct ThemeGroup: View {
    @ObservedObject var store: Store
    @ObservedObject var browser: BrowserModel
    var body: some View {
        SettingsGroup(title: store.text("тема", "Тема"), footnote: browser.prefs.theme == .custom ? store.text("акцент окрашивает оболочку, переключатели, основные кнопки и индикатор загрузки. страницы сайтов не меняются.", "Акцент окрашивает оболочку, переключатели, основные кнопки и индикатор загрузки. Страницы сайтов не меняются.") : nil) {
            SettingRow(title: store.text("тема", "Тема"), divider: browser.prefs.theme == .custom) { ThemePicker(store: store, browser: browser, width: 380) }
            if browser.prefs.theme == .custom {
                SettingRow(title: store.text("основа", "Основа")) {
                    Segmented(selection: $browser.prefs.customBase, options: [(.system, store.text("как в системе", "Как в системе")), (.light, store.text("светлая", "Светлая")), (.dark, store.text("тёмная", "Тёмная"))], width: 380, label: store.text("основа темы", "Основа темы"))
                }
                .transition(.opacity)
                SettingRow(title: store.text("акцент", "Акцент")) { AccentPicker(store: store, browser: browser) }
                    .transition(.opacity)
                SettingRow(title: store.text("цвет оболочки", "Цвет оболочки"), detail: store.text("насколько акцент окрашивает фон окна", "Насколько акцент окрашивает фон окна"), divider: false) {
                    HStack(spacing: Space.small) {
                        MSlider(value: $browser.prefs.customTint, range: 0...0.6, label: store.text("цвет оболочки", "Цвет оболочки")).frame(width: 180)
                        Text(String(Int((browser.prefs.customTint / 0.6 * 100).rounded())) + "%").font(.system(size: 11.5).monospacedDigit()).foregroundStyle(Palette.text3).frame(width: 34, alignment: .trailing)
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(Motion.quick, value: browser.prefs.theme)
    }
}
