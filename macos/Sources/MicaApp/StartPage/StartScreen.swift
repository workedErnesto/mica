import AppKit
import SwiftUI
import WebKit
import MicaCore
import UniformTypeIdentifiers

struct StartScreen: View {
    @ObservedObject var browser: BrowserModel
    @ObservedObject var store: Store
    @State private var text = ""
    @State private var highlighted = 0
    /// Picks the greeting phrase; a new tab gets a new one, the open start page keeps its own.
    @State private var seed = Int.random(in: 0..<1000)
    @FocusState private var focused: Bool
    /// Entrance of the parts of the page (Entrance.swift): false until the window is ordered in, true from the start
    /// for a tab whose page already played it.
    @State private var shown: Bool

    init(browser: BrowserModel, store: Store) {
        _browser = ObservedObject(wrappedValue: browser)
        _store = ObservedObject(wrappedValue: store)
        _shown = State(initialValue: browser.selected?.introduced ?? true)
    }
    var body: some View {
        let editing = browser.customizingStart
        let items = editing ? [] : Suggestion.make(text, browser: browser, store: store)
        let options = browser.prefs.start
        let greeting = Greeting.text(browser.prefs, hour: Calendar.current.component(.hour, from: Date()), seed: seed)
        let sections = visibleSections(options, editing: editing)
        ZStack {
            // ContentCard draws the canvas under the start page, translucent when the shell is frosted.
            Color.clear
            ScrollView {
                VStack(spacing: 28) {
                    if options.wordmark || browser.privateMode || editing {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            if options.wordmark || editing {
                                VStack(spacing: Space.normal) {
                                    if editing {
                                        StartBlockHeader(title: greeting == nil ? browser.text("знак mica", "Знак mica") : browser.text("приветствие", "Приветствие"), editing: true, shown: $browser.prefs.start.wordmark, store: store, browser: browser)
                                            .transition(.opacity)
                                    }
                                    SwiftUI.Group {
                                        if let greeting {
                                            AssemblingText(text: Text(greeting).font(.system(size: 34, weight: .light)).tracking(-1.1).foregroundStyle(Palette.ink),
                                                           length: greeting.count, shown: shown || editing, delay: Entrance.step(2))
                                                .multilineTextAlignment(.center).lineLimit(2)
                                        } else {
                                            AssemblingText(text: Text("mica").font(.system(size: 40, weight: .light)).tracking(-1.6).foregroundStyle(Palette.ink),
                                                           length: 4, shown: shown || editing, delay: Entrance.step(2))
                                        }
                                    }
                                    .opacity(editing && !options.wordmark ? 0.4 : 1)
                                    .padding(.horizontal, editing ? StartLayout.inset : 0)
                                }
                                .modifier(StartEditFrame(editing: editing))
                                .transition(.opacity)
                            }
                            if browser.privateMode && !editing {
                                Label { Text(browser.text("инкогнито", "Инкогнито")) } icon: { Glyph(name: Glyph.incognito, size: 11.5) }
                                    .font(.system(size: 11.5, weight: .medium)).foregroundStyle(Palette.text2)
                                    .padding(.horizontal, 10).frame(height: 24)
                                    .background(Capsule().fill(Palette.track))
                                    // Slides out from behind the last letter once the wordmark has mostly assembled.
                                    .entrance(shown, delay: options.wordmark ? Entrance.step(2) + AssembleRenderer.total(glyphs: (greeting ?? "mica").count) * 0.55 : Entrance.step(2), rise: 0, dx: -14)
                            }
                        }
                        .transition(.opacity)
                    }
                    searchField(items)
                        .entrance(shown, delay: Entrance.step(3))
                        .opacity(editing ? 0.5 : 1)
                        .allowsHitTesting(!editing)
                    if text.isEmpty || editing {
                        if sections.isEmpty { hints.entrance(shown, delay: Entrance.step(4)) }
                        ForEach(Array(sections.enumerated()), id: \.element.section) { index, entry in
                            StartSectionView(section: entry.section, sites: entry.sites, browser: browser, store: store, editing: editing)
                                .entrance(shown, delay: Entrance.step(4 + index))
                                .transition(.opacity)
                        }
                    }
                    if browser.privateMode && !editing {
                        Text(browser.text("история и сессия этого окна не сохраняются. загруженные файлы остаются на диске.", "История и сессия этого окна не сохраняются. Загруженные файлы остаются на диске."))
                            .font(.system(size: 12)).foregroundStyle(Palette.text3).multilineTextAlignment(.center)
                            .entrance(shown, delay: Entrance.step(4 + sections.count))
                    }
                }
                .frame(maxWidth: 600)
                .padding(.horizontal, Space.large)
                .padding(.top, 96).padding(.bottom, editing ? 128 : 64)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.never)
        }
        .overlay(alignment: editing ? .bottom : .bottomTrailing) {
            if editing {
                StartCustomizeBar(store: store, browser: browser)
                    .padding(.horizontal, Space.normal).padding(.bottom, Space.normal)
                    .transition(Motion.slide(.bottom))
            } else {
                StartCustomizeButton(store: store, browser: browser) { withMotion(Motion.panel) { browser.customizingStart = true } }
                    .padding(Space.normal)
                    .entrance(shown, delay: Entrance.step(5 + sections.count), rise: 0)
                    .transition(.opacity)
            }
        }
        .animation(Motion.quick, value: text.isEmpty)
        .animation(Motion.quick, value: items.map(\.id))
        .animation(Motion.quick, value: options)
        .animation(Motion.panel, value: editing)
        .animation(Motion.hover, value: greeting)
        .onAppear { DispatchQueue.main.async { focused = true }; begin() }
        .onChange(of: browser.entered) { _, _ in begin() }
        .onDisappear { browser.customizingStart = false }
        .onChange(of: browser.focusAddress) { _, _ in focused = true }
        .onChange(of: browser.customizingToolbar) { _, on in if on { browser.customizingStart = false } }
        .onChange(of: editing) { _, on in if on { text = ""; focused = false } }
        .onChange(of: text) { _, _ in highlighted = 0 }
        .onExitCommand { if editing { withMotion(Motion.panel) { browser.customizingStart = false } } }
    }

    /// Plays the entrance once per tab, after the window is on screen so the first frames are not spent hidden.
    private func begin() {
        guard browser.entered, !shown else { return }
        browser.selected?.introduced = true
        shown = true
    }

    /// Sections in the user's order. Frequent sites never come from history in a private window;
    /// empty sections are skipped, except custom sites, which always offer the add tile.
    /// While customizing, every section is listed, hidden ones after the visible ones, empty ones too.
    private func visibleSections(_ options: StartPage, editing: Bool) -> [(section: StartSection, sites: [StartSite])] {
        let order = editing ? options.sections + StartSection.allCases.filter { !options.sections.contains($0) } : options.sections
        return order.compactMap { section in
            let sites: [StartSite]
            switch section {
            case .custom:
                sites = options.shortcuts.map { StartSite(id: $0.id.uuidString, title: $0.title, url: $0.url, shortcut: $0.id) }
                return (section, sites)
            case .frequent:
                if browser.privateMode { sites = [] } else {
                    let pinned = Set(options.shortcuts.compactMap { $0.url.host?.lowercased() })
                    sites = StartPage.frequent(store.history, excluding: Set(options.hiddenHosts).union(pinned), limit: options.frequentCount).map { StartSite(id: "f-" + ($0.url.host ?? ""), title: "", url: $0.url) }
                }
            case .bookmarks:
                sites = store.bookmarks.prefix(options.frequentCount).map { StartSite(id: "b-" + $0.id.uuidString, title: $0.title, url: $0.url) }
            }
            return sites.isEmpty && !editing ? nil : (section, sites)
        }
    }

    private func searchField(_ items: [Suggestion]) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .medium)).foregroundStyle(Palette.text2)
                TextField(browser.text("поиск в ", "Поиск в ") + store.preferences.search.title(browser.prefs.language) + browser.text(" или адрес", " или адрес"), text: $text)
                    .textFieldStyle(.plain).font(.system(size: 16)).focused($focused)
                    .onSubmit { if items.indices.contains(highlighted), highlighted > 0 || [.open, .search].contains(items[0].kind) { items[highlighted].activate(in: browser) } else if !text.isEmpty { browser.navigate(text) } }
                    .modifier(SuggestionKeys(count: items.count, highlighted: $highlighted))
                    .accessibilityLabel(browser.text("адресная строка", "Адресная строка"))
                if !focused { KeyHint(keys: "⌘L").transition(.opacity) }
            }
            .padding(.horizontal, 18).frame(height: 54)
            if !items.isEmpty && focused {
                Hairline()
                SuggestionList(items: items, highlighted: $highlighted) { $0.activate(in: browser) }.padding(Radius.panelPadding)
            }
        }
        .background(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous).fill(Palette.surface).shadow(color: focused ? Palette.shadowStrong : Palette.shadow, radius: focused ? 16 : 6, y: focused ? 6 : 2))
        .overlay(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous).strokeBorder(focused ? Palette.hairlineStrong : Palette.hairline, lineWidth: 1))
        .animation(Motion.quick, value: focused)
    }

    private var hints: some View {
        HStack(spacing: Space.section) {
            hint("⌘T", browser.text("вкладка", "Вкладка"))
            hint("⌘⇧N", browser.text("инкогнито", "Инкогнито"))
            hint("⌃⌘S", browser.text("боковая панель", "Боковая панель"))
        }
        .transition(.opacity)
    }
    private func hint(_ keys: String, _ title: String) -> some View {
        HStack(spacing: 6) { KeyHint(keys: keys); Text(title).font(.system(size: 12)).foregroundStyle(Palette.text3) }
    }
}
