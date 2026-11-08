import AppKit
import SwiftUI
import WebKit
import MicaCore
import UniformTypeIdentifiers

struct FindBar: View {
    @ObservedObject var tab: Tab
    @ObservedObject var browser: BrowserModel
    @State private var query = ""
    @State private var found = true
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "text.magnifyingglass").font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.text3).padding(.leading, 8)
            TextField(browser.text("найти на странице", "Найти на странице"), text: $query).textFieldStyle(.plain).font(.system(size: 13)).frame(width: 180).focused($focused).onSubmit { find(false) }
            if !found { Text(browser.text("не найдено", "Не найдено")).font(.system(size: 11.5)).foregroundStyle(Palette.danger).transition(.opacity) }
            IconButton(symbol: "chevron.up", label: browser.text("предыдущее совпадение", "Предыдущее совпадение"), size: 24) { find(true) }
            IconButton(symbol: "chevron.down", label: browser.text("следующее совпадение", "Следующее совпадение"), size: 24) { find(false) }
            IconButton(symbol: "xmark", label: browser.text("закрыть поиск", "Закрыть поиск"), size: 24) { close() }
        }
        .padding(4)
        .modifier(RaisedSurface(radius: 12))
        .animation(Motion.hover, value: found)
        .onAppear { focused = true }
        .onExitCommand { close() }
    }
    private func close() { browser.showFind = false; tab.webView?.find("", configuration: WKFindConfiguration()) { _ in } }
    private func find(_ backwards: Bool) { let config = WKFindConfiguration(); config.backwards = backwards; config.wraps = true; tab.webView?.find(query, configuration: config) { found = $0.matchFound } }
}
