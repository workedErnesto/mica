import AppKit
import SwiftUI
import MicaCore

/// AppKit view that answers only right clicks and Control-clicks, so ordinary clicks, drags and hover
/// go to the SwiftUI content under it. Nested areas each have one; the smallest one under the pointer wins.
class MenuCatcherView: NSView {
    var entries: () -> [MenuEntry] = { [] }
    /// Areas inside the toolbar editor keep their menus while the rest of the window is covered by it.
    var activeWhileCustomizing = false
    private static let all = NSHashTable<MenuCatcherView>.weakObjects()
    private static var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            Self.all.add(self)
            Self.installMonitor()
        } else { Self.all.remove(self) }
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == self ? passThrough() : nil
    }
    /// Subclasses that handle ordinary clicks themselves return self here.
    func passThrough() -> NSView? { nil }
    static func secondary(_ event: NSEvent) -> Bool {
        event.type == .rightMouseDown || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
    }
    private static func installMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { event in
            guard secondary(event), let window = event.window else { return event }
            let point = event.locationInWindow
            let candidates = all.allObjects.filter { view in
                view.window === window && !view.isHiddenOrHasHiddenAncestor && !view.covered && view.convert(view.bounds, to: nil).contains(point)
            }.sorted { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }
            for view in candidates {
                let entries = view.entries().tidy
                if !entries.isEmpty {
                    MicaMenu.shared.show(entries, at: NSEvent.mouseLocation, in: window)
                    return nil
                }
            }
            return event
        }
    }
    /// Settings and the command bar cover the shell; the toolbar editor covers everything except its own tiles.
    private var covered: Bool {
        guard let model = Store.shared.windows.first(where: { $0.window === window })?.model else { return false }
        return model.modal || model.commandBar || (model.customizingToolbar && !activeWhileCustomizing)
    }
    override func rightMouseDown(with event: NSEvent) { present(event) }
    override func mouseDown(with event: NSEvent) {
        if Self.secondary(event) { present(event) } else { super.mouseDown(with: event) }
    }
    func present(_ event: NSEvent) {
        let point = event.locationInWindow
        let candidates = Self.all.allObjects.filter { view in
            view.window === window && !view.isHiddenOrHasHiddenAncestor && !view.covered && view.convert(view.bounds, to: nil).contains(point)
        }
        let ordered = candidates.sorted { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }
        for view in ordered {
            let entries = view.entries().tidy
            if !entries.isEmpty { MicaMenu.shared.show(entries, at: NSEvent.mouseLocation, in: window); return }
        }
    }
}

struct MenuCatcher: NSViewRepresentable {
    let entries: () -> [MenuEntry]
    var activeWhileCustomizing = false
    func makeNSView(context: Context) -> MenuCatcherView { let view = MenuCatcherView(); update(view); return view }
    func updateNSView(_ view: MenuCatcherView, context: Context) { update(view) }
    private func update(_ view: MenuCatcherView) { view.entries = entries; view.activeWhileCustomizing = activeWhileCustomizing }
}

extension View {
    /// mica's context menu: a right click or Control-click on this view opens it.
    func micaContextMenu(activeWhileCustomizing: Bool = false, @MenuBuilder _ entries: @escaping () -> [MenuEntry]) -> some View {
        overlay(MenuCatcher(entries: entries, activeWhileCustomizing: activeWhileCustomizing))
    }
}
