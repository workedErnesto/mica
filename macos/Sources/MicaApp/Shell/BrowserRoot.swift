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
            let layout = browser.prefs.layout.fitting(width: geo.size.width)
            let edge = layout.sidebarEdge
            let lights = browser.fullScreen ? 0 : Chrome.lightsInset
            let collapsed = browser.prefs.sidebarCollapsed && edge != nil
            let width = collapsed ? Chrome.rail : CGFloat(dragWidth ?? browser.prefs.sidebarWidth)
            VStack(spacing: 0) {
                if layout == .tabsAbove {
                    // Tabs in the title bar band next to the window buttons, the toolbar row with the address under them.
                    TabStrip(browser: browser, titleBand: true)
                        .padding(.leading, lights == 0 ? Radius.gutter : lights).padding(.trailing, Radius.gutter)
                        .frame(height: Chrome.bar)
                        .background { WindowDragArea(titleBand: true) }
                        .micaContextMenu { TabStrip.menu(browser: browser, store: store) }
                        .transition(.opacity)
                    TopBar(browser: browser, store: store, layout: layout, windowWidth: geo.size.width, leadingInset: Space.small)
                        .padding(.top, -Space.micro)
                } else {
                    TopBar(browser: browser, store: store, layout: layout, windowWidth: geo.size.width, leadingInset: lights)
                    if layout == .top {
                        // The whole band, gutters and the free space after the tabs included, opens the strip menu;
                        // a tab's own smaller area keeps its tab menu.
                        TabStrip(browser: browser).padding(.horizontal, Radius.gutter).padding(.bottom, Space.small)
                            .micaContextMenu { TabStrip.menu(browser: browser, store: store) }
                            .transition(.opacity)
                    }
                }
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
                                    CustomizeToolbarPanel(store: store, browser: browser, layout: layout, maxHeight: max(200, geo.size.height - (layout == .tabsAbove ? 2 : 1) * Chrome.bar - 2 * Space.normal - Radius.gutter))
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
            // The title bar band moves the window on a mouse down, so a SwiftUI tap or drag there never starts:
            // toolbar tiles while customizing, tabs when they sit in the band. Then only WindowDragArea moves the window.
            .onAppear { movable(layout) }
            .onChange(of: browser.customizingToolbar) { _, _ in movable(layout) }
            .onChange(of: layout) { _, value in movable(value) }
            .overlay { if browser.showSettings { SettingsOverlay(store: store, browser: browser).transition(.opacity) } }
            .overlay { if browser.showOnboarding { ModalCard(width: 860, height: 660, dismissible: false) { Onboarding(store: store, browser: browser) }.transition(.opacity) } }
            .overlay { if browser.showClearData { ModalCard(width: 480, onDismiss: { browser.showClearData = false }) { ClearDataPanel(store: store, browser: browser) }.transition(.opacity) } }
            .overlay {
                if let id = browser.profilePrompt {
                    ModalCard(width: 300, onDismiss: { browser.profilePrompt = nil }) { ProfileOpenPrompt(profile: store.profile(id), store: store, browser: browser) }.transition(.opacity)
                }
            }
            .overlay { QuitHoldOverlay(browser: browser, store: store) }
            .background { shellBackground.ignoresSafeArea() }
            .ignoresSafeArea()
            .animation(Motion.panel, value: layout)
            .animation(Motion.panel, value: collapsed)
            .animation(Motion.panel, value: browser.panel)
            .animation(Motion.panel, value: browser.prefs.toolbar)
            .animation(Motion.quick, value: browser.commandBar)
            .animation(Motion.quick, value: browser.showFind)
            .onChange(of: browser.focusAddress) { _, _ in if browser.selected?.url != nil { browser.commandBar = true } }
            .animation(Motion.quick, value: browser.showSettings)
            .animation(Motion.quick, value: browser.showOnboarding)
            .animation(Motion.quick, value: browser.showClearData)
            .animation(Motion.quick, value: browser.profilePrompt)
            .animation(Motion.panel, value: browser.customizingToolbar)
            .alert("mica", isPresented: Binding(get: { browser.message != nil || store.issue != nil }, set: { if !$0 { browser.message = nil; store.issue = nil } })) { Button("OK") { browser.message = nil; store.issue = nil } } message: { Text(browser.message ?? store.issue ?? "") }
        }
        .environment(\.look, browser.look)
        .environment(\.locale, browser.locale)
        .frame(minWidth: 600, minHeight: 420)
    }

    private func movable(_ layout: TabLayout) {
        browser.controller?.window?.isMovable = !browser.customizingToolbar && layout != .tabsAbove
    }

    @ViewBuilder private var shellBackground: some View {
        ShellBackground(store: store, browser: browser, glass: Store.glass(browser.prefs, reduceTransparency: reduceTransparency, contrast: contrast))
    }

    private func workspace(_ geo: GeometryProxy) -> some View {
        // On the first appearance the start page card rises a little out of the shell. A site's card is not moved or
        // scaled, its pixels stay as they are; it appears with the window fade.
        let startPage = browser.selected.map { $0.webView == nil && $0.url == nil } ?? true
        return HStack(spacing: Radius.gutter) {
            ContentCard(browser: browser, store: store)
                .entrance(browser.entered || !startPage, delay: Entrance.step(1), scale: MotionTokens.entrance.cardScale)
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
                let base = browser.prefs.sidebarWidth
                dragWidth = min(Preferences.sidebarRange.upperBound, max(Preferences.sidebarRange.lowerBound, base + Double(value.translation.width * sign)))
            }.onEnded { _ in if let dragWidth { browser.prefs.sidebarWidth = dragWidth }; dragWidth = nil })
            .accessibilityHidden(true)
    }
}
