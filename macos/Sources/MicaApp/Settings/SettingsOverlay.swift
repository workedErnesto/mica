import AppKit
import SwiftUI
import AVFoundation
import MicaCore

/// Settings float over the window: clicking the dimmed area or pressing Esc closes them.
struct SettingsOverlay: View {
    @ObservedObject var store: Store
    @ObservedObject var browser: BrowserModel
    var body: some View {
        ModalCard(width: 860, height: 660, onDismiss: requestClose) {
            SettingsView(store: store, browser: browser, dismiss: requestClose)
        }
    }
    private func requestClose() {
        guard !store.settingsDraft.trimmingCharacters(in: .whitespaces).isEmpty else { store.settingsDraft = ""; browser.showSettings = false; return }
        Task {
            let answer = await ask(title: browser.text("адрес не добавлен", "Адрес не добавлен"), detail: browser.text("введённый адрес «", "Введённый адрес «") + store.settingsDraft + browser.text("» ещё не сохранён в списке.", "» ещё не сохранён в списке."), buttons: [browser.text("продолжить редактирование", "Продолжить редактирование"), browser.text("закрыть без сохранения", "Закрыть без сохранения")], window: browser.controller?.window, destructive: true)
            if answer == 1 { store.settingsDraft = ""; browser.showSettings = false }
        }
    }
}
