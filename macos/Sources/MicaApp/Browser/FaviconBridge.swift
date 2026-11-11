import WebKit

/// Some apps add or replace their icon after didFinish. Observe the head, with no polling or page-world overrides.
@MainActor final class FaviconBridge: NSObject, WKScriptMessageHandler {
    private weak var tab: Tab?
    private static let name = "micaFavicon"
    private static let world = WKContentWorld.world(name: "mica.favicons")
    init(tab: Tab, controller: WKUserContentController) {
        self.tab = tab
        super.init()
        controller.add(self, contentWorld: Self.world, name: Self.name)
        controller.addUserScript(WKUserScript(source: Self.script, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: Self.world))
    }
    func detach(from controller: WKUserContentController) {
        controller.removeScriptMessageHandler(forName: Self.name, contentWorld: Self.world)
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let tab, tab.webView === message.webView else { return }
        tab.refreshFavicon()
    }
    private static let script = #"""
    (() => {
      if (!document.head) return;
      const signature = () => Array.from(document.head.querySelectorAll('link[rel][href]'))
        .filter(link => /(?:^|\s)(?:icon|apple-touch-icon|apple-touch-icon-precomposed)(?:\s|$)/i.test(link.rel))
        .slice(0, 24).map(link => [link.href, link.sizes.value, link.type, link.media]);
      let previous = JSON.stringify(signature()), timer;
      new MutationObserver(() => {
        const next = JSON.stringify(signature());
        if (next === previous) return;
        previous = next; clearTimeout(timer);
        timer = setTimeout(() => window.webkit.messageHandlers.micaFavicon.postMessage(null), 150);
      }).observe(document.head, {subtree:true, childList:true, attributes:true, attributeFilter:['href','rel','sizes','type','media']});
    })();
    """#
}
