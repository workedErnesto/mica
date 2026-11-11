import AppKit
import SwiftUI
import MicaCore

struct PasswordSettings: View {
    @ObservedObject var store: Store
    @ObservedObject var browser: BrowserModel
    @ObservedObject var passwords: Passwords
    @State private var query = ""
    @State private var revealed: UUID?
    @State private var copied: UUID?
    @State private var deleting: SavedLogin?

    private var results: [SavedLogin] {
        passwords.vault.logins.filter { query.isEmpty || $0.host.localizedCaseInsensitiveContains(query) || $0.username.localizedCaseInsensitiveContains(query) }
            .sorted { $0.host.localizedCaseInsensitiveCompare($1.host) == .orderedAscending }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: Space.section) {
            SettingsGroup(title: browser.text("автозаполнение", "Автозаполнение")) {
                Toggle(browser.text("предлагать сохранение и создание паролей", "Предлагать сохранение и создание паролей"), isOn: $store.preferences.offerPasswords)
                    .toggleStyle(MToggleStyle()).modifier(RowInset(divider: true))
                Toggle(browser.text("предлагать сохранённые учётные записи", "Предлагать сохранённые учётные записи"), isOn: $store.preferences.fillPasswords)
                    .toggleStyle(MToggleStyle()).modifier(RowInset(divider: false))
            }
            if passwords.loading {
                Text(browser.text("открываем хранилище…", "Открываем хранилище…")).foregroundStyle(Palette.text3)
            }
            if let error = passwords.error {
                Text(browser.text("хранилище недоступно: ", "Хранилище недоступно: ") + error).foregroundStyle(Palette.text2).textSelection(.enabled)
            }
            SettingsGroup(title: browser.text("сохранённые пароли", "Сохранённые пароли")) {
                MTextField(placeholder: browser.text("поиск по сайту или имени", "Поиск по сайту или имени"), text: $query, symbol: "magnifyingglass").padding(14)
                if results.isEmpty && !passwords.loading && passwords.error == nil {
                    Text(browser.text("пароли не найдены", "Пароли не найдены")).foregroundStyle(Palette.text3).padding(14)
                }
                ForEach(results) { login in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(login.origin).font(.system(size: 13, weight: .medium)).textSelection(.enabled)
                        Text(login.username.isEmpty ? browser.text("без имени пользователя", "Без имени пользователя") : login.username).foregroundStyle(Palette.text2).textSelection(.enabled)
                        if revealed == login.id { Text(login.password).textSelection(.enabled) }
                        HStack {
                            Button(revealed == login.id ? browser.text("скрыть", "Скрыть") : browser.text("показать", "Показать")) {
                                if revealed == login.id { revealed = nil }
                                else { Task { if await passwords.authenticate() { revealed = login.id } } }
                            }
                            Button(browser.text("копировать", "Копировать")) {
                                Task { if await passwords.authenticate() { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(login.password, forType: .string); copied = login.id } }
                            }
                            Button(browser.text("удалить", "Удалить")) { deleting = login }
                            if copied == login.id { Text(browser.text("скопировано", "Скопировано")).foregroundStyle(Palette.text3) }
                        }.buttonStyle(MButtonStyle(kind: .secondary, compact: true))
                    }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    Rectangle().fill(Palette.hairline).frame(height: 1)
                }
            }
            SettingsGroup(title: browser.text("сайты без сохранения", "Сайты без сохранения")) {
                if passwords.vault.never.isEmpty && !passwords.loading && passwords.error == nil { Text(browser.text("исключений нет", "Исключений нет")).foregroundStyle(Palette.text3).padding(14) }
                ForEach(passwords.vault.never, id: \.self) { origin in
                    SettingRow(title: origin, divider: true) {
                        Button(browser.text("удалить", "Удалить")) { passwords.update { $0.never.removeAll { $0 == origin } } }.buttonStyle(MButtonStyle(kind: .secondary, compact: true))
                    }
                }
            }
        }
        .onDisappear { revealed = nil; copied = nil }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in revealed = nil }
        .alert(browser.text("удалить пароль?", "Удалить пароль?"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), presenting: deleting) { login in
            Button(browser.text("удалить", "Удалить"), role: .destructive) { passwords.update { $0.logins.removeAll { $0.id == login.id } }; if revealed == login.id { revealed = nil }; deleting = nil }
            Button(browser.text("отмена", "Отмена"), role: .cancel) { deleting = nil }
        } message: { login in Text(login.origin + "\n" + login.username) }
    }
}
