import AppKit
import SwiftUI
import MicaCore

/// A popover with a form in it, drawn by mica instead of NSPopover: the raised card of the shell menus, without an
/// arrow, growing out of the control that opened it. Unlike SwiftUI's `.popover`, which is transient, it stays open while the user
/// goes to another window or app and comes back, and closes only on its own buttons, Esc, a click elsewhere in its
/// window, or when the window resizes or closes. It is a child window, so it moves together with its window.
struct StickyPopover<Body: View>: NSViewRepresentable {
    @Binding var isPresented: Bool
    let content: () -> Body

    func makeCoordinator() -> FormPopover { FormPopover() }
    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        let popover = context.coordinator
        popover.dismiss = { isPresented = false }
        if isPresented {
            guard !popover.isOpen else { return }
            // The view may not be in a window during the first update; present once it is.
            DispatchQueue.main.async {
                guard isPresented, !popover.isOpen, view.window != nil else { return }
                popover.show(from: view) { content() }
            }
        } else if popover.isOpen {
            popover.close(animated: true, notify: false)
        }
    }

    static func dismantleNSView(_ view: NSView, coordinator: FormPopover) {
        coordinator.close(animated: false, notify: false)
    }
}

extension View {
    func stickyPopover<Content: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) -> some View {
        background(StickyPopover(isPresented: isPresented, content: content))
    }
}

@MainActor
final class FormPopoverModel: ObservableObject {
    @Published var shown = false
    /// The control's centre across the card's width (0...1): the card grows from there. And whether it opens below.
    @Published var origin: CGFloat = 0.5
    @Published var below = true
}

/// Takes keyboard focus for the fields inside, unlike the menu panel.
final class FormPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class FormPopover {
    static let gap: CGFloat = 6
    let model = FormPopoverModel()
    var dismiss: () -> Void = {}
    private var panel: FormPanel?
    private weak var parent: NSWindow?
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    var isOpen: Bool { panel != nil }

    func show<Content: View>(from view: NSView, @ViewBuilder content: () -> Content) {
        guard let window = view.window else { return }
        close(animated: false, notify: false)
        model.shown = false
        let store = Store.shared
        let root = FormChrome(model: model) { content() }
            .environment(\.look, store.look(for: window))
            .environment(\.locale, store.locale)
        let host = NSHostingView(rootView: AnyView(root))
        let size = host.fittingSize
        let margin = MicaMenu.margin
        let card = NSSize(width: size.width - 2 * margin, height: size.height - 2 * margin)
        let anchor = window.convertToScreen(view.convert(view.bounds, to: nil))
        // Keep the card inside the window, so it never hangs past the edge it belongs to.
        let bounds = window.frame.insetBy(dx: 8, dy: 8)
        var x = anchor.midX - card.width / 2
        x = min(max(x, bounds.minX), bounds.maxX - card.width)
        var below = true
        var y = anchor.minY - Self.gap - card.height
        let screen = (window.screen ?? NSScreen.main)?.visibleFrame ?? bounds
        if y < max(bounds.minY, screen.minY) { y = anchor.maxY + Self.gap; below = false }
        model.origin = min(max((anchor.midX - x) / card.width, 0), 1)
        model.below = below
        let panel = FormPanel(contentRect: NSRect(x: x - margin, y: y - margin, width: size.width, height: size.height), styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        panel.appearance = window.effectiveAppearance
        panel.contentView = host
        window.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
        parent = window
        watch(window)
        withMotion(Motion.reduced ? .easeOut(duration: 0.1) : .spring(response: 0.24, dampingFraction: 0.88)) { model.shown = true }
        NSAccessibility.post(element: host, notification: .created)
    }

    /// `notify` tells the owner the popover closed on its own (Esc, a click elsewhere), so its binding turns off.
    func close(animated: Bool, notify: Bool) {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors = []
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        guard let panel else { return }
        self.panel = nil
        let parent = parent
        let wasKey = panel.isKeyWindow
        if animated {
            withAnimation(.easeOut(duration: 0.1)) { model.shown = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { parent?.removeChildWindow(panel); panel.orderOut(nil) }
        } else { parent?.removeChildWindow(panel); panel.orderOut(nil) }
        if wasKey { parent?.makeKey() }
        if notify { dismiss() }
    }

    private func watch(_ window: NSWindow) {
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self, self.panel != nil, event.window === window else { return event }
            self.close(animated: true, notify: true)
            // The click only closes the form, as with a popover; a right click still opens its menu.
            return event.type == .rightMouseDown ? event : nil
        } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self, let panel = self.panel, event.window === panel, event.keyCode == 53 else { return event }
            self.close(animated: true, notify: true)
            return nil
        } as Any)
        let center = NotificationCenter.default
        for name in [NSWindow.didResizeNotification, NSWindow.willCloseNotification, NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification] {
            observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.close(animated: false, notify: true) }
            })
        }
    }
}

private struct FormChrome<Content: View>: View {
    @ObservedObject var model: FormPopoverModel
    @ViewBuilder var content: Content
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
        content
            .background(shape.fill(Palette.raised))
            .overlay(shape.strokeBorder(Palette.hairline, lineWidth: 1))
            .shadow(color: Palette.menuShadow, radius: 10, y: 4)
            .scaleEffect(model.shown || reduced ? 1 : 0.94, anchor: UnitPoint(x: model.origin, y: model.below ? 0 : 1))
            .offset(y: model.shown || reduced ? 0 : model.below ? -4 : 4)
            .opacity(model.shown ? 1 : 0)
            .padding(MicaMenu.margin)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
    }
}
