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
                    PasswordRow(login: login, browser: browser, revealed: revealed == login.id, copied: copied == login.id,
                                reveal: {
                                    if revealed == login.id { withMotion(Motion.quick) { revealed = nil } }
                                    else { Task { if await passwords.authenticate() { withMotion(Motion.quick) { revealed = login.id } } } }
                                },
                                copy: {
                                    Task {
                                        guard await passwords.authenticate() else { return }
                                        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(login.password, forType: .string)
                                        withMotion(Motion.quick) { copied = login.id }
                                        try? await Task.sleep(for: .seconds(1.6))
                                        if copied == login.id { withMotion(Motion.quick) { copied = nil } }
                                    }
                                },
                                remove: { deleting = login })
                        .transition(.opacity)
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

/// A saved account: the site's icon and host, the user name under it, the password once revealed.
/// Show, copy and remove are icon buttons at the trailing edge, like the other list rows of settings.
private struct PasswordRow: View {
    let login: SavedLogin
    @ObservedObject var browser: BrowserModel
    let revealed: Bool
    let copied: Bool
    let reveal: () -> Void
    let copy: () -> Void
    let remove: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Palette.hairline).frame(height: 1).padding(.leading, 14)
            HStack(alignment: .center, spacing: Space.normal) {
                SiteIcon(url: URL(string: login.origin), favicons: browser.favicons, size: Chrome.rowIcon, tiled: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(login.host).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.ink)
                        .lineLimit(1).truncationMode(.middle).help(login.origin)
                    Text(login.username.isEmpty ? browser.text("без имени пользователя", "Без имени пользователя") : login.username)
                        .font(.system(size: 12)).foregroundStyle(login.username.isEmpty ? Palette.text3 : Palette.text2)
                        .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    if revealed {
                        Text(login.password).font(.system(size: 12.5, design: .monospaced)).foregroundStyle(Palette.ink)
                            .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                            .transition(.opacity)
                    }
                }
                Spacer(minLength: Space.small)
                HStack(spacing: 2) {
                    IconButton(symbol: revealed ? "eye.slash" : "eye", label: revealed ? browser.text("скрыть", "Скрыть") : browser.text("показать", "Показать"), selected: revealed, action: reveal)
                    IconButton(symbol: copied ? "checkmark" : "square.on.square", label: copied ? browser.text("скопировано", "Скопировано") : browser.text("копировать", "Копировать"), action: copy)
                        .contentTransition(.symbolEffect(.replace))
                    IconButton(symbol: "trash", label: browser.text("удалить", "Удалить"), action: remove)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
    }
}
