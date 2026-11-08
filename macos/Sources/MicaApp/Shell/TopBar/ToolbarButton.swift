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
        }
    }
    @MainActor func title(_ store: Store) -> String {
        switch self {
        case .sidebar: return store.text("боковая панель", "Боковая панель")
        case .back: return store.text("назад", "Назад")
        case .forward: return store.text("вперёд", "Вперёд")
        case .reload: return store.text("перезагрузить", "Перезагрузить")
        case .newTab: return store.text("новая вкладка", "Новая вкладка")
        case .bookmarks: return store.text("закладки", "Закладки")
        case .history: return store.text("история", "История")
        case .downloads: return store.text("загрузки", "Загрузки")
        case .extensions: return store.text("расширения", "Расширения")
        case .incognito: return store.text("окно инкогнито", "Окно инкогнито")
        case .settings: return store.text("настройки", "Настройки")
        }
    }
    var panel: Panel? {
        switch self { case .bookmarks: return .bookmarks; case .history: return .history; case .downloads: return .downloads; case .extensions: return .extensions; default: return nil }
    }
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
            let collapsed = store.preferences.sidebarCollapsed
            IconButton(symbol: edge == .right ? "sidebar.right" : "sidebar.left", label: collapsed ? browser.text("развернуть боковую панель", "Развернуть боковую панель") : browser.text("свернуть боковую панель", "Свернуть боковую панель")) {
                withMotion(Motion.panel) { store.preferences.sidebarCollapsed.toggle() }
            }
        case .back, .forward:
            if let tab = browser.selected { NavigationButton(tab: tab, browser: browser, forward: item == .forward) }
            else { IconButton(symbol: item.symbol, label: item.title(store)) {}.disabled(true) }
        case .reload:
            if let tab = browser.selected { ReloadButton(tab: tab, browser: browser, size: 28) }
            else { IconButton(symbol: item.symbol, label: item.title(store)) {}.disabled(true) }
        case .newTab:
            IconButton(symbol: "plus", label: item.title(store) + " ⌘T") { _ = browser.add(); browser.focusAddress += 1 }
        case .extensions:
            // In the top bar the extension buttons sit next to the puzzle; in the sidebar they get their own row above the footer.
            if inSidebar { IconButton(symbol: item.symbol, label: item.title(store), selected: browser.panel == .extensions) { browser.panel = browser.panel == .extensions ? nil : .extensions } }
            else { ExtensionActions(manager: store.extensions, browser: browser, store: store) }
        case .incognito:
            IconButton(symbol: item.symbol, label: browser.text("новое окно инкогнито", "Новое окно инкогнито") + " ⌘⇧N") { store.newWindow(privateMode: true) }
        case .bookmarks, .history, .downloads:
            let panel = item.panel!
            IconButton(symbol: item.symbol, label: item.title(store), selected: browser.panel == panel) { browser.panel = browser.panel == panel ? nil : panel }
        case .settings:
            IconButton(symbol: item.symbol, label: item.title(store)) { browser.showSettings = true }
        }
    }
}
