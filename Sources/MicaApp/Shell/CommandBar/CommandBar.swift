import AppKit
import SwiftUI
import WebKit
import MicaCore
import UniformTypeIdentifiers

struct CommandBar: View {
    @ObservedObject var browser: BrowserModel
    @ObservedObject var store: Store
    @State private var text = ""
    @State private var highlighted = 0
    @State private var shown = false
    @FocusState private var focused: Bool
    var body: some View {
        let items = Suggestion.make(text, browser: browser, store: store)
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Color.black.opacity(0.14).ignoresSafeArea().onTapGesture { close() }
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .medium)).foregroundStyle(Palette.text2)
                        TextField(browser.text("адрес или поиск", "Адрес или поиск"), text: $text)
                            .textFieldStyle(.plain).font(.system(size: 16)).focused($focused)
                            .onSubmit { submit(items) }
                            .modifier(SuggestionKeys(count: items.count, highlighted: $highlighted))
                            .accessibilityLabel(browser.text("адресная строка", "Адресная строка"))
                        KeyHint(keys: "esc")
                    }
                    .padding(.horizontal, 16).frame(height: 52)
                    if !items.isEmpty {
                        Hairline()
                        SuggestionList(items: items, highlighted: $highlighted) { choose($0) }.padding(Radius.panelPadding)
                    }
                }
                .frame(width: min(640, geo.size.width - 64))
                .modifier(RaisedSurface(radius: Radius.panel))
                .scaleEffect(shown || Motion.reduced ? 1 : 0.97, anchor: .top)
                .offset(y: shown || Motion.reduced ? 0 : -6)
                .padding(.top, max(56, geo.size.height * 0.14))
            }
        }
        .onChange(of: text) { _, _ in highlighted = 0 }
        .onExitCommand { close() }
        .onAppear {
            text = browser.selected?.url?.absoluteString ?? ""
            focused = true
            withMotion(Motion.quick) { shown = true }
            DispatchQueue.main.async { (NSApp.keyWindow?.firstResponder as? NSTextView)?.selectAll(nil) }
        }
    }
    private func submit(_ items: [Suggestion]) {
        if items.indices.contains(highlighted), highlighted > 0 || [.open, .search].contains(items[0].kind) { choose(items[highlighted]) }
        else if !text.isEmpty { browser.navigate(text); close() }
    }
    private func choose(_ item: Suggestion) { item.activate(in: browser); close() }
    private func close() { browser.commandBar = false }
}
