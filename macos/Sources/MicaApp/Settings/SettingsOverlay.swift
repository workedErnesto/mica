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
            let answer = await ask(title: store.text("адрес не добавлен", "Адрес не добавлен"), detail: store.text("введённый адрес «", "Введённый адрес «") + store.settingsDraft + store.text("» ещё не сохранён в списке.", "» ещё не сохранён в списке."), buttons: [store.text("продолжить редактирование", "Продолжить редактирование"), store.text("закрыть без сохранения", "Закрыть без сохранения")], window: browser.controller?.window)
            if answer == 1 { store.settingsDraft = ""; browser.showSettings = false }
        }
    }
}
