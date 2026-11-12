import AppKit
import SwiftUI
import MicaCore

/// Chrome Web Store: install the extension open in the current tab, or paste its address or ID.
struct ChromeStoreSection: View {
    @ObservedObject var manager: ExtensionManager
    @ObservedObject var browser: BrowserModel
    @State private var input = ""
    var body: some View {
        let current = browser.selected?.url.flatMap { ChromeStore.extensionID(from: $0.absoluteString) }
        let busy = manager.installingChrome != nil || manager.busy
        VStack(alignment: .leading, spacing: Space.small) {
            Text("Chrome Web Store").font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.text2)
            if let current, let tab = browser.selected {
                let installed = manager.records.contains { $0.source == "cws:" + current }
                HStack(spacing: 10) {
                    Monogram(host: storeTitle(tab.title), size: Chrome.rowIcon)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(storeTitle(tab.title)).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Palette.ink).lineLimit(1)
                        Text(browser.text("открыто в текущей вкладке", "Открыто в текущей вкладке")).font(.system(size: 11)).foregroundStyle(Palette.text3)
                    }
                    Spacer(minLength: Space.small)
                    if manager.installingChrome == current {
                        ProgressView().controlSize(.small)
                    } else {
                        Button(installed ? browser.text("обновить", "Обновить") : browser.text("установить", "Установить")) { Task { await manager.installFromChromeStore(current) } }
                            .buttonStyle(MButtonStyle(kind: installed ? .secondary : .primary, compact: true)).disabled(busy || browser.privateMode)
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: Radius.row + 2, style: .continuous).fill(Palette.surface))
                .overlay(RoundedRectangle(cornerRadius: Radius.row + 2, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
                .transition(.opacity)
            }
            MTextField(placeholder: browser.text("ссылка на расширение или его ID", "Ссылка на расширение или его ID"), text: $input, symbol: "link") {
                Task { await manager.installFromChromeStore(input); if manager.chromeStatus.isEmpty { input = "" } }
            }
            .disabled(busy || browser.privateMode)
            Text(manager.chromeStatus.isEmpty ? browser.text("Return устанавливает. mica скачивает тот же пакет, что получает Chrome, проверяет подпись разработчика и показывает права до запуска. API Chrome работают в объёме WebKit.", "Return устанавливает. mica скачивает тот же пакет, что получает Chrome, проверяет подпись разработчика и показывает права до запуска. API Chrome работают в объёме WebKit.") : manager.chromeStatus)
                .font(.system(size: 11.5)).foregroundStyle(manager.chromeStatus.isEmpty || manager.installingChrome != nil ? Palette.text3 : Palette.danger)
                .fixedSize(horizontal: false, vertical: true)
            LinkRow(title: browser.text("открыть магазин", "Открыть магазин"), symbol: "arrow.up.right") { browser.open(URL(string: "https://chromewebstore.google.com/category/extensions")!) }
        }
        .animation(Motion.hover, value: manager.chromeStatus)
        .animation(Motion.quick, value: current)
    }
    /// Store pages are titled "Name - Chrome Web Store".
    private func storeTitle(_ title: String) -> String {
        let name = title.replacingOccurrences(of: " - Chrome Web Store", with: "").trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Chrome Web Store" : name
    }
}
