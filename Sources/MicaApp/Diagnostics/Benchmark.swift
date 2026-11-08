import Foundation
import AppKit
import WebKit
import MicaCore

@MainActor final class Benchmark {
    static let urls = [
        "https://www.wikipedia.org", "https://github.com/WebKit/WebKit", "https://webkit.org/blog/",
        "https://developer.apple.com/documentation/webkit", "https://www.swift.org/documentation/",
        "https://www.w3.org/TR/websockets/", "https://developer.mozilla.org/en-US/docs/Web/API/WebRTC_API",
        "https://www.youtube.com/watch?v=aqz-KE-bpKQ", "https://www.openstreetmap.org", "https://www.bbc.com/news"
    ]
    static func run(store: Store, count: Int) async {
        guard let browser = store.active else { return }
        browser.showOnboarding = false
        browser.controller?.window?.setContentSize(NSSize(width: 1180, height: 780))
        // A benchmark never silently runs installed extensions or changes the user's normal profile.
        for record in store.extensions.records where store.extensions.contexts[record.id] != nil { await store.extensions.toggle(record) }
        let helper = SmokeTest(store: store)
        let start = ProcessInfo.processInfo.systemUptime
        var pages: [[String: Any]] = []
        for (i, address) in urls.prefix(count).enumerated() {
            let tab = i == 0 ? browser.selected! : browser.add()
            let pageStart = ProcessInfo.processInfo.systemUptime
            tab.load(URL(string: address)!)
            let loaded = await helper.wait({ tab.webView?.url != nil && !tab.loading && tab.webView?.title?.isEmpty == false && tab.error == nil }, seconds: 35)
            pages.append(["url": address, "loaded": loaded, "title": tab.title, "finalURL": tab.url?.absoluteString ?? "", "error": tab.error ?? "", "seconds": ProcessInfo.processInfo.systemUptime - pageStart])
        }
        if let first = browser.tabs.first { browser.select(first) }
        var response: [Double] = []
        for _ in 0..<30 { let start = ProcessInfo.processInfo.systemUptime; browser.cycle(1); await Task.yield(); response.append((ProcessInfo.processInfo.systemUptime - start) * 1000) }
        let report: [String: Any] = ["viewportPoints": ["width": browser.controller?.window?.contentLayoutRect.width ?? 0, "height": browser.controller?.window?.contentLayoutRect.height ?? 0], "pid": ProcessInfo.processInfo.processIdentifier, "mode": "live", "requestedTabs": count, "webViews": browser.tabs.filter { $0.webView != nil }.count, "pages": pages, "preparationSeconds": ProcessInfo.processInfo.systemUptime - start, "selectionMainActorMilliseconds": response, "selectionLimit": "Measures model dispatch plus one executor yield, not input-to-photon latency.", "extensions": "disabled", "blocking": store.preferences.blocking, "generated": ISO8601DateFormatter().string(from: Date())]
        do { try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: store.root.appendingPathComponent("benchmark-\(count).json"), options: .atomic) } catch { store.issue = error.localizedDescription }
        browser.controller?.window?.miniaturize(nil)
        if let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--benchmark-duration=") }), let duration = Double(argument.dropFirst("--benchmark-duration=".count)), duration >= 5, duration <= 7200 {
            try? await Task.sleep(for: .seconds(duration))
            NSApp.terminate(nil)
        }
    }
}
