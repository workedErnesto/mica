import AppKit
import SwiftUI
import WebKit
import MicaCore
import UniformTypeIdentifiers

struct PrivateBadge: View {
    @ObservedObject var browser: BrowserModel
    var body: some View {
        Glyph(name: Glyph.incognito, size: 13).foregroundStyle(Palette.text2).frame(width: 28, height: 28)
            .help(browser.text("окно инкогнито", "Окно инкогнито")).accessibilityLabel(browser.text("окно инкогнито", "Окно инкогнито"))
    }
}

struct NavigationButton: View {
    @ObservedObject var tab: Tab
    @ObservedObject var browser: BrowserModel
    let forward: Bool
    var body: some View {
        IconButton(symbol: forward ? "chevron.right" : "chevron.left", label: forward ? browser.text("вперёд", "Вперёд") : browser.text("назад", "Назад")) { if forward { tab.webView?.goForward() } else { tab.webView?.goBack() } }
            .disabled(forward ? !tab.canForward : !tab.canBack)
    }
}

struct ReloadButton: View {
    @ObservedObject var tab: Tab
    @ObservedObject var browser: BrowserModel
    var size: CGFloat
    var body: some View {
        IconButton(symbol: tab.loading ? "xmark" : "arrow.clockwise", label: tab.loading ? browser.text("остановить", "Остановить") : browser.text("перезагрузить", "Перезагрузить"), size: size) { if tab.loading { tab.webView?.stopLoading() } else { tab.reload() } }
            .disabled(tab.url == nil)
            .contentTransition(.symbolEffect(.replace))
    }
}

extension ToolbarControl {
    var symbol: String {
        switch self {
        case .sidebar: return "sidebar.left"
        case .back: return "chevron.left"
        case .forward: return "chevron.right"
        case .reload: return "arrow.clockwise"
        case .newTab: return "plus"
        case .bookmarks: return "bookmark"
        case .history: return "clock"
        case .downloads: return "arrow.down.circle"
        case .extensions: return "puzzlepiece.extension"
        case .incognito: return Glyph.incognito
        case .settings: return "gearshape"
        case .profile: return "person.crop.circle"
        case .save: return "square.and.arrow.down"
        }
    }
    @MainActor func title(_ browser: BrowserModel) -> String {
        switch self {
        case .sidebar: return browser.text("боковая панель", "Боковая панель")
        case .back: return browser.text("назад", "Назад")
        case .forward: return browser.text("вперёд", "Вперёд")
        case .reload: return browser.text("перезагрузить", "Перезагрузить")
        case .newTab: return browser.text("новая вкладка", "Новая вкладка")
        case .bookmarks: return browser.text("закладки", "Закладки")
        case .history: return browser.text("история", "История")
        case .downloads: return browser.text("загрузки", "Загрузки")
        case .extensions: return browser.text("расширения", "Расширения")
        case .incognito: return browser.text("окно инкогнито", "Окно инкогнито")
        case .settings: return browser.text("настройки", "Настройки")
        case .profile: return browser.text("профиль", "Профиль")
        case .save: return browser.text("сохранить страницу", "Сохранить страницу")
        }
    }
    var panel: Panel? {
        switch self { case .bookmarks: return .bookmarks; case .history: return .history; case .downloads: return .downloads; case .extensions: return .extensions; default: return nil }
    }
}

/// Saves the page of the selected tab: a menu of formats under the button, then the system save panel.
/// While a page of this tab is being written the button shows its progress in place of the glyph.
struct SavePageButton: View {
    @ObservedObject var tab: Tab
    @ObservedObject var browser: BrowserModel
    @ObservedObject var downloads: DownloadManager
    var body: some View {
        let current = downloads.items.first { $0.saving && $0.state == .running && $0.tab === tab }
        ZStack {
            if let current {
                SavingRing(item: current).help(browser.text("сохраняется", "Сохраняется"))
                    .accessibilityLabel(browser.text("сохраняется", "Сохраняется"))
                    .transition(.opacity)
            } else {
                MenuButton(symbol: ToolbarControl.save.symbol, label: ToolbarControl.save.title(browser) + " ⌘S", size: 28, trigger: browser.saveMenu) {
                    PageSaver.entries(tab, browser: browser)
                }
                .disabled(!PageSaver.canSave(tab) || tab.loading && tab.progress < 0.1)
                .transition(.opacity)
            }
        }
        .frame(width: 28, height: 28)
        .animation(Motion.reduced ? nil : .easeOut(duration: 0.15), value: current?.id)
    }
}

private struct SavingRing: View {
    @ObservedObject var item: DownloadItem
    var body: some View { ProgressRing(progress: item.fraction, size: 16).frame(width: 28, height: 28) }
}

/// One configurable control. The same item works in the top bar, at the bottom of the sidebar and in the rail.
struct ToolbarButton: View {
    let item: ToolbarControl
    @ObservedObject var browser: BrowserModel
    @ObservedObject var store: Store
    var edge: TabLayout? = .left
    var inSidebar = false
    var body: some View {
        switch item {
        case .sidebar:
            let collapsed = browser.prefs.sidebarCollapsed
            IconButton(symbol: edge == .right ? "sidebar.right" : "sidebar.left", label: collapsed ? browser.text("развернуть боковую панель", "Развернуть боковую панель") : browser.text("свернуть боковую панель", "Свернуть боковую панель")) {
                withMotion(Motion.panel) { browser.prefs.sidebarCollapsed.toggle() }
            }
        case .back, .forward:
            if let tab = browser.selected { NavigationButton(tab: tab, browser: browser, forward: item == .forward) }
            else { IconButton(symbol: item.symbol, label: item.title(browser)) {}.disabled(true) }
        case .reload:
            if let tab = browser.selected { ReloadButton(tab: tab, browser: browser, size: 28) }
            else { IconButton(symbol: item.symbol, label: item.title(browser)) {}.disabled(true) }
        case .newTab:
            IconButton(symbol: "plus", label: item.title(browser) + " ⌘T") { _ = browser.add(); browser.focusAddress += 1 }
        case .extensions:
            // In the top bar the extension buttons sit next to the puzzle; in the sidebar they get their own row above the footer.
            if inSidebar { IconButton(symbol: item.symbol, label: item.title(browser), selected: browser.panel == .extensions) { browser.panel = browser.panel == .extensions ? nil : .extensions } }
            else { ExtensionActions(manager: store.extensions, browser: browser, store: store) }
        case .incognito:
            IconButton(symbol: item.symbol, label: browser.text("новое окно инкогнито", "Новое окно инкогнито") + " ⌘⇧N") { store.newWindow(privateMode: true) }
        case .bookmarks, .history, .downloads:
            let panel = item.panel!
            IconButton(symbol: item.symbol, label: item.title(browser), selected: browser.panel == panel) { browser.panel = browser.panel == panel ? nil : panel }
        case .settings:
            IconButton(symbol: item.symbol, label: item.title(browser)) { browser.showSettings = true }
        case .profile:
            ProfileButton(browser: browser, store: store)
        case .save:
            if let tab = browser.selected { SavePageButton(tab: tab, browser: browser, downloads: browser.downloads) }
            else { IconButton(symbol: item.symbol, label: item.title(browser)) {}.disabled(true) }
        }
    }
}
