import AppKit
import SwiftUI
import WebKit
import Combine
import CryptoKit
import MicaCore

@MainActor
func ask(title: String, detail: String, buttons: [String], window: NSWindow? = nil) async -> Int {
    let window = window ?? NSApp.keyWindow
    let alert = NSAlert(); alert.messageText = title
    // NSAlert draws the bundle icon; the icon chosen in settings is the one in the Dock.
    alert.icon = NSApp.applicationIconImage
    if detail.count > 1600 {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 440, height: 240))
        scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        let text = NSTextView(frame: scroll.bounds)
        text.string = detail; text.font = .systemFont(ofSize: 12); text.isEditable = false; text.isSelectable = true; text.drawsBackground = false
        text.isVerticallyResizable = true; text.isHorizontallyResizable = false
        text.textContainer?.widthTracksTextView = true
        text.textContainer?.containerSize = NSSize(width: 440, height: CGFloat.greatestFiniteMagnitude)
        text.maxSize = NSSize(width: 440, height: CGFloat.greatestFiniteMagnitude)
        scroll.documentView = text; alert.accessoryView = scroll
    } else { alert.informativeText = detail }
    for button in buttons { alert.addButton(withTitle: button) }
    if let window, window.attachedSheet == nil {
        return await withCheckedContinuation { continuation in alert.beginSheetModal(for: window) { continuation.resume(returning: $0.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue) } }
    }
    return alert.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
}
