import AppKit
import SwiftUI
import MicaCore

/// Icon button that opens a mica menu under itself; replaces the system pull-down menu.
struct MenuButton: View {
    let symbol: String
    let label: String
    var size: CGFloat = 24
    /// Changing it opens the menu as if clicked (a keyboard command for the same menu).
    var trigger = 0
    let entries: () -> [MenuEntry]
    @State private var anchor = PopupAnchor()
    @Environment(\.isEnabled) private var enabled
    init(symbol: String = "ellipsis", label: String, size: CGFloat = 24, trigger: Int = 0, @MenuBuilder entries: @escaping () -> [MenuEntry]) {
        self.symbol = symbol; self.label = label; self.size = size; self.trigger = trigger; self.entries = entries
    }
    var body: some View {
        IconButton(symbol: symbol, label: label, size: size) { open() }
        .background(PopupAnchorView(anchor: anchor))
        .help(label)
        .onChange(of: trigger) { if enabled { open() } }
    }
    private func open() {
        guard let view = anchor.view, let window = view.window else { return }
        let rect = window.convertToScreen(view.convert(view.bounds, to: nil))
        MicaMenu.shared.show(entries(), below: rect, in: window)
    }
}
