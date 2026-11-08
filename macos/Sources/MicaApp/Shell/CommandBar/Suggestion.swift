import AppKit
import SwiftUI
import WebKit
import MicaCore
import UniformTypeIdentifiers

struct Suggestion: Identifiable, Equatable {
    enum Kind { case open, search, tab, bookmark, history }
    let id: String
    let kind: Kind
    let title: String
    let detail: String
    var url: URL?
    var tabID: UUID?
    var symbol: String {
        switch kind { case .open: return "arrow.up.right"; case .search: return "magnifyingglass"; case .tab: return "square.on.square"; case .bookmark: return "bookmark"; case .history: return "clock" }
    }

    @MainActor static func make(_ input: String, browser: BrowserModel, store: Store) -> [Suggestion] {
        let query = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        var result: [Suggestion] = []
        let engine = store.preferences.search
        if case .web(let url) = AddressParser.resolve(query, engine: engine) {
            if engine.isSearch(url, for: query) {
                result.append(Suggestion(id: "search", kind: .search, title: query, detail: browser.text("поиск: ", "Поиск: ") + engine.title(store.preferences.language), url: url))
            } else {
                result.append(Suggestion(id: "open", kind: .open, title: url.absoluteString, detail: browser.text("открыть адрес", "Открыть адрес"), url: url))
                result.append(Suggestion(id: "search", kind: .search, title: query, detail: browser.text("поиск: ", "Поиск: ") + engine.title(store.preferences.language), url: engine.search(query)))
            }
        }
        func matches(_ title: String, _ url: URL) -> Bool { title.localizedCaseInsensitiveContains(query) || url.absoluteString.localizedCaseInsensitiveContains(query) }
        var seen = Set(result.compactMap(\.url?.absoluteString))
        for tab in browser.tabs where tab.id != browser.selectedID {
            guard let url = tab.url, matches(tab.title, url), seen.insert(url.absoluteString).inserted else { continue }
            result.append(Suggestion(id: "tab-" + tab.id.uuidString, kind: .tab, title: tab.title.isEmpty ? url.absoluteString : tab.title, detail: browser.text("перейти к вкладке", "Перейти к вкладке"), url: url, tabID: tab.id))
        }
        for visit in store.bookmarks where matches(visit.title, visit.url) && seen.insert(visit.url.absoluteString).inserted {
            result.append(Suggestion(id: "b-" + visit.id.uuidString, kind: .bookmark, title: visit.title.isEmpty ? visit.url.absoluteString : visit.title, detail: visit.url.host ?? visit.url.absoluteString, url: visit.url))
        }
        if !browser.privateMode {
            for visit in store.history where matches(visit.title, visit.url) && seen.insert(visit.url.absoluteString).inserted {
                result.append(Suggestion(id: "h-" + visit.id.uuidString, kind: .history, title: visit.title.isEmpty ? visit.url.absoluteString : visit.title, detail: visit.url.host ?? visit.url.absoluteString, url: visit.url))
                if result.count >= 8 { break }
            }
        }
        return Array(result.prefix(8))
    }

    @MainActor func activate(in browser: BrowserModel) {
        if let tabID, let tab = browser.tabs.first(where: { $0.id == tabID }) { browser.select(tab) }
        else if let url { browser.selected?.load(url) }
    }
}
