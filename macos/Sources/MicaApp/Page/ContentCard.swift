import AppKit
import SwiftUI
import WebKit
import MicaCore
import UniformTypeIdentifiers

struct ContentCard: View {
    @ObservedObject var browser: BrowserModel
    @ObservedObject var store: Store
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        // The start page is mica's own surface, so with glass on it lets the frosted shell through; a site keeps an opaque card.
        let startPage = browser.selected.map { $0.webView == nil && $0.url == nil && $0.error == nil } ?? true
        let see = startPage && Store.glass(browser.prefs, reduceTransparency: reduceTransparency, contrast: contrast)
        ZStack(alignment: .topTrailing) {
            if let tab = browser.selected { PageSurface(tab: tab, browser: browser, store: store) }
            if browser.showFind, let tab = browser.selected {
                FindBar(tab: tab, browser: browser).padding(10).transition(Motion.slide(.top))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // A translucent fill would show its own shadow through itself, so the see-through card keeps only its hairline.
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Palette.canvas.opacity(see ? Store.startTint(browser.prefs) : 1)).shadow(color: see ? .clear : Palette.shadow, radius: 6, y: 2))
        .animation(Motion.hover, value: see)
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
            if let box = tab.box { WebSurface(box: box, covered: browser.modal || browser.commandBar || browser.customizingToolbar).id(tab.id) }
            else if tab.url == nil { StartScreen(browser: browser, store: store).id(tab.id).transition(.opacity) }
            if let error = tab.error { ErrorPage(tab: tab, browser: browser, error: error).transition(.opacity) }
        }
        .animation(Motion.hover, value: tab.error)
    }
}
