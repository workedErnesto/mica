import AppKit
import SwiftUI
import MicaCore

@MainActor
final class MenuModel: ObservableObject {
    @Published var entries: [MenuEntry] = []
    @Published var highlighted: Int?
    @Published var shown = false
    /// Corner the menu grows from: the click point or the button it hangs from.
    var anchor: UnitPoint = .topLeading
}

/// Shows one menu at a time and closes it on a click elsewhere, Esc, a choice or when mica loses focus.
@MainActor
final class MicaMenu {
    static let shared = MicaMenu()
    let model = MenuModel()
    private var panel: MenuPanel?
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    /// Transparent room around the menu in its window for the shadow and the opening scale.
    static let margin: CGFloat = 24

    var isOpen: Bool { panel?.isVisible == true && model.shown }

    /// Opens at a point in screen coordinates (a right click).
    func show(_ entries: [MenuEntry], at point: NSPoint, in window: NSWindow?) {
        present(entries, window: window) { size, screen in
            var origin = NSPoint(x: point.x, y: point.y - size.height)
            var anchor = UnitPoint.topLeading
            if origin.y < screen.minY + 4 { origin.y = point.y; anchor = .bottomLeading }
            if origin.x + size.width > screen.maxX - 4 { origin.x = point.x - size.width; anchor = anchor == .topLeading ? .topTrailing : .bottomTrailing }
            return (origin, anchor)
        }
    }

    /// Opens under a control (screen rectangle), or above it when there is no room below.
    func show(_ entries: [MenuEntry], below rect: NSRect, in window: NSWindow?) {
        present(entries, window: window) { size, screen in
            var origin = NSPoint(x: rect.minX, y: rect.minY - 4 - size.height)
            var anchor = UnitPoint.topLeading
            if origin.y < screen.minY + 4 { origin.y = rect.maxY + 4; anchor = .bottomLeading }
            if origin.x + size.width > screen.maxX - 4 { origin.x = rect.maxX - size.width; anchor = anchor == .topLeading ? .topTrailing : .bottomTrailing }
            return (origin, anchor)
        }
    }

    private func present(_ entries: [MenuEntry], window: NSWindow?, place: (NSSize, NSRect) -> (NSPoint, UnitPoint)) {
        let entries = entries.tidy
        guard !entries.isEmpty else { return }
        close(animated: false)
        model.entries = entries
        model.highlighted = nil
        model.shown = false
        let store = Store.shared
        let root = MenuView(model: model) { [weak self] index in self?.choose(index) }
            .environment(\.look, store.look(for: window))
            .environment(\.locale, store.locale)
        let host = FirstMouseHost(rootView: AnyView(root))
        let size = host.fittingSize
        let content = NSSize(width: size.width - 2 * Self.margin, height: size.height - 2 * Self.margin)
        let screen = (window?.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let (origin, anchor) = place(content, screen)
        model.anchor = anchor
        let panel = MenuPanel(contentRect: NSRect(x: origin.x - Self.margin, y: origin.y - Self.margin, width: size.width, height: size.height), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.level = .popUpMenu; panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = true
        panel.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        panel.appearance = window?.effectiveAppearance ?? NSApp.effectiveAppearance
        panel.contentView = host
        panel.orderFront(nil)
        self.panel = panel
        watch(window)
        withMotion(Motion.reduced ? .easeOut(duration: 0.1) : .spring(response: 0.2, dampingFraction: 0.9)) { model.shown = true }
        NSAccessibility.post(element: host, notification: .created)
    }

    func close(animated: Bool = true) {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors = []
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        guard let panel else { return }
        self.panel = nil
        if animated {
            withAnimation(.easeOut(duration: 0.1)) { model.shown = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { panel.orderOut(nil) }
        } else { panel.orderOut(nil) }
    }

    /// The action runs right away; the menu fades out after it.
    private func choose(_ index: Int) {
        guard model.entries.indices.contains(index), model.entries[index].kind == .action, model.entries[index].enabled else { return }
        let action = model.entries[index].action
        close()
        action()
    }

    private func move(_ step: Int) {
        let candidates = model.entries.indices.filter { model.entries[$0].kind == .action && model.entries[$0].enabled }
        guard !candidates.isEmpty else { return }
        guard let current = model.highlighted, let position = candidates.firstIndex(of: current) else {
            model.highlighted = step > 0 ? candidates.first : candidates.last; return
        }
        model.highlighted = candidates[(position + step + candidates.count) % candidates.count]
    }

    private func watch(_ window: NSWindow?) {
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self, let panel = self.panel, event.window !== panel else { return event }
            self.close()
            // A right click elsewhere opens the menu of that place, as in system menus; other clicks only close.
            return event.type == .rightMouseDown ? event : nil
        } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
            if event.window !== self?.panel { self?.close() }
            return event
        } as Any)
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.close() }
        } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            switch event.keyCode {
            case 53: self.close()
            case 125: self.move(1)
            case 126: self.move(-1)
            case 36, 76, 49: if let index = self.model.highlighted { self.choose(index) }
            default: break
            }
            return nil
        } as Any)
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.close(animated: false) } })
        if let window {
            for name in [NSWindow.willMoveNotification, NSWindow.didResizeNotification, NSWindow.willCloseNotification, NSWindow.didResignKeyNotification] {
                observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in Task { @MainActor in self?.close(animated: false) } })
            }
        }
    }
}

final class MenuPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The menu window never becomes key, so its first click must act without activating it first.
final class FirstMouseHost: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
