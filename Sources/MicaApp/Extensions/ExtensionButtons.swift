import AppKit
import SwiftUI
import WebKit
import MicaCore
import UniformTypeIdentifiers

/// Top bar: one button per running extension, then the puzzle that opens the extensions panel.
struct ExtensionActions: View {
    @ObservedObject var manager: ExtensionManager
    @ObservedObject var browser: BrowserModel
    @ObservedObject var store: Store
    var body: some View {
        HStack(spacing: 2) {
            ExtensionStrip(manager: manager, browser: browser)
            IconButton(symbol: "puzzlepiece.extension", label: browser.text("расширения", "Расширения"), selected: browser.panel == .extensions) { browser.panel = browser.panel == .extensions ? nil : .extensions }
        }
    }
}

/// Buttons of the running extensions; a click runs the extension's action or opens its popup under the button.
/// Extensions never run in incognito windows, so the strip is empty there.
struct ExtensionStrip: View {
    @ObservedObject var manager: ExtensionManager
    @ObservedObject var browser: BrowserModel
    var vertical = false
    var body: some View {
        let records = manager.actionable(privateWindow: browser.privateMode)
        let buttons = ForEach(records) { record in ExtensionButton(record: record, manager: manager, browser: browser).transition(Motion.pop) }
        SwiftUI.Group {
            if vertical { VStack(spacing: 2) { buttons } }
            else if records.count > 6 { ScrollView(.horizontal) { HStack(spacing: 2) { buttons } }.scrollIndicators(.never).frame(maxWidth: 6 * Chrome.item) }
            else { HStack(spacing: 2) { buttons } }
        }
        .animation(Motion.quick, value: records.map(\.id))
    }
}

struct ExtensionButton: View {
    let record: ExtensionRecord
    @ObservedObject var manager: ExtensionManager
    @ObservedObject var browser: BrowserModel
    @State private var anchor = PopupAnchor()
    @State private var hover = false
    var body: some View {
        let context = manager.contexts[record.id]
        let action = context?.action(for: browser.selected)
        let label = action.map { $0.label.isEmpty ? record.name : $0.label } ?? record.name
        let enabled = action?.isEnabled ?? true
        Button { manager.popupAnchor = anchor.view; manager.action(record, tab: browser.selected) } label: {
            SwiftUI.Group {
                if let image = action?.icon(for: CGSize(width: 16, height: 16)) ?? context?.webExtension.icon(for: CGSize(width: 16, height: 16)) {
                    Image(nsImage: image).resizable().interpolation(.high).frame(width: 16, height: 16)
                } else { Monogram(host: record.name, size: 16) }
            }
            .opacity(enabled ? 1 : 0.45)
            .frame(width: 28, height: 28)
            .background(RoundedRectangle(cornerRadius: Radius.icon, style: .continuous).fill(hover ? Palette.hover : .clear))
            .overlay(alignment: .topTrailing) {
                if let badge = action?.badgeText, !badge.isEmpty {
                    Text(badge).font(.system(size: 8.5, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                        .padding(.horizontal, 3).frame(minWidth: 13, minHeight: 12)
                        .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color(nsColor: .systemRed)))
                        .offset(x: 2, y: -1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: Radius.icon, style: .continuous))
        }
        .buttonStyle(PressStyle(scale: 0.9))
        .background(PopupAnchorView(anchor: anchor))
        .disabled(!enabled)
        .onHover { hover = $0 && enabled }
        .animation(Motion.hover, value: hover)
        .help(label)
        .accessibilityLabel(label)
        .micaContextMenu {
            MenuEntry.item(browser.text("настройки расширения", "Настройки расширения"), enabled: context?.optionsPageURL != nil) { manager.options(record) }
            MenuEntry.item(browser.text("разрешить текущий сайт", "Разрешить текущий сайт"), enabled: browser.selected?.url != nil) { Task { await manager.allowCurrentSite(record, tab: browser.selected) } }
            MenuEntry.divider
            MenuEntry.item(browser.text("управление расширениями", "Управление расширениями")) { browser.panel = .extensions }
        }
    }
}

/// Holds the AppKit view behind an extension button so the popup opens under the button that was clicked.
final class PopupAnchor { weak var view: NSView? }

struct PopupAnchorView: NSViewRepresentable {
    let anchor: PopupAnchor
    func makeNSView(context: Context) -> NSView { let view = NSView(); anchor.view = view; return view }
    func updateNSView(_ view: NSView, context: Context) { anchor.view = view }
}
