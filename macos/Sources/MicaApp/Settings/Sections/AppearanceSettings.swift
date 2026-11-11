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
            SettingsGroup(title: browser.text("материал оболочки", "Материал оболочки"), footnote: browser.text("размытие и прозрачность относятся только к оболочке, страницы остаются непрозрачными. системные «уменьшить прозрачность» и «увеличить контраст» имеют приоритет.", "Размытие и прозрачность относятся только к оболочке, страницы остаются непрозрачными. Системные «Уменьшить прозрачность» и «Увеличить контраст» имеют приоритет.")) {
                Toggle(browser.text("матовое стекло", "Матовое стекло"), isOn: $browser.prefs.frosted).toggleStyle(MToggleStyle()).modifier(RowInset(divider: true))
                SettingRow(title: browser.text("прозрачность", "Прозрачность"), divider: false) {
                    HStack(spacing: Space.small) {
                        MSlider(value: $browser.prefs.transparency, range: 0...1, label: browser.text("прозрачность", "Прозрачность")).frame(width: 180)
                        Text(String(Int((browser.prefs.transparency * 100).rounded())) + "%").font(.system(size: 11.5).monospacedDigit()).foregroundStyle(Palette.text3).frame(width: 34, alignment: .trailing)
                    }
                    .disabled(!browser.prefs.frosted)
                }
            }
            SettingsGroup(title: browser.text("иконка приложения", "Иконка приложения"), footnote: browser.text("иконка меняется в Доке и переключателе приложений. если mica закреплена в Доке, иконка остаётся и после выхода. в Finder и Launchpad остаётся стандартная.", "Иконка меняется в Доке и переключателе приложений. Если mica закреплена в Доке, иконка остаётся и после выхода. В Finder и Launchpad остаётся стандартная.")) {
                IconPicker(store: store, browser: browser).padding(14)
            }
            SettingsGroup(title: browser.text("язык и текст", "Язык и текст"), footnote: browser.text("у каждого профиля свои язык и регистр, здесь они меняются для профиля этого окна. страницы сайтов, адреса и ваши данные не переводятся.", "У каждого профиля свои язык и регистр, здесь они меняются для профиля этого окна. Страницы сайтов, адреса и ваши данные не переводятся.")) {
                SettingRow(title: browser.text("язык", "Язык")) { LanguagePicker(store: store, browser: browser, width: 260) }
                SettingRow(title: browser.text("текст интерфейса", "Текст интерфейса"), divider: false) { CasePicker(store: store, browser: browser, width: 260) }
            }
        }
    }
}

/// Theme, and for the custom theme its light or dark base and accent. The shell behind and the preview update live.
struct ThemeGroup: View {
    @ObservedObject var store: Store
    @ObservedObject var browser: BrowserModel
    var body: some View {
        SettingsGroup(title: browser.text("тема", "Тема"), footnote: browser.prefs.theme == .custom ? browser.text("акцент окрашивает оболочку, переключатели, основные кнопки и индикатор загрузки. страницы сайтов не меняются.", "Акцент окрашивает оболочку, переключатели, основные кнопки и индикатор загрузки. Страницы сайтов не меняются.") : nil) {
            SettingRow(title: browser.text("тема", "Тема"), divider: browser.prefs.theme == .custom) { ThemePicker(store: store, browser: browser, width: 380) }
            if browser.prefs.theme == .custom {
                SettingRow(title: browser.text("основа", "Основа")) {
                    Segmented(selection: $browser.prefs.customBase, options: [(.system, browser.text("как в системе", "Как в системе")), (.light, browser.text("светлая", "Светлая")), (.dark, browser.text("тёмная", "Тёмная"))], width: 380, label: browser.text("основа темы", "Основа темы"))
                }
                .transition(.opacity)
                SettingRow(title: browser.text("акцент", "Акцент")) { AccentPicker(store: store, browser: browser) }
                    .transition(.opacity)
                SettingRow(title: browser.text("цвет оболочки", "Цвет оболочки"), detail: browser.text("насколько акцент окрашивает фон окна", "Насколько акцент окрашивает фон окна"), divider: false) {
                    HStack(spacing: Space.small) {
                        MSlider(value: $browser.prefs.customTint, range: 0...0.6, label: browser.text("цвет оболочки", "Цвет оболочки")).frame(width: 180)
                        Text(String(Int((browser.prefs.customTint / 0.6 * 100).rounded())) + "%").font(.system(size: 11.5).monospacedDigit()).foregroundStyle(Palette.text3).frame(width: 34, alignment: .trailing)
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(Motion.quick, value: browser.prefs.theme)
    }
}
