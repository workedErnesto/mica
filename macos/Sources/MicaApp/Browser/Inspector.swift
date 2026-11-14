import AppKit
import WebKit

/// WebKit's Web Inspector inside the mica window, as in Safari and Orion: "Inspect Element" in the page context menu,
/// plus the developer tools and JavaScript console commands, docked beside the page in its card.
///
/// macOS has no public API for this: `isInspectable` only lets Safari's Develop menu attach from outside. So mica uses
/// two WebKit SPI names, the `developerExtrasEnabled` preference and the web view's `_inspector` object, and checks
/// both before use. If a macOS release drops them, the commands only beep and `isInspectable` is turned on so Safari's
/// Develop menu still reaches the page.
@MainActor
enum Inspector {
    static let available = WKPreferences.instancesRespond(to: NSSelectorFromString("_setDeveloperExtrasEnabled:"))
        && WKWebView.instancesRespond(to: NSSelectorFromString("_inspector"))

    /// Adds "Inspect Element" to the page context menu of web views made with this configuration.
    static func enable(_ configuration: WKWebViewConfiguration) {
        guard available else { return }
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
    }

    /// Opens the inspector beside the page, or closes it when it is already open.
    static func toggle(_ view: WKWebView) {
        guard let inspector = inspector(of: view) else { NSSound.beep(); return }
        if visible(inspector) { call(inspector, "close") } else { call(inspector, "show") }
    }

    /// Opens the inspector on its console.
    static func console(_ view: WKWebView) {
        guard let inspector = inspector(of: view) else { NSSound.beep(); return }
        call(inspector, "showConsole")
    }

    /// Closes the inspector of a web view that is going away.
    static func close(_ view: WKWebView) {
        guard let inspector = inspector(of: view), visible(inspector) else { return }
        call(inspector, "close")
    }

    private static func inspector(of view: WKWebView) -> NSObject? {
        guard available else { return nil }
        return view.perform(NSSelectorFromString("_inspector"))?.takeUnretainedValue() as? NSObject
    }

    private static func visible(_ inspector: NSObject) -> Bool {
        guard inspector.responds(to: NSSelectorFromString("isVisible")) else { return false }
        return (inspector.value(forKey: "isVisible") as? Bool) ?? false
    }

    private static func call(_ inspector: NSObject, _ name: String) {
        let selector = NSSelectorFromString(name)
        if inspector.responds(to: selector) { inspector.perform(selector) } else { NSSound.beep() }
    }
}
