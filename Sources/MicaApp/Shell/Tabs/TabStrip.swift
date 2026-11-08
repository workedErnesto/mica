import AppKit
import SwiftUI
import WebKit
import MicaCore
import UniformTypeIdentifiers

/// Horizontal tabs share the width evenly; the new-tab button sits right after the last tab, in the tab colour.
struct TabStrip: View {
    @ObservedObject var browser: BrowserModel
    @State private var hoverPlus = false
    private let plus: CGFloat = 32
    var body: some View {
        GeometryReader { geo in
            let regular = browser.tabs.filter { !$0.pinned }.count
            let pinned = browser.tabs.count - regular
            let free = geo.size.width - plus - Space.micro - CGFloat(pinned) * (44 + Space.micro) - CGFloat(max(0, regular - 1)) * Space.micro
            let width = regular == 0 ? 0 : min(240, max(130, free / CGFloat(regular)))
            ScrollView(.horizontal) {
                HStack(spacing: Space.micro) {
                    ForEach(browser.tabs) { tab in
                        SwiftUI.Group {
                            if tab.pinned { PinnedTile(tab: tab, browser: browser).frame(width: 44) }
                            else { TabRow(tab: tab, browser: browser, horizontal: true).frame(width: width) }
                        }
                        .transition(Motion.pop)
                    }
                    Button { _ = browser.add(); browser.focusAddress += 1 } label: {
                        Image(systemName: "plus").font(.system(size: 12, weight: .medium))
                            .foregroundStyle(hoverPlus ? Palette.ink : Palette.text2)
                            .frame(width: plus, height: 32)
                            .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(hoverPlus ? Palette.pressed : Palette.hover))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle(scale: 0.92))
                    .onHover { hoverPlus = $0 }.animation(Motion.hover, value: hoverPlus)
                    .help(browser.text("новая вкладка", "Новая вкладка") + " ⌘T")
                    .accessibilityLabel(browser.text("новая вкладка", "Новая вкладка"))
                }
                .animation(Motion.quick, value: browser.tabs.map(\.id))
                .animation(Motion.quick, value: width)
            }
            .scrollIndicators(.never)
        }
        .frame(height: 32)
    }
}
