import AppKit
import SwiftUI

/// The same optional action is available during onboarding and in settings.
struct DefaultBrowserSetting: View {
    @ObservedObject var store: Store
    @ObservedObject var browser: BrowserModel
    @State private var isDefault = false
    @State private var busy = false
    @State private var failed = false

    var body: some View {
        SettingsGroup(title: browser.text("браузер по умолчанию", "Браузер по умолчанию")) {
            SettingRow(title: isDefault ? browser.text("mica открывает веб-ссылки", "mica открывает веб-ссылки") : browser.text("открывать веб-ссылки в mica", "Открывать веб-ссылки в mica"), divider: false) {
                if !isDefault {
                    Button(browser.text("сделать основным", "Сделать основным")) { setDefault() }
                        .buttonStyle(MButtonStyle(kind: .secondary, compact: true)).disabled(busy)
                }
            }
        }
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
        if failed && !isDefault {
            Text(browser.text("не удалось изменить браузер по умолчанию. попробуйте ещё раз или откройте системные настройки", "Не удалось изменить браузер по умолчанию. Попробуйте ещё раз или откройте системные настройки"))
                .font(.system(size: 12.5)).foregroundStyle(Palette.danger).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func refresh() {
        isDefault = Self.handlesWebLinks()
        if isDefault { failed = false }
    }

    private static func handlesWebLinks() -> Bool {
        ["http", "https"].allSatisfy { scheme in
            guard let url = URL(string: "\(scheme)://example.com"), let app = NSWorkspace.shared.urlForApplication(toOpen: url) else { return false }
            return Bundle(url: app)?.bundleIdentifier == Bundle.main.bundleIdentifier
        }
    }

    /// macOS shows one confirmation that switches http, https and HTML together, so a second request
    /// for "https" right after "http" fails even though the switch happened. Only "http" is requested;
    /// "https" is requested separately only when LaunchServices still points it elsewhere.
    private func setDefault() {
        busy = true; failed = false
        Task { @MainActor in
            defer { busy = false }
            var lastError: Error?
            do {
                try await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: "http")
            } catch { lastError = error }
            // Keeping the current browser in the system prompt is the user's answer, not a failure.
            if let lastError, Self.isDecline(lastError) { refresh(); return }
            if await settle() { return }
            if lastError == nil {
                do {
                    try await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: "https")
                } catch { lastError = error }
                if await settle() { return }
            }
            if let lastError, Self.isDecline(lastError) { return }
            failed = true
        }
    }

    /// LaunchServices applies the new handler asynchronously, so the result is polled for about 3 seconds.
    private func settle() async -> Bool {
        for _ in 0..<10 {
            refresh()
            if isDefault { return true }
            try? await Task.sleep(for: .milliseconds(300))
        }
        refresh()
        return isDefault
    }

    private static func isDecline(_ error: Error) -> Bool {
        let error = error as NSError
        switch error.domain {
        case NSCocoaErrorDomain: return error.code == NSUserCancelledError
        case NSOSStatusErrorDomain: return error.code == Int(userCanceledErr)
        default: return false
        }
    }
}
