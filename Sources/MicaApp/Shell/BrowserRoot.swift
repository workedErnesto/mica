import AppKit
import SwiftUI
import WebKit
import MicaCore
import UniformTypeIdentifiers

enum Panel: String, Identifiable { case bookmarks, history, downloads, extensions; var id: String { rawValue } }

struct BrowserRoot: View {
    @ObservedObject var browser: BrowserModel
    @ObservedObject var store: Store
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var dragWidth: Double?
    var body: some View {
        GeometryReader { geo in
            let layout: TabLayout = geo.size.width < 760 ? .top : store.preferences.layout
            let edge: TabLayout? = layout == .top ? nil : layout
            let collapsed = store.preferences.sidebarCollapsed && edge != nil
            let width = collapsed ? Chrome.rail : CGFloat(dragWidth ?? store.preferences.sidebarWidth)
            VStack(spacing: 0) {
                TopBar(browser: browser, store: store, layout: layout, windowWidth: geo.size.width, leadingInset: browser.fullScreen ? 0 : Chrome.lightsInset)
                if layout == .top { TabStrip(browser: browser).padding(.horizontal, Radius.gutter).padding(.bottom, Space.small) }
                HStack(spacing: 0) {
                    if edge == .left {
                        Sidebar(browser: browser, store: store, compact: collapsed, edge: .left)
                            .frame(width: width)
                            .overlay(alignment: .trailing) { if !collapsed { resizeHandle(sign: 1) } }
                            .transition(Motion.slide(.leading))
                    }
                    workspace(geo)
                        .overlay(alignment: .top) {
                            if browser.customizingToolbar {
                                ZStack(alignment: .top) {
                                    // A web page dims itself (WebSurface); the start page and panels are SwiftUI and need this layer.
                                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                                        .fill(Color.black.opacity(browser.selected?.webView == nil ? 0.18 : 0))
                                        .contentShape(Rectangle())
                                        .onTapGesture {}
                                    CustomizeToolbarPanel(store: store, browser: browser, layout: layout, maxHeight: max(200, geo.size.height - Chrome.bar - 2 * Space.normal - Radius.gutter))
                                        .padding(.horizontal, Space.normal).padding(.top, Space.normal)
                                }
                                .transition(.opacity)
                            }
                        }
                        .padding(.bottom, Radius.gutter)
                        .padding(.leading, edge == .left ? 0 : Radius.gutter)
                        .padding(.trailing, edge == .right ? 0 : Radius.gutter)
                    if edge == .right {
                        Sidebar(browser: browser, store: store, compact: collapsed, edge: .right)
                            .frame(width: width)
                            .overlay(alignment: .leading) { if !collapsed { resizeHandle(sign: -1) } }
                            .transition(Motion.slide(.trailing))
                    }
                }
            }
            .overlay { if browser.commandBar { CommandBar(browser: browser, store: store).transition(.opacity) } }
            .onChange(of: browser.modal) { _, shown in if shown { browser.customizingToolbar = false; browser.commandBar = false } }
            // The top bar lies in the title bar band, where AppKit would move the window instead of starting a tile drag.
            .onChange(of: browser.customizingToolbar) { _, editing in browser.controller?.window?.isMovable = !editing }
            .overlay { if browser.showSettings { SettingsOverlay(store: store, browser: browser).transition(.opacity) } }
            .overlay { if browser.showOnboarding { ModalCard(width: 860, height: 660, dismissible: false) { Onboarding(store: store, browser: browser) }.transition(.opacity) } }
            .overlay { if browser.showClearData { ModalCard(width: 480, onDismiss: { browser.showClearData = false }) { ClearDataPanel(store: store, browser: browser) }.transition(.opacity) } }
            .background { shellBackground.ignoresSafeArea() }
            .ignoresSafeArea()
            .animation(Motion.panel, value: layout)
            .animation(Motion.panel, value: collapsed)
            .animation(Motion.panel, value: browser.panel)
            .animation(Motion.panel, value: store.preferences.toolbar)
            .animation(Motion.quick, value: browser.commandBar)
            .animation(Motion.quick, value: browser.showFind)
            .onChange(of: browser.focusAddress) { _, _ in if browser.selected?.url != nil { browser.commandBar = true } }
            .animation(Motion.quick, value: browser.showSettings)
            .animation(Motion.quick, value: browser.showOnboarding)
            .animation(Motion.quick, value: browser.showClearData)
            .animation(Motion.panel, value: browser.customizingToolbar)
            .alert("mica", isPresented: Binding(get: { browser.message != nil || store.issue != nil }, set: { if !$0 { browser.message = nil; store.issue = nil } })) { Button("OK") { browser.message = nil; store.issue = nil } } message: { Text(browser.message ?? store.issue ?? "") }
        }
        .environment(\.look, store.look)
        .environment(\.locale, store.locale)
        .frame(minWidth: 600, minHeight: 420)
    }

    @ViewBuilder private var shellBackground: some View {
        ShellBackground(store: store, glass: store.preferences.frosted && !reduceTransparency && contrast != .increased)
    }

    private func workspace(_ geo: GeometryProxy) -> some View {
        HStack(spacing: Radius.gutter) {
            ContentCard(browser: browser, store: store)
            if let panel = browser.panel {
                SidePanel(panel: panel, browser: browser, store: store)
                    .frame(width: min(340, geo.size.width * 0.4))
                    .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Palette.surface))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
                    .shadow(color: Palette.shadow, radius: 6, y: 2)
                    .transition(Motion.slide(.trailing))
            }
        }
    }

    private func resizeHandle(sign: CGFloat) -> some View {
        Color.clear.frame(width: 6).contentShape(Rectangle())
            .onHover { inside in if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global).onChanged { value in
                let base = store.preferences.sidebarWidth
                dragWidth = min(Preferences.sidebarRange.upperBound, max(Preferences.sidebarRange.lowerBound, base + Double(value.translation.width * sign)))
            }.onEnded { _ in if let dragWidth { store.preferences.sidebarWidth = dragWidth }; dragWidth = nil })
            .accessibilityHidden(true)
    }
}
