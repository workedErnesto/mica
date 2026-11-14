import AppKit
import WebKit

/// The web view of a tab. Its context menu is a mica menu (PageMenu) made from WebKit's items.
///
/// WebKit's own "download image", "download linked file" and "download video" items hand their download only to a
/// private delegate method, so in an app they silently did nothing. mica points those items at its own action
/// instead: a script in an isolated world notes what the context click was on, and the item starts an ordinary
/// WKWebView download of that address, which then goes through the save panel and the downloads list like any other.
@MainActor
final class PageView: WKWebView {
    weak var tab: Tab?
    /// What the latest context click in this view was on, from ContextTargets.
    var target = ContextTarget()

    /// True while a mica overlay (a question, settings, the command bar) covers the page. Clicks already miss the
    /// page then (WebSurface.Host.hitTest), but WebKit follows the pointer through tracking areas owned by its own
    /// WKMouseTrackingObserver, which ignore the views above the page and bypass this view's mouse methods: the page
    /// kept setting its cursor, an I-beam over text, under the card's switch and buttons. While covered those areas
    /// are taken off and the cursor is the arrow; they come back unchanged when the overlay closes.
    var covered = false {
        didSet {
            guard covered != oldValue else { return }
            if covered {
                parkedAreas = trackingAreas
                parkedAreas.forEach(removeTrackingArea)
                if let window, window.isKeyWindow, bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil)) { NSCursor.arrow.set() }
            } else {
                let present = trackingAreas
                parkedAreas.filter { area in !present.contains { $0 === area } }.forEach(addTrackingArea)
                parkedAreas = []
            }
        }
    }
    private var parkedAreas: [NSTrackingArea] = []
    /// WebKit may install its areas again (a resize, a window change) while the page is covered.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        guard covered else { return }
        for area in trackingAreas {
            if !parkedAreas.contains(where: { $0 === area }) { parkedAreas.append(area) }
            removeTrackingArea(area)
        }
    }

    /// WebKit's identifiers for the three download items; the raw values are stable strings, the constants are not public on macOS.
    enum DownloadItem: String {
        case image = "WKMenuItemIdentifierDownloadImage"
        case link = "WKMenuItemIdentifierDownloadLinkedFile"
        case media = "WKMenuItemIdentifierDownloadMedia"
    }

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        for item in menu.items {
            guard let kind = item.identifier.flatMap({ DownloadItem(rawValue: $0.rawValue) }) else { continue }
            item.target = self
            item.action = #selector(downloadContextTarget(_:))
            item.representedObject = kind.rawValue
        }
        // WebKit's menu opens empty and so not at all; the items go to a mica menu at the same point. The context
        // script's message about this click comes in before the menu, so the menu below sees the current target.
        let items = menu.items
        menu.removeAllItems()
        let point = NSEvent.mouseLocation
        DispatchQueue.main.async { [weak self] in
            guard let self, let tab = self.tab, let browser = tab.owner else { return }
            MicaMenu.shared.show(PageMenu.entries(from: items, page: self, tab: tab, browser: browser), at: point, in: self.window)
        }
    }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(downloadContextTarget(_:)) { return true }
        return super.validateUserInterfaceItem(item)
    }

    @objc private func downloadContextTarget(_ sender: NSMenuItem) {
        guard let kind = (sender.representedObject as? String).flatMap(DownloadItem.init(rawValue:)),
              let address = target.url(for: kind), let tab else { NSSound.beep(); return }
        var request = URLRequest(url: address)
        // Image hosts often check the referrer. An HTTPS page never sends its address to a plain HTTP server.
        if let page = url, let scheme = page.scheme?.lowercased(), ["http", "https"].contains(scheme),
           !(scheme == "https" && address.scheme?.lowercased() == "http") {
            request.setValue(page.absoluteString, forHTTPHeaderField: "Referer")
        }
        startDownload(using: request) { [weak tab] download in
            guard let tab else { download.cancel(nil); return }
            tab.owner?.downloads.add(download, tab: tab)
        }
    }
}

/// The image, link and media element under the latest context click, as absolute addresses, and the selected text.
struct ContextTarget {
    var image: URL?
    var link: URL?
    var media: URL?
    var selection: String?
    func url(for kind: PageView.DownloadItem) -> URL? {
        switch kind {
        case .image: image
        case .link: link
        case .media: media
        }
    }
}

/// Receives context click targets from every frame. One handler serves a whole WKUserContentController, which popups
/// share with the tab that opened them, so a message is routed by the web view that sent it.
@MainActor
final class ContextTargets: NSObject, WKScriptMessageHandler {
    static let shared = ContextTargets()
    static let world = WKContentWorld.world(name: "mica.context")
    static let name = "micaContext"

    func install(in controller: WKUserContentController) {
        controller.add(self, contentWorld: Self.world, name: Self.name)
        controller.addUserScript(WKUserScript(source: Self.script, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: Self.world))
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let view = message.webView as? PageView, let body = message.body as? [String: Any] else { return }
        func address(_ key: String) -> URL? {
            guard let text = body[key] as? String, !text.isEmpty, text.count < 100_000, let url = URL(string: text),
                  let scheme = url.scheme?.lowercased(), ["http", "https", "data", "blob"].contains(scheme) else { return nil }
            return url
        }
        let selection = (body["selection"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        view.target = ContextTarget(image: address("image"), link: address("link"), media: address("media"),
                                    selection: selection.flatMap { $0.isEmpty ? nil : String($0.prefix(2_000)) })
    }

    /// Capture phase, so a page that stops the event still reports it; nothing is changed or prevented.
    static let script = """
    addEventListener('contextmenu', (event) => {
      const path = typeof event.composedPath === 'function' ? event.composedPath() : [event.target];
      const absolute = (value) => { try { return value ? new URL(value, document.baseURI).href : ''; } catch { return ''; } };
      let image = '', link = '', media = '';
      for (const node of path) {
        if (!(node instanceof Element)) continue;
        const tag = node.localName;
        if (!image && tag === 'img') image = node.currentSrc || node.src || '';
        if (!image && tag === 'image') image = absolute(node.getAttribute('href') || node.getAttribute('xlink:href'));
        if (!media && (tag === 'video' || tag === 'audio')) media = node.currentSrc || node.src || '';
        if (!link && (tag === 'a' || tag === 'area')) link = absolute(node.getAttribute('href') || node.getAttribute('xlink:href'));
      }
      const selection = String(getSelection() || '').slice(0, 2000);
      window.webkit.messageHandlers.micaContext.postMessage({ image, link, media, selection });
    }, true);
    """
}
