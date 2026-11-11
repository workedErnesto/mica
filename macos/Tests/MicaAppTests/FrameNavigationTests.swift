import WebKit
import XCTest
import MicaCore

@MainActor final class FrameNavigationTests: XCTestCase {
    private final class Policy: NSObject, WKNavigationDelegate {
        var inlineFrame = false
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { decisionHandler(.cancel); return }
            let main = action.targetFrame?.isMainFrame != false
            if url.absoluteString == "about:srcdoc", !main { inlineFrame = true }
            decisionHandler(AddressParser.navigable(url, mainFrame: main) ? .allow : .cancel)
        }
    }
    func testWebKitLoadsSrcdocChildThroughNavigationPolicy() async {
        let configuration = WKWebViewConfiguration(); configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        let policy = Policy(); view.navigationDelegate = policy
        view.loadHTMLString("<iframe srcdoc='<span id=ready>loaded</span>'></iframe>", baseURL: URL(string: "https://frame.example/"))
        let deadline = Date().addingTimeInterval(8)
        var ready = false
        while Date() < deadline {
            ready = (try? await view.callAsyncJavaScript("return !!document.querySelector('iframe')?.contentDocument?.getElementById('ready')", contentWorld: .defaultClient)) as? Bool == true
            if ready { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(policy.inlineFrame, "WebKit must report the actual srcdoc navigation")
        XCTAssertTrue(ready, "The child document must load, not remain an empty frame")
        view.stopLoading(); view.navigationDelegate = nil
    }
}
