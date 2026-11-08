import AppKit
import SwiftUI
import WebKit
import MicaCore
import UniformTypeIdentifiers

struct WebSurface: NSViewRepresentable {
    let webView: WKWebView
    /// True while a mica overlay (settings, command bar) covers the page.
    var covered = false
    final class Host: NSView {
        let shade = NSView()
        var covered = false {
            didSet {
                guard covered != oldValue else { return }
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = Motion.reduced ? 0 : 0.16
                    shade.animator().alphaValue = covered ? 1 : 0
                }
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
    }
    static func dismantleNSView(_ host: Host, coordinator: ()) { host.subviews.forEach { $0.removeFromSuperview() } }
}
