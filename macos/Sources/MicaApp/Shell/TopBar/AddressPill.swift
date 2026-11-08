import AppKit
import SwiftUI
import WebKit
import MicaCore
import UniformTypeIdentifiers

struct AddressPill: View {
    @ObservedObject var tab: Tab
    @ObservedObject var browser: BrowserModel
    @ObservedObject var store: Store
    var height: CGFloat = Chrome.field
    @State private var hover = false
    @State private var siteInfo = false
    @Environment(\.look) private var look
    var body: some View {
        let bookmarked = tab.url.map { url in store.bookmarks.contains { $0.url == url } } ?? false
        let control = height - 6
        HStack(spacing: 4) {
            IconButton(symbol: browser.privateMode ? Glyph.incognito : tab.secure ? "lock.fill" : tab.url == nil ? "magnifyingglass" : "exclamationmark.shield", label: browser.text("сведения о сайте", "Сведения о сайте"), size: control) { siteInfo.toggle() }
                .disabled(tab.url == nil)
                .popover(isPresented: $siteInfo, arrowEdge: .bottom) { SiteInfo(tab: tab, browser: browser, store: store).frame(width: 320) }
            Button { browser.commandBar = true } label: {
                Text(display)
                    .font(.system(size: 12.5, weight: .regular))
                    .foregroundStyle(tab.url == nil ? Palette.text3 : Palette.ink)
                    .lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(browser.text("адресная строка: ", "Адресная строка: ") + (tab.url?.absoluteString ?? ""))
            if !browser.privateMode, let address = tab.url?.absoluteString, let id = ChromeStore.extensionID(from: address), !store.extensions.records.contains(where: { $0.source == "cws:" + id }) {
                IconButton(symbol: "puzzlepiece.extension", label: browser.text("установить расширение в mica", "Установить расширение в mica"), size: control) {
                    browser.panel = .extensions
                    Task { await store.extensions.installFromChromeStore(address) }
                }
                .transition(.opacity)
            }
            IconButton(symbol: bookmarked ? "bookmark.fill" : "bookmark", label: browser.text("добавить или удалить закладку", "Добавить или удалить закладку"), size: control) { store.bookmark(tab) }
                .opacity(tab.url != nil && (hover || bookmarked) ? 1 : 0)
                .disabled(tab.url == nil)
        }
        .padding(.horizontal, 3)
        .frame(height: height)
        .background(RoundedRectangle(cornerRadius: Radius.icon, style: .continuous).fill(hover ? Palette.fieldHover : Palette.field).shadow(color: Palette.fieldShadow, radius: 1, y: 0.5))
        .overlay(RoundedRectangle(cornerRadius: Radius.icon, style: .continuous).strokeBorder(Palette.fieldBorder, lineWidth: 1))
        .overlay(alignment: .bottom) {
            GeometryReader { geo in
                Capsule().fill((look.accent ?? Palette.ink).opacity(0.6)).frame(width: max(0, geo.size.width * tab.progress), height: 2)
            }
            .frame(height: 2).padding(.horizontal, Radius.icon).opacity(tab.loading ? 1 : 0)
            .animation(.easeOut(duration: 0.2), value: tab.progress)
            .animation(Motion.hover, value: tab.loading)
        }
        .onHover { hover = $0 }
        .animation(Motion.hover, value: hover)
    }
    private var display: String {
        guard let url = tab.url else { return browser.text("адрес или поиск", "Адрес или поиск") }
        if let host = url.host { return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host }
        return url.absoluteString
    }
}
