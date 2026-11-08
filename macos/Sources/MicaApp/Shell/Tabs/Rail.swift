import AppKit
import SwiftUI
import WebKit
import MicaCore
import UniformTypeIdentifiers

/// Site icon of a tab in the collapsed sidebar; same interactions as a tab row.
struct RailTile: View {
    @ObservedObject var tab: Tab
    @ObservedObject var browser: BrowserModel
    @State private var hover = false
    var body: some View {
        let selected = browser.selectedID == tab.id
        Button { browser.select(tab) } label: {
            TabIcon(tab: tab, size: 18)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(selected ? Palette.selected : hover ? Palette.hover : .clear).shadow(color: selected ? Palette.shadow : .clear, radius: 2, y: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.92))
        .onHover { hover = $0 }
        .animation(Motion.hover, value: hover)
        .animation(Motion.hover, value: selected)
        .help(tab.title.isEmpty ? (tab.url?.host ?? browser.text("новая вкладка", "Новая вкладка")) : tab.title)
        .accessibilityLabel((tab.pinned ? browser.text("закреплена: ", "Закреплена: ") : "") + (tab.title.isEmpty ? browser.text("новая вкладка", "Новая вкладка") : tab.title))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .modifier(TabInteractions(tab: tab, browser: browser))
    }
}

struct RailPlus: View {
    @ObservedObject var browser: BrowserModel
    @State private var hover = false
    var body: some View {
        Button { _ = browser.add(); browser.focusAddress += 1 } label: {
            Image(systemName: "plus").font(.system(size: 13, weight: .medium))
                .foregroundStyle(hover ? Palette.ink : Palette.text2)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(hover ? Palette.pressed : Palette.hover))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.92))
        .onHover { hover = $0 }.animation(Motion.hover, value: hover)
        .help(browser.text("новая вкладка", "Новая вкладка") + " ⌘T")
        .accessibilityLabel(browser.text("новая вкладка", "Новая вкладка"))
    }
}
