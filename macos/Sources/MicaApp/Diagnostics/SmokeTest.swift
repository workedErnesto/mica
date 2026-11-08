import AppKit
import WebKit
import MicaCore

/// Runs only when explicitly requested. No diagnostic timer or JS is installed in normal browsing.
@MainActor final class SmokeTest {
    let store: Store
    var results: [[String: Any]] = []
    init(store: Store) { self.store = store }
    func check(_ name: String, _ passed: Bool, _ detail: String = "") {
        results.append(["name": name, "passed": passed, "detail": detail])
        let checkpoint: [String: Any] = ["status": "running", "generated": ISO8601DateFormatter().string(from: Date()), "tests": results, "failed": results.filter { $0["passed"] as? Bool == false }.count]
        try? JSONSerialization.data(withJSONObject: checkpoint, options: [.prettyPrinted, .sortedKeys]).write(to: store.root.appendingPathComponent("smoke-report.json"), options: .atomic)
    }
    func skip(_ name: String, _ detail: String) { results.append(["name": name, "passed": true, "skipped": true, "detail": detail]) }
    func wait(_ test: () -> Bool, seconds: Double = 15) async -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + seconds
        while ProcessInfo.processInfo.systemUptime < deadline {
            if test() { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return false
    }
    func js(_ tab: Tab, _ expression: String) async -> Any? { try? await tab.webView?.callAsyncJavaScript("return await eval(code)", arguments: ["code": expression], in: nil, contentWorld: .page) }
    func fixture(_ tab: Tab, number: Int = 0) async {
        tab.makeWebView(); tab.phase = .live
        tab.webView?.loadHTMLString("""
        <!doctype html><meta charset="utf-8"><title>mica QA \(number)</title>
        <style>body{font:16px -apple-system,sans-serif;margin:48px;color:#292524;background:#f5f5f5}input,button{font:inherit;padding:8px}pre{white-space:pre-wrap}</style>
        <h1>mica QA \(number)</h1><p>Controlled in-memory document, no external requests.</p>
        <label>Unsaved text <input id="draft" value=""></label><p id="alive">live</p>
        <a id="popup" href="https://webkit.org" target="_blank">new tab</a>
        <button id="file" onclick="document.querySelector('#upload').click()">choose file</button><input id="upload" type="file" multiple>
        <a id="download" download="mica-QA.txt">download fixture</a>
        <button onclick="let c=new AudioContext();let o=c.createOscillator();o.connect(c.destination);o.start();o.stop(c.currentTime+0.3)">play short tone</button>
        <button onclick="capture({video:true})">test camera locally</button><button onclick="capture({audio:true})">test microphone locally</button><button onclick="if(window.captureStream)captureStream.getTracks().forEach(t=>t.stop());document.querySelector('#status').textContent='stopped'">stop capture</button>
        <pre id="status"></pre><script>
        async function capture(constraints){try{window.captureStream=await navigator.mediaDevices.getUserMedia(constraints);document.querySelector('#status').textContent='active '+captureStream.getTracks().map(t=>t.kind+':'+t.readyState).join(', ')}catch(error){document.querySelector('#status').textContent=error.name}}
        
        window.initialPermission=window.Notification?Notification.permission:'missing';
        window.identity=crypto.randomUUID();window.memory=new Uint8Array(1024*1024);window.memory.fill(\(number));
        document.querySelector('#download').href=URL.createObjectURL(new Blob(['mica download fixture\\n'],{type:'text/plain'}));
        </script>
        """, baseURL: URL(string: "https://mica.invalid/qa/\(number)"))
        _ = await wait({ tab.webView?.title == "mica QA \(number)" && !tab.loading })
    }
    func waitForJS(_ tab: Tab, _ expression: String, seconds: Double = 6) async -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + seconds
        while ProcessInfo.processInfo.systemUptime < deadline {
            if await js(tab, expression) as? Bool == true { return true }
            try? await Task.sleep(for: .milliseconds(150))
        }
        return false
    }
    func notificationChecks(_ browser: BrowserModel, _ tab: Tab) async {
        let origin = "https://mica.invalid"
        store.setPermission(origin: origin, capability: .notifications, decision: .ask)
        check("notification API present in page world", await js(tab, "typeof Notification === 'function' && typeof Notification.requestPermission === 'function'") as? Bool == true)
        check("notification permission default without decision", await waitForJS(tab, "Notification.permission === 'default'"))
        let unasked = await js(tab, "Notification.requestPermission()") as? String
        check("request without gesture shows no question", unasked == "default", unasked ?? "nil")
        store.setPermission(origin: origin, capability: .notifications, decision: .allow)
        check("decision pushed to open page", await waitForJS(tab, "Notification.permission === 'granted'"))
        check("permissions.query reflects decision", await waitForJS(tab, "navigator.permissions.query({name:'notifications'}).then(s => s.state === 'granted')"))
        let fresh = browser.add()
        await fixture(fresh, number: 60)
        check("new page starts with saved decision", await js(fresh, "initialPermission") as? String == "granted")
        browser.close(fresh)
        let privateWindow = store.newWindow(privateMode: true)
        if let privateTab = privateWindow.selected {
            await fixture(privateTab, number: 61)
            check("incognito refuses notifications", await js(privateTab, "Notification.permission") as? String == "denied")
        }
        privateWindow.controller?.window?.close()
        let status = await store.notifier.status()
        if status == .authorized || status == .provisional {
            check("notification delivered by macOS", await js(tab, "new Promise(r => { const n = new Notification('mica QA', {body: 'smoke test', tag: 'qa'}); n.onshow = () => { n.close(); r(true) }; n.onerror = () => r(false) })") as? Bool == true)
        } else { skip("notification delivered by macOS", "system authorization status \(status.rawValue), mica has not been allowed yet") }
        store.setPermission(origin: origin, capability: .notifications, decision: .deny)
        let deniedState = await waitForJS(tab, "Notification.permission === 'denied'")
        let refused = await js(tab, "new Promise(r => { const n = new Notification('x'); n.onerror = () => r(true); n.onshow = () => r(false) })") as? Bool == true
        check("denied decision refuses construction", deniedState && refused)
        store.setPermission(origin: origin, capability: .notifications, decision: .ask)
    }
    func run() async {
        guard let browser = store.active else { return }
        browser.showOnboarding = false
        let start = ProcessInfo.processInfo.systemUptime
        let tab = browser.selected!
        check("media permission delegate connected", tab.responds(to: NSSelectorFromString("webView:requestMediaCapturePermissionForOrigin:initiatedByFrame:type:decisionHandler:")))
        await fixture(tab)
        let identity = await js(tab, "identity") as? String
        _ = await js(tab, "document.querySelector('#draft').value='Apple GitHub ООО ДПС'; true")
        for index in 1...9 { let next = browser.add(); await fixture(next, number: index) }
        let views = browser.tabs.compactMap(\.webView)
        check("ten genuinely live tabs", views.count == 10 && Set(views.map(ObjectIdentifier.init)).count == 10 && browser.tabs.allSatisfy { $0.phase == .live })
        browser.select(tab)
        check("switch preserves JS identity", await js(tab, "identity") as? String == identity)
        check("switch preserves unsaved form", await js(tab, "document.querySelector('#draft').value") as? String == "Apple GitHub ООО ДПС")
        let order = browser.tabs.map(\.id)
        if let last = browser.tabs.last { browser.move(last.id, before: tab.id) }
        check("drag reorder model", browser.tabs.first?.id == order.last)
        browser.pin(tab); check("pin places tab in pinned group", browser.tabs.first?.id == tab.id && tab.pinned)
        let before = browser.tabs.count
        if let last = browser.tabs.last { browser.close(last); browser.reopen() }
        check("close and reopen", browser.tabs.count == before && browser.closed.isEmpty)
        let privateWindow = store.newWindow(privateMode: true)
        check("private nonpersistent data store", !privateWindow.dataStore.isPersistent && privateWindow.dataStore !== browser.dataStore)
        privateWindow.selected?.makeWebView()
        check("private extensions disabled", privateWindow.selected?.webView?.configuration.webExtensionController == nil)
        let historyCount = store.history.count
        privateWindow.selected?.makeWebView()
        privateWindow.selected?.url = URL(string: "https://private.invalid")
        store.record(privateWindow.selected!)
        check("private navigation excluded from history", store.history.count == historyCount)
        privateWindow.controller?.window?.close()
        check("private objects disposed on close", privateWindow.tabs.isEmpty && privateWindow.transientPermissions.isEmpty)
        await notificationChecks(browser, tab)
        let saved = browser.snapshot
        let restored = store.newWindow(saved: saved)
        check("lazy restore loads selected only", restored.tabs.filter { $0.webView != nil }.count == 1)
        check("restored state distinct", restored.tabs.contains { $0.phase == .restored })
        restored.controller?.window?.close()
        // Compile AND execute a real content rule. This check is independent of external network availability.
        do {
            let rule = try await WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "mica-qa-execution", encodedContentRuleList: "[{\"trigger\":{\"url-filter\":\".*\"},\"action\":{\"type\":\"css-display-none\",\"selector\":\"#alive\"}}]")
            let testTab = browser.add()
            testTab.makeWebView(); testTab.webView?.configuration.userContentController.add(rule!)
            await fixture(testTab, number: 50)
            check("WebKit content rule execution", await js(testTab, "getComputedStyle(document.querySelector('#alive')).display") as? String == "none")
            browser.close(testTab)
        } catch { check("WebKit content rule execution", false, error.localizedDescription) }
        // Actual built-in network rule A/B. Script is never executed: fetch response bytes only.
        let networkTab = browser.add(saved: SavedTab(url: URL(string: "https://webkit.org")))
        let online = await wait({ !networkTab.loading && networkTab.webView?.title?.isEmpty == false && networkTab.error == nil }, seconds: 25)
        check("real HTTPS navigation", online, networkTab.error ?? networkTab.webView?.title ?? "")
        if online {
            let request = "fetch('https://www.google-analytics.com/analytics.js',{mode:'no-cors',cache:'no-store'}).then(()=>true).catch(()=>false)"
            let blocked = await js(networkTab, request) as? Bool
            networkTab.webView?.configuration.userContentController.removeAllContentRuleLists()
            let allowed = await js(networkTab, request) as? Bool
            store.blocker.apply(networkTab.webView)
            check("built-in network blocker A/B", blocked == false && allowed == true, "blocked=\(String(describing: blocked)), unblocked=\(String(describing: allowed))")
        }
        browser.close(networkTab)
        let badCertificate = URL(string: "https://self-signed.badssl.com/")!
        let rejected = browser.add(saved: SavedTab(url: badCertificate))
        _ = await wait({ rejected.navigationFailure != nil || (!rejected.loading && rejected.webView?.title?.isEmpty == false) }, seconds: 15)
        let tlsFailure = rejected.navigationFailure
        check("TLS rejects untrusted certificate", tlsFailure?.domain == NSURLErrorDomain && [-1200, -1202, -1203, -1204].contains(tlsFailure?.code ?? 0), tlsFailure?.localizedDescription ?? "no failure")
        check("failed navigation preserves address", rejected.url == badCertificate)
        rejected.reload()
        _ = await wait({ rejected.navigationFailure != nil }, seconds: 15)
        check("retry remains secure and retains address", rejected.url == badCertificate && rejected.navigationFailure != nil && !rejected.secure)
        browser.close(rejected)
        if store.extensions.records.contains(where: { $0.name == "Dark Reader" && store.extensions.contexts[$0.id] != nil }) {
            let themed = browser.add(saved: SavedTab(url: URL(string: "https://webrtc.github.io/samples/src/content/getusermedia/gum/")))
            _ = await wait({ !themed.loading && themed.webView?.title?.isEmpty == false }, seconds: 25)
            let applied = await waitForJS(themed, "!!document.querySelector('style.darkreader') || document.documentElement.hasAttribute('data-darkreader-mode')")
            check("Dark Reader actual DOM theme injection", applied, "version " + (store.extensions.records.first { $0.name == "Dark Reader" }?.version ?? "?"))
            browser.close(themed)
        }
        if let fixture = Bundle.main.resourceURL?.appendingPathComponent("QA/extension-check"), FileManager.default.fileExists(atPath: fixture.path) {
            do {
                let copied = store.root.appendingPathComponent("FixtureExtension", isDirectory: true)
                try? FileManager.default.removeItem(at: copied)
                try FileManager.default.copyItem(at: fixture, to: copied)
                defer { try? FileManager.default.removeItem(at: copied) }
                let ext = try await WKWebExtension(resourceBaseURL: copied)
                let context = WKWebExtensionContext(for: ext)
                context.uniqueIdentifier = "mica-integration-check"
                for permission in ext.requestedPermissions { context.setPermissionStatus(.grantedExplicitly, for: permission) }
                for pattern in ext.requestedPermissionMatchPatterns { context.setPermissionStatus(.grantedExplicitly, for: pattern) }
                try store.extensions.controller.load(context)
                let page = browser.add(saved: SavedTab(url: URL(string: "https://webkit.org")))
                let injected = await waitForJS(page, "document.documentElement.dataset.micaExtension === 'active'", seconds: 20)
                let responded = await waitForJS(page, "document.documentElement.dataset.micaExtensionReply === 'ok'")
                let reply = await js(page, "document.documentElement.dataset.micaExtensionReply || ''") as? String ?? ""
                check("WebExtension content script", injected, context.errors.map(\.localizedDescription).joined(separator: "; "))
                check("WebExtension runtime messaging and storage", responded, reply)
                browser.close(page)
                try store.extensions.controller.unload(context)
                check("WebExtension unload", !context.isLoaded)
            } catch { check("WebExtension fixture", false, error.localizedDescription) }
        }
        let temporary = browser.add(activate: false)
        temporary.makeWebView()
        weak var releasedView = temporary.webView
        browser.close(temporary)
        _ = await wait({ releasedView == nil }, seconds: 3)
        check("closed WebView released", releasedView == nil)
        browser.select(tab)
        let report: [String: Any] = ["generated": ISO8601DateFormatter().string(from: Date()), "durationSeconds": ProcessInfo.processInfo.systemUptime - start, "tests": results, "failed": results.filter { ($0["passed"] as? Bool) == false }.count, "limits": "Fixture tests exercise live WKWebViews; permission grants, download panels and popular extension behavior require separate tests."]
        do { let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]); try data.write(to: store.root.appendingPathComponent("smoke-report.json"), options: .atomic) } catch { store.issue = error.localizedDescription }
        if ProcessInfo.processInfo.arguments.contains("--exit-after-smoke") { NSApp.terminate(nil); return }
        browser.message = "QA: \(results.filter { $0["passed"] as? Bool == true }.count) / \(results.count)" + "\n" + store.root.appendingPathComponent("smoke-report.json").path
    }
}
