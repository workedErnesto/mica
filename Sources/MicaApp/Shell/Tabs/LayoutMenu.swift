import AppKit
import SwiftUI
import WebKit
import MicaCore
import UniformTypeIdentifiers

/// Where the tabs live, from any context menu of the shell.
@MainActor
enum LayoutMenu {
    static func entries(store: Store) -> [MenuEntry] {
        let current = store.preferences.layout
        func choose(_ layout: TabLayout) { withMotion(Motion.panel) { store.preferences.layout = layout } }
        return [
            .item(store.text("боковая панель слева", "Боковая панель слева"), symbol: "sidebar.left", checked: current == .left) { choose(.left) },
            .item(store.text("вкладки сверху", "Вкладки сверху"), symbol: "rectangle.topthird.inset.filled", checked: current == .top) { choose(.top) },
            .item(store.text("боковая панель справа", "Боковая панель справа"), symbol: "sidebar.right", checked: current == .right) { choose(.right) },
        ]
    }
}
