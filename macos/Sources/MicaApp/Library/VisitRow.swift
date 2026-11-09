import AppKit
import SwiftUI
import MicaCore

struct VisitRow: View {
    let visit: Visit
    let panel: Panel
    @ObservedObject var browser: BrowserModel
    @ObservedObject var store: Store
    @State private var hover = false
    var body: some View {
        Button { browser.selected?.load(visit.url) } label: {
            HStack(spacing: 10) {
                SiteIcon(url: visit.url, favicons: browser.favicons, size: Chrome.rowIcon, tiled: true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(visit.title.isEmpty ? visit.url.absoluteString : visit.title).font(.system(size: 12.5)).foregroundStyle(Palette.ink).lineLimit(1)
                    HStack(spacing: 6) {
                        Text(visit.url.host ?? visit.url.absoluteString).lineLimit(1)
                        if panel == .history { Text(visit.date, style: .time) }
                    }
                    .font(.system(size: 11)).foregroundStyle(Palette.text3)
                }
                Spacer(minLength: 24)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(hover ? Palette.hover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.98))
        .overlay(alignment: .trailing) {
            if hover {
                MenuButton(label: browser.text("действия", "Действия")) {
                    MenuEntry.item(browser.text("открыть в новой вкладке", "Открыть в новой вкладке"), symbol: "plus.square") { browser.open(visit.url) }
                    MenuEntry.item(browser.text("копировать адрес", "Копировать адрес"), symbol: "link") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(visit.url.absoluteString, forType: .string) }
                    MenuEntry.divider
                    if panel == .history, let host = visit.url.host {
                        MenuEntry.item(browser.text("удалить всё с сайта ", "Удалить всё с сайта ") + host, symbol: "trash.slash", destructive: true) { withMotion(Motion.quick) { store.history = History.removing(store.history, host: host) } }
                    }
                    MenuEntry.item(browser.text("удалить", "Удалить"), symbol: "trash", destructive: true) { withMotion(Motion.quick) { if panel == .history { store.history.removeAll { $0.id == visit.id } } else { store.bookmarks.removeAll { $0.id == visit.id } } } }
                }
                .padding(.trailing, 6)
                .transition(.opacity)
            }
        }
        .onHover { hover = $0 }.animation(Motion.hover, value: hover)
    }
}
