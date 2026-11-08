import AppKit
import SwiftUI
import WebKit
import MicaCore
import UniformTypeIdentifiers

/// Tab status: microphone or camera in use, a crashed page, load progress, otherwise the site icon
/// (dimmed until a restored tab loads).
struct TabIcon: View {
    @ObservedObject var tab: Tab
    var size: CGFloat = 16
    /// Rail tiles: a monogram without its own plate, coloured like the neighbouring glyphs.
    var plain = false
    var tint: Color = Palette.text2
    var body: some View {
        ZStack {
            if tab.capturing { Image(systemName: "mic.fill").font(.system(size: size * 0.7)).foregroundStyle(Palette.live) }
            else if tab.phase == .terminated { Image(systemName: "exclamationmark.triangle").font(.system(size: size * 0.7)).foregroundStyle(Palette.text2) }
            else if tab.loading { ProgressRing(progress: tab.progress, size: size) }
            else if let favicons = tab.owner?.favicons { SiteIcon(host: tab.url?.host, favicons: favicons, size: size, plain: plain, tint: tint).opacity(tab.phase == .restored ? 0.55 : 1) }
            else { Monogram(host: tab.url?.host, size: size, plain: plain, tint: tint).opacity(tab.phase == .restored ? 0.55 : 1) }
        }
        .frame(width: size, height: size)
        .animation(Motion.hover, value: tab.loading)
    }
}

struct TabRow: View {
    @ObservedObject var tab: Tab
    @ObservedObject var browser: BrowserModel
    let horizontal: Bool
    @State private var hover = false
    var selected: Bool { browser.selectedID == tab.id }
    var body: some View {
        Button { browser.select(tab) } label: {
            HStack(spacing: 9) {
                TabIcon(tab: tab)
                Text(tab.title.isEmpty ? (tab.url?.host ?? browser.text("новая вкладка", "Новая вкладка")) : tab.title)
                    .font(.system(size: 12.5, weight: selected ? .medium : .regular))
                    .foregroundStyle(selected ? Palette.ink : tab.phase == .restored ? Palette.text3 : Palette.text2)
                    .lineLimit(1)
                Spacer(minLength: 22)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: horizontal ? 30 : 34)
            .background {
                RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                    .fill(selected ? Palette.selected : hover ? (horizontal ? Palette.pressed : Palette.hover) : (horizontal ? Palette.hover : .clear))
                    .shadow(color: selected ? Palette.shadow : .clear, radius: 2, y: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.98))
        .overlay(alignment: .trailing) {
            if horizontal && tab.pinned && !hover {
                Image(systemName: "pin").font(.system(size: 10))
                    .foregroundStyle(Palette.text2).frame(width: 22, height: 22)
                    .padding(.trailing, 5).accessibilityHidden(true).transition(.opacity)
            }
            if hover || (selected && !horizontal) {
                IconButton(symbol: "xmark", label: browser.text("закрыть: ", "Закрыть: ") + tab.title, size: 22) { withMotion(Motion.quick) { browser.close(tab) } }
                    .padding(.trailing, 5)
                    .transition(.opacity)
            }
        }
        .onHover { hover = $0 }
        .animation(Motion.hover, value: hover)
        .animation(Motion.hover, value: selected)
        .accessibilityElement(children: .contain)
        .accessibilityLabel((tab.pinned ? browser.text("закреплена: ", "Закреплена: ") : "") + (tab.title.isEmpty ? browser.text("новая вкладка", "Новая вкладка") : tab.title))
        .accessibilityValue(selected ? browser.text("выбрана", "Выбрана") : tab.phase == .restored ? browser.text("ещё не загружена", "Ещё не загружена") : "")
        .modifier(TabInteractions(tab: tab, browser: browser))
    }
}

struct PinnedTile: View {
    @ObservedObject var tab: Tab
    @ObservedObject var browser: BrowserModel
    var height: CGFloat = 44
    @State private var hover = false
    var body: some View {
        let selected = browser.selectedID == tab.id
        Button { browser.select(tab) } label: {
            TabIcon(tab: tab, size: 20)
                .frame(maxWidth: .infinity).frame(height: height)
                .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(selected ? Palette.selected : hover ? Palette.pressed : Palette.hover).shadow(color: selected ? Palette.shadow : .clear, radius: 2, y: 1))
                .overlay(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).strokeBorder(selected ? Palette.hairlineStrong : .clear, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.94))
        .animation(Motion.hover, value: hover)
        .help(tab.title)
        .accessibilityLabel(browser.text("закреплена: ", "Закреплена: ") + tab.title)
        .modifier(TileCloseBadge(tab: tab, browser: browser, hover: $hover))
        .modifier(TabInteractions(tab: tab, browser: browser))
    }
}

struct TabInteractions: ViewModifier {
    @ObservedObject var tab: Tab
    @ObservedObject var browser: BrowserModel
    func body(content: Content) -> some View {
        content
            .onDrag { NSItemProvider(object: tab.id.uuidString as NSString) }
            .onDrop(of: [.text], isTargeted: nil) { providers in
                guard let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: String.self) { string, _ in
                    guard let string, let id = UUID(uuidString: string) else { return }
                    Task { @MainActor in withMotion(Motion.quick) { browser.move(id, before: tab.id) } }
                }; return true
            }
            .micaContextMenu {
                MenuEntry.item(browser.text("дублировать", "Дублировать"), symbol: "plus.square.on.square") { _ = browser.add(saved: SavedTab(url: tab.url, title: tab.title)) }
                MenuEntry.item(tab.pinned ? browser.text("открепить", "Открепить") : browser.text("закрепить", "Закрепить"), symbol: tab.pinned ? "pin.slash" : "pin") { withMotion(Motion.quick) { browser.pin(tab) } }
                MenuEntry.item(browser.text("перезагрузить", "Перезагрузить"), symbol: "arrow.clockwise", enabled: tab.url != nil) { tab.reload() }
                MenuEntry.item(browser.text("копировать адрес", "Копировать адрес"), symbol: "link", enabled: tab.url != nil) { if let url = tab.url { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(url.absoluteString, forType: .string) } }
                MenuEntry.item(browser.text("открыть в новом окне", "Открыть в новом окне"), symbol: "macwindow") { let window = browser.store.newWindow(privateMode: browser.privateMode); if let url = tab.url { window.selected?.load(url) } }
                MenuEntry.divider
                MenuEntry.item(browser.text("закрыть остальные", "Закрыть остальные"), symbol: "xmark.square") { withMotion(Motion.quick) { for other in browser.tabs where other.id != tab.id && !other.pinned { browser.close(other) } } }
                MenuEntry.item(browser.text("закрыть все", "Закрыть все"), symbol: "xmark.rectangle") { withMotion(Motion.quick) { browser.closeAll() } }
                MenuEntry.item(browser.text("закрыть вкладку", "Закрыть вкладку"), symbol: "xmark") { withMotion(Motion.quick) { browser.close(tab) } }
            }
    }
}
