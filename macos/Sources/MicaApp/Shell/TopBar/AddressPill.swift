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
    @State private var pinning = false
    @Environment(\.look) private var look
    var body: some View {
        let bookmarked = tab.url.map { url in store.bookmarks.contains { $0.url == url } } ?? false
        // A bookmark to a local file would only open while mica keeps the file's permission, so files get none.
        let local = tab.url?.isFileURL == true
        // Only web pages go to the start page; its tiles open in a regular tab.
        let pinnable = tab.url.map { ["http", "https"].contains($0.scheme?.lowercased() ?? "") } ?? false
        let pinned = tab.url.map { url in browser.prefs.start.shortcuts.contains { $0.url == url } } ?? false
        let control = height - 6
        HStack(spacing: 4) {
            IconButton(symbol: browser.privateMode ? Glyph.incognito : tab.secure ? "lock.fill" : tab.url == nil ? "magnifyingglass" : local ? "doc" : "exclamationmark.shield", label: browser.text("сведения о сайте", "Сведения о сайте"), size: control) { siteInfo.toggle() }
                .disabled(tab.url == nil)
                .popover(isPresented: $siteInfo, arrowEdge: .bottom) { SiteInfo(tab: tab, browser: browser, store: store).frame(width: 320) }
            Button { browser.commandBar = true } label: {
                Group {
                    if let url = tab.url { AddressText(address: url.absoluteString, style: browser.prefs.address) } else { Text(browser.text("адрес или поиск", "Адрес или поиск")).foregroundStyle(Palette.text3) }
                }
                    .font(.system(size: 12.5, weight: .regular))
                    .lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(browser.text("адресная строка: ", "Адресная строка: ") + (tab.url.map { $0.isFileURL ? $0.path : $0.absoluteString } ?? ""))
            if !browser.privateMode, let address = tab.url?.absoluteString, let id = ChromeStore.extensionID(from: address), !store.extensions.records.contains(where: { $0.source == "cws:" + id }) {
                IconButton(symbol: "puzzlepiece.extension", label: browser.text("установить расширение в mica", "Установить расширение в mica"), size: control) {
                    browser.panel = .extensions
                    Task { await store.extensions.installFromChromeStore(address) }
                }
                .transition(.opacity)
            }
            IconButton(symbol: pinned ? "pin.fill" : "pin", label: pinned ? browser.text("удалить с начальной страницы", "Удалить с начальной страницы") : browser.text("закрепить в своих сайтах", "Закрепить в своих сайтах"), size: control) {
                // A pinned page comes off at once; a new one opens the form to give it a name first.
                if pinned, let url = tab.url { withMotion(Motion.quick) { browser.removeStartShortcut(url) } } else { pinning = true }
            }
            .stickyPopover(isPresented: $pinning) { ShortcutEditor(store: store, browser: browser, editing: nil, page: tab.url) { pinning = false } }
            .opacity(pinnable && (hover || pinning) ? 1 : 0)
            .disabled(!pinnable)
            IconButton(symbol: bookmarked ? "bookmark.fill" : "bookmark", label: browser.text("добавить или удалить закладку", "Добавить или удалить закладку"), size: control) { store.bookmark(tab) }
                .opacity(tab.url != nil && !local && (hover || bookmarked) ? 1 : 0)
                .disabled(tab.url == nil || local)
        }
        .padding(.horizontal, 3)
        .frame(height: height)
        .background(RoundedRectangle(cornerRadius: Radius.icon, style: .continuous).fill(hover ? Palette.fieldHover : Palette.field).shadow(color: Palette.fieldShadow, radius: 1, y: 0.5))
        .overlay {
            // Load progress: flush with the bottom edge from the very left, clipped by the field's own shape so it
            // follows the rounded corners instead of stopping short of them. Drawn under the border stroke.
            GeometryReader { geo in
                Rectangle().fill((look.accent ?? Palette.ink).opacity(0.6))
                    .frame(width: max(0, geo.size.width * min(1, tab.progress)), height: 3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.icon, style: .continuous))
            .opacity(tab.loading ? 1 : 0)
            .animation(.easeOut(duration: 0.2), value: tab.progress)
            .animation(Motion.hover, value: tab.loading)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .overlay(RoundedRectangle(cornerRadius: Radius.icon, style: .continuous).strokeBorder(Palette.fieldBorder, lineWidth: 1))
        .onHover { hover = $0 }
        .animation(Motion.hover, value: hover)
    }
}
