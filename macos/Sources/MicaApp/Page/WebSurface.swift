import AppKit
import SwiftUI
import WebKit
import MicaCore
import UniformTypeIdentifiers

struct WebSurface: NSViewRepresentable {
    let webView: WKWebView
    /// True while a mica overlay (settings, command bar) covers the page.
    var covered = false
    /// Dimming layer over the page. It never takes events: even fully transparent it would sit above the web view in
    /// hit testing, swallow clicks and keep the page from becoming first responder, so ⌘C, ⌘A and ⌘V had no target.
    final class Shade: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
    final class Host: NSView {
        let shade = Shade()
        var covered = false {
            didSet {
                guard covered != oldValue else { return }
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = Motion.reduced ? 0 : 0.16
                    shade.animator().alphaValue = covered ? 1 : 0
                }
                if !covered { focusPage() }
            }
        }
        /// A page that appears (tab switch, address entered on the start page) or comes back from under an overlay
        /// (command bar, settings, toolbar editor) takes keyboard focus, as in Safari, so edit shortcuts and keyboard
        /// scrolling reach it without a click first. The overlay's own field may still be fading out at that moment.
        func focusPage() {
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.covered, let window = self.window,
                      let page = self.subviews.first(where: { $0 is WKWebView }), window.firstResponder !== page else { return }
                window.makeFirstResponder(page)
            }
        }
        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.cornerRadius = Radius.card
            layer?.cornerCurve = .continuous
            layer?.masksToBounds = true
            shade.wantsLayer = true
            shade.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.32).cgColor
            shade.alphaValue = 0
            shade.autoresizingMask = [.width, .height]
        }
        required init?(coder: NSCoder) { nil }
        // AppKit views sit above SwiftUI content for events; while covered, the page must not take clicks meant for the overlay.
        override func hitTest(_ point: NSPoint) -> NSView? { covered ? nil : super.hitTest(point) }
    }
    func makeNSView(context: Context) -> Host { let host = Host(); mount(host); host.covered = covered; return host }
    func updateNSView(_ host: Host, context: Context) { mount(host); host.covered = covered }
    func mount(_ host: Host) {
        guard webView.superview !== host else { return }
        host.subviews.forEach { $0.removeFromSuperview() }
        webView.removeFromSuperview(); webView.frame = host.bounds; webView.autoresizingMask = [.width, .height]; host.addSubview(webView)
        host.shade.frame = host.bounds; host.addSubview(host.shade)
        host.focusPage()
    }
    static func dismantleNSView(_ host: Host, coordinator: ()) { host.subviews.forEach { $0.removeFromSuperview() } }
}
