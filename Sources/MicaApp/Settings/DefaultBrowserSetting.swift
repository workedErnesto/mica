import AppKit
import SwiftUI

/// The same optional action is available during onboarding and in settings.
struct DefaultBrowserSetting: View {
    @ObservedObject var store: Store
    @State private var isDefault = false
    @State private var busy = false
    @State private var failed = false

    var body: some View {
        SettingsGroup(title: store.text("браузер по умолчанию", "Браузер по умолчанию")) {
            SettingRow(title: isDefault ? store.text("mica открывает веб-ссылки", "mica открывает веб-ссылки") : store.text("открывать веб-ссылки в mica", "Открывать веб-ссылки в mica"), divider: false) {
                if !isDefault {
                    Button(store.text("сделать основным", "Сделать основным")) { setDefault() }
                        .buttonStyle(MButtonStyle(kind: .secondary, compact: true)).disabled(busy)
                }
            }
        }
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
        if failed {
            Text(store.text("не удалось изменить браузер по умолчанию. попробуйте ещё раз или откройте системные настройки", "Не удалось изменить браузер по умолчанию. Попробуйте ещё раз или откройте системные настройки"))
                .font(.system(size: 12.5)).foregroundStyle(Palette.danger).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func refresh() {
        isDefault = ["http", "https"].allSatisfy { scheme in
            guard let url = URL(string: "\(scheme)://example.com"), let app = NSWorkspace.shared.urlForApplication(toOpen: url) else { return false }
            return Bundle(url: app)?.bundleIdentifier == Bundle.main.bundleIdentifier
        }
    }

    private func setDefault() {
        busy = true; failed = false
        Task {
            do {
                for scheme in ["http", "https"] {
                    try await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: scheme)
                }
            } catch { failed = true }
            refresh(); busy = false
        }
    }
}
