import AppKit
import SwiftUI
import AVFoundation
import UserNotifications
import MicaCore

struct PermissionSettings: View {
    @ObservedObject var store: Store
    @ObservedObject var browser: BrowserModel
    @State private var notificationStatus: UNAuthorizationStatus?
    var body: some View {
        VStack(alignment: .leading, spacing: Space.section) {
            SettingsGroup(title: "macOS", footnote: browser.text("системный доступ меняется в настройках конфиденциальности macOS", "Системный доступ меняется в настройках конфиденциальности macOS")) {
                ForEach(SiteCapability.allCases, id: \.self) { capability in
                    SettingRow(title: store.capabilityName(capability), divider: true) { Text(systemStatus(capability)).font(.system(size: 12)).foregroundStyle(Palette.text2) }
                }
                SettingRow(title: browser.text("системные настройки", "Системные настройки"), divider: false) {
                    Button(browser.text("открыть", "Открыть")) { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")!) }.buttonStyle(MButtonStyle(kind: .secondary, compact: true))
                }
            }
            SettingsGroup(title: browser.text("уведомления сайтов", "Уведомления сайтов"), footnote: browser.text("уведомления приходят от открытых вкладок. push-уведомления закрытых сайтов не поддерживаются. в окнах инкогнито уведомления запрещены.", "Уведомления приходят от открытых вкладок. Push-уведомления закрытых сайтов не поддерживаются. В окнах инкогнито уведомления запрещены.")) {
                Toggle(browser.text("сайты могут спрашивать разрешение", "Сайты могут спрашивать разрешение"), isOn: $store.preferences.notificationRequests)
                    .toggleStyle(MToggleStyle()).modifier(RowInset(divider: false))
            }
            SettingsGroup(title: browser.text("решения для сайтов", "Решения для сайтов"), footnote: browser.text("решения окон инкогнито существуют только внутри окна. геолокация недоступна для управления через публичный API этой версии.", "Решения окон инкогнито существуют только внутри окна. Геолокация недоступна для управления через публичный API этой версии.")) {
                if store.permissions.isEmpty {
                    Text(browser.text("сайты пока ничего не запрашивали", "Сайты пока ничего не запрашивали")).font(.system(size: 13)).foregroundStyle(Palette.text3).frame(maxWidth: .infinity, alignment: .leading).padding(14)
                }
                ForEach(Array(store.permissions.enumerated()), id: \.element.id) { index, record in
                    SettingRow(title: record.origin, detail: store.capabilityName(record.capability), divider: index < store.permissions.count - 1) {
                        Segmented(selection: Binding(get: { store.permissions.first { $0.id == record.id }?.decision ?? .ask }, set: { store.setPermission(origin: record.origin, capability: record.capability, decision: $0) }), options: [(.ask, browser.text("спрашивать", "Спрашивать")), (.allow, browser.text("разрешить", "Разрешить")), (.deny, browser.text("запретить", "Запретить"))], compact: true, width: 270, label: record.origin)
                    }
                }
            }
            if !store.appLinks.isEmpty {
                SettingsGroup(title: browser.text("ссылки в приложениях", "Ссылки в приложениях"), footnote: browser.text("эти сайты открывают такие ссылки без вопроса", "Эти сайты открывают такие ссылки без вопроса")) {
                    ForEach(Array(store.appLinks.enumerated()), id: \.element.id) { index, record in
                        SettingRow(title: record.origin, detail: appLinkDetail(record), divider: index < store.appLinks.count - 1) {
                            Button(browser.text("удалить", "Удалить")) { store.appLinks.removeAll { $0 == record } }
                                .buttonStyle(MButtonStyle(kind: .secondary, compact: true))
                        }
                    }
                }
            }
        }
        .task { notificationStatus = await store.notifier.status() }
    }
    /// The app the system opens for the scheme now, then the scheme: "Telegram, tg:".
    private func appLinkDetail(_ record: AppLinkPermission) -> String {
        guard let link = URL(string: record.scheme + ":"), let app = NSWorkspace.shared.urlForApplication(toOpen: link) else { return record.scheme + ":" }
        var name = FileManager.default.displayName(atPath: app.path)
        if name.hasSuffix(".app") { name.removeLast(4) }
        return name + ", " + record.scheme + ":"
    }
    private func systemStatus(_ capability: SiteCapability) -> String {
        if capability == .notifications {
            switch notificationStatus {
            case .authorized?, .provisional?, .ephemeral?: return browser.text("разрешено", "Разрешено")
            case .denied?: return browser.text("запрещено", "Запрещено")
            case .notDetermined?: return browser.text("ещё не запрашивалось", "Ещё не запрашивалось")
            default: return browser.text("проверяем…", "Проверяем…")
            }
        }
        switch AVCaptureDevice.authorizationStatus(for: capability == .camera ? .video : .audio) {
        case .authorized: return browser.text("разрешено", "Разрешено")
        case .denied: return browser.text("запрещено", "Запрещено")
        case .restricted: return browser.text("ограничено системой", "Ограничено системой")
        default: return browser.text("ещё не запрашивалось", "Ещё не запрашивалось")
        }
    }
}
