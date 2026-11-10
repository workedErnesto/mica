import AppKit
import SwiftUI
import WebKit
import MicaCore
import UniformTypeIdentifiers

/// Behind-window blur for the shell only. It stays active in background windows so the material does not flip
/// to an opaque fill whenever another app takes focus; pages are never blurred.
struct Frost: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView(); view.material = .underWindowBackground; view.blendingMode = .behindWindow; view.state = .active; return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// Empty chrome areas move the window like a title bar; double click zooms.
/// `titleBand`: the area lies in the title bar band of a window made immovable so SwiftUI tabs there get their clicks
/// (tabs above the address). AppKit hands such a view the mouse down only when it cannot move the window itself,
/// and the window is movable again just for the drag it starts.
struct WindowDragArea: NSViewRepresentable {
    var titleBand = false
    final class DragView: NSView {
        var titleBand = false
        override var mouseDownCanMoveWindow: Bool { !titleBand }
        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            if event.clickCount == 2 { window.performZoom(nil); return }
            if titleBand && !window.isMovable {
                window.isMovable = true
                window.performDrag(with: event)
                // The drag runs in the window server and may not send a mouse up; wait for the button to come up.
                Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak window] timer in
                    guard NSEvent.pressedMouseButtons & 1 == 0 else { return }
                    timer.invalidate()
                    MainActor.assumeIsolated { window?.isMovable = false }
                }
            } else { window.performDrag(with: event) }
        }
    }
    func makeNSView(context: Context) -> DragView { let view = DragView(); view.titleBand = titleBand; return view }
    func updateNSView(_ view: DragView, context: Context) { view.titleBand = titleBand }
}

/// Shell fill: the tint over the blurred desktop, or the plain tint when glass is off or the system asks for opacity.
struct ShellBackground: View {
    @ObservedObject var store: Store
    @ObservedObject var browser: BrowserModel
    let glass: Bool
    @Environment(\.look) private var look
    var body: some View {
        if glass { Frost().overlay(look.shell.opacity(Store.glassTint(browser.prefs))) }
        else { look.shell }
    }
}
