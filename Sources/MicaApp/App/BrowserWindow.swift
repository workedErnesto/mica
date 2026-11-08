import AppKit
import SwiftUI
import WebKit
import Combine
import MicaCore

@MainActor
final class BrowserWindow: NSWindowController, NSWindowDelegate {
    let model: BrowserModel
    init(model: BrowserModel) {
        self.model = model
        let visible = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
        let initial = NSSize(width: min(1640, max(980, visible.width * 0.9)), height: min(1080, max(680, visible.height * 0.92)))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: initial), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init(window: window)
        model.controller = self
        window.title = "mica"; window.titlebarAppearsTransparent = true; window.titleVisibility = .hidden
        window.minSize = NSSize(width: 620, height: 460); window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: BrowserRoot(browser: model, store: model.store))
        window.delegate = self; window.center(); window.setFrameAutosaveName((ProcessInfo.processInfo.arguments.contains("--qa") ? "qa-" : "") + (model.privateMode ? "private-window-2" : "browser-window-2"))
        window.collectionBehavior = [.fullScreenPrimary]
        window.titlebarSeparatorStyle = .none
        // The shell draws its own fill. A clear, non-opaque window lets the behind-window blur reach the desktop;
        // an opaque window background left the frosted material showing only a flat colour.
        window.isOpaque = false; window.backgroundColor = .clear
        for type in BrowserWindow.buttons {
            guard let button = window.standardWindowButton(type) else { continue }
            button.postsFrameChangedNotifications = true
            NotificationCenter.default.addObserver(self, selector: #selector(buttonFrameChanged(_:)), name: NSView.frameDidChangeNotification, object: button)
        }
        placeWindowButtons()
        if ProcessInfo.processInfo.arguments.contains("--qa") && ProcessInfo.processInfo.arguments.contains("--narrow") { window.setContentSize(NSSize(width: 640, height: 620)); window.center() }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    static let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
    private var placingWindowButtons = false
    private var windowButtonPlacementPending = false
    /// AppKit can reposition the other buttons while laying out one of them. Wait until that layout finishes.
    @objc func buttonFrameChanged(_ notification: Notification) {
        guard !placingWindowButtons, !windowButtonPlacementPending else { return }
        windowButtonPlacementPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.windowButtonPlacementPending = false
            self.placeWindowButtons()
        }
    }
    func placeWindowButtons() {
        guard let window, !window.styleMask.contains(.fullScreen), !placingWindowButtons else { return }
        placingWindowButtons = true
        defer { placingWindowButtons = false }
        for (index, type) in BrowserWindow.buttons.enumerated() {
            guard let button = window.standardWindowButton(type), let bar = button.superview else { continue }
            let size = button.frame.size
            let top = Chrome.bar / 2 - size.height / 2
            let y = bar.isFlipped ? top : bar.bounds.height - top - size.height
            let target = NSPoint(x: Chrome.lightsX + CGFloat(index) * Chrome.lightsStep, y: max(0, y))
            if button.frame.origin != target { button.setFrameOrigin(target) }
        }
    }
    func windowDidResize(_ notification: Notification) { placeWindowButtons() }
    func windowDidEnterFullScreen(_ notification: Notification) { model.fullScreen = true }
    func windowDidExitFullScreen(_ notification: Notification) { model.fullScreen = false; placeWindowButtons() }
    func windowDidBecomeKey(_ notification: Notification) { if !model.privateMode { model.store.extensions.controller.didFocusWindow(model) } }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        let running = model.downloads.items.contains { $0.state == .running || $0.state == .choosing }
        guard running else { return true }
        Task {
            let answer = await ask(title: model.text("закрыть окно и отменить загрузки?", "Закрыть окно и отменить загрузки?"), detail: model.text("незавершённые загрузки этого окна будут отменены", "Незавершённые загрузки этого окна будут отменены"), buttons: [model.text("отмена", "Отмена"), model.text("закрыть", "Закрыть")], window: sender)
            if answer == 1 { model.downloads.cancelAll(); sender.performClose(nil) }
        }; return false
    }
    func windowWillClose(_ notification: Notification) {
        let store = model.store
        if !model.privateMode { store.extensions.controller.didCloseWindow(model) }
        model.dispose()
        store.windows.removeAll { $0 === self }
        if !store.shuttingDown { store.scheduleSession() }
    }
}
