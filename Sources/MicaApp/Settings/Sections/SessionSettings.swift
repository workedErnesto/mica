import AppKit
import SwiftUI
import AVFoundation
import MicaCore

struct SessionSettings: View {
    @ObservedObject var store: Store
    var body: some View {
        VStack(alignment: .leading, spacing: Space.section) {
            SettingsGroup(title: store.text("при запуске", "При запуске"), footnote: store.text("это касается только запуска. открытые вами вкладки остаются живыми, включая фоновые. несохранённые формы после сбоя не восстанавливаются.", "Это касается только запуска. Открытые вами вкладки остаются живыми, включая фоновые. Несохранённые формы после сбоя не восстанавливаются.")) {
                Toggle(store.text("восстанавливать окна и вкладки", "Восстанавливать окна и вкладки"), isOn: $store.preferences.restore).toggleStyle(MToggleStyle()).modifier(RowInset(divider: true))
                Toggle(store.text("загружать сохранённые вкладки при выборе", "Загружать сохранённые вкладки при выборе"), isOn: $store.preferences.lazyRestore).toggleStyle(MToggleStyle()).modifier(RowInset(divider: false)).disabled(!store.preferences.restore)
            }
            SettingsGroup(title: store.text("всегда загружать при запуске", "Всегда загружать при запуске"), footnote: store.text("например, почта или мессенджер, которым нужны уведомления сразу", "Например, почта или мессенджер, которым нужны уведомления сразу")) {
                HostListEditor(hosts: $store.preferences.eagerHosts, store: store)
            }
            SettingsGroup(title: store.text("память", "Память"), footnote: store.text("публичный WebKit не позволяет надёжно определить звонки, формы и WebSocket, поэтому mica не выгружает живые вкладки. автоматического таймера выгрузки нет.", "Публичный WebKit не позволяет надёжно определить звонки, формы и WebSocket, поэтому mica не выгружает живые вкладки. Автоматического таймера выгрузки нет.")) {
                SettingRow(title: store.text("выгрузка живых вкладок", "Выгрузка живых вкладок"), divider: false) { Text(store.text("выключена", "Выключена")).font(.system(size: 12)).foregroundStyle(Palette.text3) }
            }
        }
    }
}
