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
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) { if event.clickCount == 2 { window?.performZoom(nil) } else { window?.performDrag(with: event) } }
    }
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) {}
}

/// Shell fill: the tint over the blurred desktop, or the plain tint when glass is off or the system asks for opacity.
struct ShellBackground: View {
    @ObservedObject var store: Store
    let glass: Bool
    @Environment(\.look) private var look
    var body: some View {
        if glass { Frost().overlay(look.shell.opacity(store.glassTint)) }
        else { look.shell }
    }
}
