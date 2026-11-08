import AppKit
import SwiftUI
import AVFoundation
import UserNotifications
import MicaCore

struct PermissionSettings: View {
    @ObservedObject var store: Store
    @State private var notificationStatus: UNAuthorizationStatus?
    var body: some View {
        VStack(alignment: .leading, spacing: Space.section) {
            SettingsGroup(title: "macOS", footnote: store.text("системный доступ меняется в настройках конфиденциальности macOS", "Системный доступ меняется в настройках конфиденциальности macOS")) {
                ForEach(SiteCapability.allCases, id: \.self) { capability in
                    SettingRow(title: store.capabilityName(capability), divider: true) { Text(systemStatus(capability)).font(.system(size: 12)).foregroundStyle(Palette.text2) }
                }
                SettingRow(title: store.text("системные настройки", "Системные настройки"), divider: false) {
                    Button(store.text("открыть", "Открыть")) { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")!) }.buttonStyle(MButtonStyle(kind: .secondary, compact: true))
                }
            }
            SettingsGroup(title: store.text("уведомления сайтов", "Уведомления сайтов"), footnote: store.text("уведомления приходят от открытых вкладок. push-уведомления закрытых сайтов не поддерживаются. в окнах инкогнито уведомления запрещены.", "Уведомления приходят от открытых вкладок. Push-уведомления закрытых сайтов не поддерживаются. В окнах инкогнито уведомления запрещены.")) {
                Toggle(store.text("сайты могут спрашивать разрешение", "Сайты могут спрашивать разрешение"), isOn: $store.preferences.notificationRequests)
                    .toggleStyle(MToggleStyle()).modifier(RowInset(divider: false))
            }
            SettingsGroup(title: store.text("решения для сайтов", "Решения для сайтов"), footnote: store.text("решения окон инкогнито существуют только внутри окна. геолокация недоступна для управления через публичный API этой версии.", "Решения окон инкогнито существуют только внутри окна. Геолокация недоступна для управления через публичный API этой версии.")) {
                if store.permissions.isEmpty {
                    Text(store.text("сайты пока ничего не запрашивали", "Сайты пока ничего не запрашивали")).font(.system(size: 13)).foregroundStyle(Palette.text3).frame(maxWidth: .infinity, alignment: .leading).padding(14)
                }
                ForEach(Array(store.permissions.enumerated()), id: \.element.id) { index, record in
                    SettingRow(title: record.origin, detail: store.capabilityName(record.capability), divider: index < store.permissions.count - 1) {
                        Segmented(selection: Binding(get: { store.permissions.first { $0.id == record.id }?.decision ?? .ask }, set: { store.setPermission(origin: record.origin, capability: record.capability, decision: $0) }), options: [(.ask, store.text("спрашивать", "Спрашивать")), (.allow, store.text("разрешить", "Разрешить")), (.deny, store.text("запретить", "Запретить"))], compact: true, width: 270, label: record.origin)
                    }
                }
            }
        }
        .task { notificationStatus = await store.notifier.status() }
    }
    private func systemStatus(_ capability: SiteCapability) -> String {
        if capability == .notifications {
            switch notificationStatus {
            case .authorized?, .provisional?, .ephemeral?: return store.text("разрешено", "Разрешено")
            case .denied?: return store.text("запрещено", "Запрещено")
            case .notDetermined?: return store.text("ещё не запрашивалось", "Ещё не запрашивалось")
            default: return store.text("проверяем…", "Проверяем…")
            }
        }
        switch AVCaptureDevice.authorizationStatus(for: capability == .camera ? .video : .audio) {
        case .authorized: return store.text("разрешено", "Разрешено")
        case .denied: return store.text("запрещено", "Запрещено")
        case .restricted: return store.text("ограничено системой", "Ограничено системой")
        default: return store.text("ещё не запрашивалось", "Ещё не запрашивалось")
        }
    }
}
