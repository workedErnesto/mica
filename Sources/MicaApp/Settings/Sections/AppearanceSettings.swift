import AppKit
import SwiftUI
import AVFoundation
import MicaCore

struct AppearanceSettings: View {
    @ObservedObject var store: Store
    var body: some View {
        VStack(alignment: .leading, spacing: Space.section) {
            LayoutPreview(store: store).frame(height: 168)
            ThemeGroup(store: store)
            SettingsGroup(title: store.text("материал оболочки", "Материал оболочки"), footnote: store.text("размытие и прозрачность относятся только к оболочке, страницы остаются непрозрачными. системные «уменьшить прозрачность» и «увеличить контраст» имеют приоритет.", "Размытие и прозрачность относятся только к оболочке, страницы остаются непрозрачными. Системные «Уменьшить прозрачность» и «Увеличить контраст» имеют приоритет.")) {
                Toggle(store.text("матовое стекло", "Матовое стекло"), isOn: $store.preferences.frosted).toggleStyle(MToggleStyle()).modifier(RowInset(divider: true))
                SettingRow(title: store.text("прозрачность", "Прозрачность"), divider: false) {
                    HStack(spacing: Space.small) {
                        MSlider(value: $store.preferences.transparency, range: 0...1, label: store.text("прозрачность", "Прозрачность")).frame(width: 180)
                        Text(String(Int((store.preferences.transparency * 100).rounded())) + "%").font(.system(size: 11.5).monospacedDigit()).foregroundStyle(Palette.text3).frame(width: 34, alignment: .trailing)
                    }
                    .disabled(!store.preferences.frosted)
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
    var body: some View {
        SettingsGroup(title: store.text("тема", "Тема"), footnote: store.preferences.theme == .custom ? store.text("акцент окрашивает оболочку, переключатели, основные кнопки и индикатор загрузки. страницы сайтов не меняются.", "Акцент окрашивает оболочку, переключатели, основные кнопки и индикатор загрузки. Страницы сайтов не меняются.") : nil) {
            SettingRow(title: store.text("тема", "Тема"), divider: store.preferences.theme == .custom) { ThemePicker(store: store, width: 380) }
            if store.preferences.theme == .custom {
                SettingRow(title: store.text("основа", "Основа")) {
                    Segmented(selection: $store.preferences.customBase, options: [(.system, store.text("как в системе", "Как в системе")), (.light, store.text("светлая", "Светлая")), (.dark, store.text("тёмная", "Тёмная"))], width: 380, label: store.text("основа темы", "Основа темы"))
                }
                .transition(.opacity)
                SettingRow(title: store.text("акцент", "Акцент")) { AccentPicker(store: store) }
                    .transition(.opacity)
                SettingRow(title: store.text("цвет оболочки", "Цвет оболочки"), detail: store.text("насколько акцент окрашивает фон окна", "Насколько акцент окрашивает фон окна"), divider: false) {
                    HStack(spacing: Space.small) {
                        MSlider(value: $store.preferences.customTint, range: 0...0.6, label: store.text("цвет оболочки", "Цвет оболочки")).frame(width: 180)
                        Text(String(Int((store.preferences.customTint / 0.6 * 100).rounded())) + "%").font(.system(size: 11.5).monospacedDigit()).foregroundStyle(Palette.text3).frame(width: 34, alignment: .trailing)
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(Motion.quick, value: store.preferences.theme)
    }
}
