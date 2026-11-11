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
        applyProfile()
        if ProcessInfo.processInfo.arguments.contains("--qa") && ProcessInfo.processInfo.arguments.contains("--narrow") { window.setContentSize(NSSize(width: 640, height: 620)); window.center() }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    /// The first time the window is ordered in it fades in (MotionTokens.entrance.windowFade, shadow included), and the
    /// content card and start page start their entrance. Later calls only bring the window forward.
    override func showWindow(_ sender: Any?) {
        guard let window, !model.entered else { super.showWindow(sender); return }
        window.alphaValue = 0
        super.showWindow(sender)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.reduced ? MotionTokens.entrance.reducedFade : MotionTokens.entrance.windowFade
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }
        model.entered = true
    }
    /// Theme and title follow the window's profile; another window may show a different theme at the same time.
    func applyProfile() {
        guard let window else { return }
        let mode = Store.appearanceMode(model.prefs)
        let appearance = mode == .system ? nil : NSAppearance(named: mode == .dark ? .darkAqua : .aqua)
        if window.appearance?.name != appearance?.name { window.appearance = appearance }
        window.title = model.windowTitle
    }
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
        guard let window, let content = window.contentView, !window.styleMask.contains(.fullScreen), !placingWindowButtons else { return }
        placingWindowButtons = true
        defer { placingWindowButtons = false }
        for (index, type) in BrowserWindow.buttons.enumerated() {
            guard let button = window.standardWindowButton(type), let bar = button.superview else { continue }
            let size = button.frame.size
            // Align against the shell's first row, not AppKit's private titlebar view: its height and origin can
            // change as the window is resized or leaves full screen.
            let center = NSPoint(x: Chrome.lightsX + CGFloat(index) * Chrome.lightsStep + size.width / 2,
                                 y: content.isFlipped ? Chrome.bar / 2 : content.bounds.height - Chrome.bar / 2)
            let inBar = bar.convert(center, from: content)
            let target = NSPoint(x: inBar.x - size.width / 2, y: inBar.y - size.height / 2)
            if button.frame.origin != target { button.setFrameOrigin(target) }
        }
    }
    func windowDidResize(_ notification: Notification) { placeWindowButtons() }
    func windowDidEnterFullScreen(_ notification: Notification) { model.fullScreen = true }
    func windowDidExitFullScreen(_ notification: Notification) { model.fullScreen = false; placeWindowButtons() }
    func windowDidBecomeKey(_ notification: Notification) { model.store.updateTextStyle(); if !model.privateMode { model.store.extensions.controller.didFocusWindow(model) } }
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
