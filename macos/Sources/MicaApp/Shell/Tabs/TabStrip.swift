import AppKit
import SwiftUI
import WebKit
import MicaCore
import UniformTypeIdentifiers

/// Horizontal tabs share the width evenly; the new-tab button sits right after the last tab, in the tab colour.
/// In the title bar band (`titleBand`) the strip keeps free space at its end, where the window can still be dragged.
struct TabStrip: View {
    @ObservedObject var browser: BrowserModel
    var titleBand = false
    @State private var hoverPlus = false
    private let plus: CGFloat = 32
    /// Empty title band left after the tabs, so the window always has somewhere to be dragged by.
    private static let dragRoom: CGFloat = 64
    var body: some View {
        GeometryReader { geo in
            let regular = browser.tabs.count
            let available = geo.size.width - (titleBand ? Self.dragRoom : 0)
            let fixed = plus + CGFloat(browser.tabs.count) * Space.micro
            let width = regular == 0 ? 0 : min(240, max(130, (available - fixed) / CGFloat(regular)))
            let content = fixed + CGFloat(regular) * width
            HStack(spacing: 0) {
                strip(width).frame(width: titleBand ? max(0, min(content, available)) : nil, height: 32)
                if titleBand { Spacer(minLength: 0) }
            }
            .frame(height: geo.size.height, alignment: .center)
            .animation(Motion.quick, value: content)
        }
        // In the band the strip is as tall as it, so the tabs share the window buttons' centre line.
        .frame(height: titleBand ? Chrome.bar : 32)
    }
    private func strip(_ width: CGFloat) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: Space.micro) {
                ForEach(browser.tabs) { tab in
                    TabRow(tab: tab, browser: browser, horizontal: true).frame(width: width).transition(Motion.pop)
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
        .scrollClipDisabled()
        .mask { Rectangle().padding(.vertical, -TileCloseBadge.overhang) }
        .scrollIndicators(.never)
    }
}
