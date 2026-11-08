import AppKit
import SwiftUI
import WebKit
import MicaCore
import UniformTypeIdentifiers

struct ContentCard: View {
    @ObservedObject var browser: BrowserModel
    @ObservedObject var store: Store
    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let tab = browser.selected { PageSurface(tab: tab, browser: browser, store: store) }
            if browser.showFind, let tab = browser.selected {
                FindBar(tab: tab, browser: browser).padding(10).transition(Motion.slide(.top))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Palette.canvas).shadow(color: Palette.shadow, radius: 6, y: 2))
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1).allowsHitTesting(false))
    }
}

struct PageSurface: View {
    @ObservedObject var tab: Tab
    @ObservedObject var browser: BrowserModel
    @ObservedObject var store: Store
    var body: some View {
        ZStack {
            if let web = tab.webView { WebSurface(webView: web, covered: browser.modal || browser.commandBar || browser.customizingToolbar).id(tab.id) }
            else if tab.url == nil { StartScreen(browser: browser, store: store).transition(.opacity) }
            if let error = tab.error { ErrorPage(tab: tab, browser: browser, error: error).transition(.opacity) }
        }
        .animation(Motion.hover, value: tab.error)
    }
}
