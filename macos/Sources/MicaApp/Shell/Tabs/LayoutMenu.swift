import AppKit
import SwiftUI
import WebKit
import MicaCore
import UniformTypeIdentifiers

/// Where the tabs live, from any context menu of the shell.
@MainActor
enum LayoutMenu {
    static func entries(store: Store, browser: BrowserModel) -> [MenuEntry] {
        let current = browser.prefs.layout
        func choose(_ layout: TabLayout) { withMotion(Motion.panel) { browser.prefs.layout = layout } }
        return [
            .item(browser.text("боковая панель слева", "Боковая панель слева"), symbol: "sidebar.left", checked: current == .left) { choose(.left) },
            .item(browser.text("вкладки под адресом", "Вкладки под адресом"), symbol: "rectangle.topthird.inset.filled", checked: current == .top) { choose(.top) },
            .item(browser.text("вкладки над адресом", "Вкладки над адресом"), symbol: "macwindow", checked: current == .tabsAbove) { choose(.tabsAbove) },
            .item(browser.text("боковая панель справа", "Боковая панель справа"), symbol: "sidebar.right", checked: current == .right) { choose(.right) },
        ]
    }
}
