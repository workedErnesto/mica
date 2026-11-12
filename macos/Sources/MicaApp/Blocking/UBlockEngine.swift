import AppKit
import WebKit
import CryptoKit
import MicaCore

/// uBlock Origin in mica. WebKit gives extensions no way to block requests (`webRequestBlocking`), so mica does not run
/// uBO's code as an extension. It runs uBO's own list compiler over uBO's lists in a hidden page and applies the result
/// with public WebKit: two content rule lists (requests and element hiding) and uBO's scriptlets, injected at document
/// start into the page world and an isolated world of every frame. The scriptlets are what removes YouTube's ads.
/// Lists come from the bundled package first and are refreshed from uBO's own sources once a day. The same rules
/// apply in private windows: they only remove content and send nothing anywhere.
@MainActor
final class UBlockEngine: ObservableObject {
    nonisolated static let geckoID = "uBlock0@raymondhill.net"
    /// First line of both bundles, so a tab can tell them from its other user scripts.
    nonisolated static let marker = "/* mica: uBlock Origin scriptlets */\n"
    static func owns(_ script: WKUserScript) -> Bool { script.source.hasPrefix(marker) }
    static let world = WKContentWorld.world(name: "mica-ublock")
    struct Stats: Codable, Equatable { var network: Int; var cosmetic: Int; var scriptlets: Int }
    private struct Build: Codable { var fingerprint: String; var stats: Stats; var compiled: Date; var listsUpdated: Date? }
    /// One list of uBO's defaults: where its copy in the package is and where uBO refreshes it from.
    struct FilterList { let key: String; let local: String?; let remote: [URL]; let trusted: Bool }

    unowned let store: Store
    @Published private(set) var package: URL?
    @Published private(set) var stats: Stats?
    @Published private(set) var compiling = false
    @Published private(set) var updating = false
    @Published private(set) var listsUpdated: Date?
    @Published var status = ""
    private(set) var network: WKContentRuleList?
    private(set) var cosmetic: WKContentRuleList?
    private(set) var mainScript = ""
    private(set) var isolatedScript = ""
    /// The two bundles as user scripts, made once per build and shared by all tabs.
    private var scripts: [WKUserScript] = []
    private var generation = 0
    private var compiler: WKWebView?
    private var handler: UBlockSchemeHandler?
    private var dailyUpdate: Task<Void, Never>?
    private(set) var prepared = false
    var active: Bool { package != nil && store.preferences.blocking }
    var folder: URL { store.root.appendingPathComponent("UBlock", isDirectory: true) }
    private var listFolder: URL { folder.appendingPathComponent("lists", isDirectory: true) }
    init(store: Store) { self.store = store }

    /// True when the package is uBlock Origin: its Gecko ID in the manifest, as AMO publishes it.
    nonisolated static func isUBlock(manifest: [String: Any]) -> Bool {
        let settings = (manifest["browser_specific_settings"] ?? manifest["applications"]) as? [String: Any]
        return (settings?["gecko"] as? [String: Any])?["id"] as? String == geckoID
    }

    // MARK: Lifecycle

    /// Built-in components are pinned with the application, independent of installed extensions.
    func startBuiltin() async {
        defer { prepared = true }
        guard store.preferences.blocking else { stop(); return }
        guard let package = Bundle.main.resourceURL?.appendingPathComponent("Blocking/ublock"),
              FileManager.default.fileExists(atPath: package.appendingPathComponent("assets/assets.json").path) else {
            status = store.text("встроенные фильтры недоступны", "Встроенные фильтры недоступны")
            return
        }
        await start(package: package)
    }

    /// Components are ready: use the last build when it still matches, otherwise compile.
    func start(package: URL) async {
        self.package = package
        status = store.text("подготовка фильтров…", "Подготовка фильтров…")
        await rebuild()
        if self.package == package, active { scheduleUpdates() }
    }
    func stop() {
        generation += 1
        package = nil; stats = nil; network = nil; cosmetic = nil; mainScript = ""; isolatedScript = ""; scripts = []
        compiler = nil; handler = nil; compiling = false
        dailyUpdate?.cancel(); dailyUpdate = nil
        status = ""
        refreshTabs()
    }
    /// Remove cached lists and builds.
    func forget() {
        stop()
        try? FileManager.default.removeItem(at: folder)
        Task { for id in ["ublock-network", "ublock-cosmetic"] { try? await store.blocker.ruleStore.removeContentRuleList(forIdentifier: id) } }
    }
    private func scheduleUpdates() {
        dailyUpdate?.cancel()
        dailyUpdate = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.active else { return }
                if (self.listsUpdated ?? .distantPast).timeIntervalSinceNow < -86_400 { await self.updateLists() }
                try? await Task.sleep(nanoseconds: 3_600_000_000_000)
            }
        }
    }

    // MARK: Lists

    /// uBO's default filter lists from its `assets.json`. The malware hosts list (urlhaus) is left out: its 200 000
    /// host rules would more than double the content rule list for no effect on ads.
    func defaultLists(_ package: URL) -> [FilterList] {
        guard let data = try? Data(contentsOf: package.appendingPathComponent("assets/assets.json")),
              let assets = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else { return [] }
        return assets.keys.sorted().compactMap { key in
            let entry = assets[key]!
            guard entry["content"] as? String == "filters", entry["off"] as? Bool != true, !key.hasPrefix("urlhaus") else { return nil }
            let content = (entry["contentURL"] as? [String]) ?? (entry["contentURL"] as? String).map { [$0] } ?? []
            let cdn = (entry["cdnURLs"] as? [String]) ?? []
            let local = content.first { !$0.hasPrefix("http") && FileManager.default.fileExists(atPath: package.appendingPathComponent($0).path) }
                ?? (content.first { !$0.hasPrefix("http") }.map { $0.hasSuffix(".txt") ? String($0.dropLast(4)) : $0 }.flatMap { FileManager.default.fileExists(atPath: package.appendingPathComponent($0).path) ? $0 : nil })
            let remote = (cdn + content).compactMap(URL.init(string:)).filter { $0.scheme == "https" }
            return FilterList(key: key, local: local, remote: remote, trusted: key.hasPrefix("ublock-"))
        }
    }
    /// The freshest copy of a list: downloaded, else the package's.
    func source(of list: FilterList, in package: URL) -> URL? {
        let cached = listFolder.appendingPathComponent(list.key + ".txt")
        if FileManager.default.fileExists(atPath: cached.path) { return cached }
        return list.local.map { package.appendingPathComponent($0) }
    }
    /// Downloads every default list from uBO's sources (its CDN first), without cookies, and rebuilds when any changed.
    /// A list that fails keeps its previous copy.
    func updateLists() async {
        guard let package, !updating else { return }
        updating = true; defer { updating = false }
        status = store.text("обновление списков uBlock Origin…", "Обновление списков uBlock Origin…")
        try? FileManager.default.createDirectory(at: listFolder, withIntermediateDirectories: true)
        let configuration = URLSessionConfiguration.ephemeral; configuration.timeoutIntervalForRequest = 30; configuration.httpCookieStorage = nil
        let session = URLSession(configuration: configuration); defer { session.invalidateAndCancel() }
        var changed = 0, failed: [String] = []
        for list in defaultLists(package) {
            var done = false
            for url in list.remote where !done {
                guard let (data, response) = try? await session.data(from: url), let http = response as? HTTPURLResponse, http.statusCode == 200,
                      http.url?.scheme == "https", data.count > 500, data.count < 30_000_000, data.first != UInt8(ascii: "<") else { continue }
                let target = listFolder.appendingPathComponent(list.key + ".txt")
                if (try? Data(contentsOf: target)) != data { try? data.write(to: target, options: .atomic); changed += 1 }
                done = true
            }
            if !done { failed.append(list.key) }
        }
        if failed.count < defaultLists(package).count { listsUpdated = Date() }
        guard self.package == package, active else { return }
        if changed > 0 { await rebuild() } else { saveBuildDate() }
        status = failed.isEmpty ? summary : store.text("не обновлены: ", "Не обновлены: ") + failed.joined(separator: ", ")
    }

    // MARK: Build

    private var buildFile: URL { folder.appendingPathComponent("build.json") }
    private func fingerprint(_ package: URL, lists: [FilterList]) -> String {
        var hash = SHA256()
        hash.update(data: Data((UBlockCompiler.version + "\n" + store.preferences.blockingExceptions.sorted().joined(separator: ",")).utf8))
        for name in ["js/static-dnr-filtering.js", "js/make-scriptlets.js", "js/resources/scriptlets.js", "manifest.json"] {
            if let data = try? Data(contentsOf: package.appendingPathComponent(name)) { hash.update(data: data) }
        }
        for list in lists { hash.update(data: Data(list.key.utf8)); if let url = source(of: list, in: package), let data = try? Data(contentsOf: url) { hash.update(data: data) } }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    private func saveBuildDate() {
        guard var build = try? Persistence.read(Build.self, at: buildFile) else { return }
        build.listsUpdated = listsUpdated
        try? Persistence.write(build, at: buildFile)
    }
    var summary: String {
        guard let stats else { return "" }
        let number = NumberFormatter(); number.numberStyle = .decimal; number.locale = Locale(identifier: store.language == .ru ? "ru_RU" : "en_US")
        let n = { (value: Int) in number.string(from: NSNumber(value: value)) ?? String(value) }
        return store.text("правил для запросов: ", "Правил для запросов: ") + n(stats.network) + store.text(", скрытия: ", ", скрытия: ") + n(stats.cosmetic) + store.text(", скриптлетов: ", ", скриптлетов: ") + n(stats.scriptlets)
    }

    /// Reuses the stored build when nothing it was made from changed; otherwise compiles in the hidden page, then
    /// compiles the two content rule lists. Tabs keep the previous rules until the new ones are ready.
    func rebuild() async {
        guard let package, active else { return }
        generation += 1; let version = generation
        let lists = defaultLists(package)
        let fingerprint = fingerprint(package, lists: lists)
        let ruleStore = store.blocker.ruleStore
        do {
            if let build = try? Persistence.read(Build.self, at: buildFile), build.fingerprint == fingerprint,
               let main = try? String(contentsOf: folder.appendingPathComponent("main.js"), encoding: .utf8),
               let isolated = try? String(contentsOf: folder.appendingPathComponent("isolated.js"), encoding: .utf8),
               let network = try? await ruleStore.contentRuleList(forIdentifier: "ublock-network"),
               let cosmetic = try? await ruleStore.contentRuleList(forIdentifier: "ublock-cosmetic") {
                guard version == generation else { return }
                install(network: network, cosmetic: cosmetic, main: main, isolated: isolated, stats: build.stats)
                listsUpdated = build.listsUpdated
                return
            }
            compiling = true; defer { if version == generation { compiling = false } }
            status = store.text("сборка фильтров uBlock Origin…", "Сборка фильтров uBlock Origin…")
            let output = try await compile(package: package, lists: lists)
            guard version == generation else { return }
            let network = try await ruleStore.compileContentRuleList(forIdentifier: "ublock-network", encodedContentRuleList: output.network)
            let cosmetic = try await ruleStore.compileContentRuleList(forIdentifier: "ublock-cosmetic", encodedContentRuleList: output.cosmetic)
            guard version == generation, let network, let cosmetic else { return }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try output.main.write(to: folder.appendingPathComponent("main.js"), atomically: true, encoding: .utf8)
            try output.isolated.write(to: folder.appendingPathComponent("isolated.js"), atomically: true, encoding: .utf8)
            try Persistence.write(Build(fingerprint: fingerprint, stats: output.stats, compiled: Date(), listsUpdated: listsUpdated), at: buildFile)
            install(network: network, cosmetic: cosmetic, main: output.main, isolated: output.isolated, stats: output.stats)
        } catch {
            guard version == generation else { return }
            status = store.text("фильтры uBlock Origin не собраны: ", "Фильтры uBlock Origin не собраны: ") + error.localizedDescription
        }
    }
    private func install(network: WKContentRuleList, cosmetic: WKContentRuleList, main: String, isolated: String, stats: Stats) {
        self.network = network; self.cosmetic = cosmetic; mainScript = main; isolatedScript = isolated; self.stats = stats
        scripts = []
        if !main.isEmpty { scripts.append(WKUserScript(source: guardedScript(main), injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .page)) }
        if !isolated.isEmpty { scripts.append(WKUserScript(source: guardedScript(isolated), injectionTime: .atDocumentStart, forMainFrameOnly: false, in: Self.world)) }
        status = summary
        refreshTabs()
    }

    /// An excluded top-level site also excludes its cross-origin child frames.
    private func guardedScript(_ source: String) -> String {
        let exceptions = String(data: (try? JSONSerialization.data(withJSONObject: store.preferences.blockingExceptions)) ?? Data("[]".utf8), encoding: .utf8) ?? "[]"
        return Self.marker + """
        (() => {
            const off = \(exceptions);
            const hosts = [location.hostname];
            try { hosts.push(top.location.hostname); } catch {}
            for (const origin of Array.from(location.ancestorOrigins || [])) { try { hosts.push(new URL(origin).hostname); } catch {} }
            if (hosts.some(host => off.some(domain => host === domain || host.endsWith('.' + domain)))) return;
            \(source)
        })();
        """
    }

    private struct Output { var network: String; var cosmetic: String; var main: String; var isolated: String; var stats: Stats }
    /// Runs the compiler module in a hidden web view that can only read the package, the lists and the module.
    private func compile(package: URL, lists: [FilterList]) async throws -> Output {
        var files: [String: URL] = [:]
        for list in lists { if let url = source(of: list, in: package) { files[list.key] = url } }
        guard !files.isEmpty else { throw MicaError.message("uBlock Origin lists are missing") }
        let handler = UBlockSchemeHandler(package: package, lists: files)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(handler, forURLScheme: UBlockSchemeHandler.scheme)
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 10, height: 10), configuration: configuration)
        self.handler = handler; compiler = view
        defer { if compiler === view { compiler = nil; self.handler = nil } }
        let loaded = NavigationWaiter(); view.navigationDelegate = loaded
        view.load(URLRequest(url: URL(string: "\(UBlockSchemeHandler.scheme)://pkg/__mica__/index.html")!))
        try await loaded.wait()
        let keys = lists.filter { files[$0.key] != nil }.map { ["key": $0.key, "trusted": $0.trusted] as [String: Any] }
        let script = """
        const lists = await Promise.all(keys.map(async k => ({ name: k.key, trustedSource: k.trusted, text: await (await fetch('/__lists__/' + k.key)).text() })));
        const probe = document.createElement('div');
        const validSelector = s => { try { probe.querySelector(s); return true; } catch { return false; } };
        const { build } = await import('/__mica__/compiler.mjs');
        const r = await build(lists, { validSelector, exceptions });
        return { network: JSON.stringify(r.network), cosmetic: JSON.stringify(r.cosmetic), main: r.main, isolated: r.isolated, stats: JSON.stringify(r.stats) };
        """
        let value = try await view.callAsyncJavaScript(script, arguments: ["keys": keys, "exceptions": store.preferences.blockingExceptions], contentWorld: .page)
        guard let result = value as? [String: Any], let network = result["network"] as? String, let cosmetic = result["cosmetic"] as? String,
              let main = result["main"] as? String, let isolated = result["isolated"] as? String, let statsJSON = result["stats"] as? String,
              let stats = try? JSONDecoder().decode(Stats.self, from: Data(statsJSON.utf8)) else { throw MicaError.message("uBlock Origin compiler returned no result") }
        return Output(network: network, cosmetic: cosmetic, main: main, isolated: isolated, stats: stats)
    }

    // MARK: Tabs

    /// Content rule lists for a web view; Blocker.apply calls this after adding mica's own list.
    func addRules(to controller: WKUserContentController) {
        guard active else { return }
        if let network { controller.add(network) }
        if let cosmetic { controller.add(cosmetic) }
    }
    /// The scriptlet bundles, at document start in every frame.
    func addScripts(to controller: WKUserContentController) {
        guard active else { return }
        for script in scripts { controller.addUserScript(script) }
    }
    /// New rules or scripts reach open tabs at once; pages already loaded get the scripts on their next load.
    func refreshTabs() {
        for window in store.windows { for tab in window.model.tabs { tab.refreshFilters() } }
    }
}

/// Serves the hidden compiler page: the installed uBO package (read only, inside its folder), the filter lists by key
/// and mica's module. Nothing else is reachable from that page.
final class UBlockSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "mica-ubo"
    let package: URL
    let lists: [String: URL]
    init(package: URL, lists: [String: URL]) { self.package = package.standardizedFileURL; self.lists = lists }
    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url, url.host == "pkg" else { return fail(task) }
        let path = url.path
        let body: Data?, type: String
        if path == "/__mica__/index.html" {
            // crypto.randomUUID needs a secure context; uBO's code calls it, getRandomValues works everywhere.
            body = Data("<!doctype html><meta charset=utf-8><script>if (!crypto.randomUUID) crypto.randomUUID = () => ([1e7]+-1e3+-4e3+-8e3+-1e11).replace(/[018]/g, c => (c ^ crypto.getRandomValues(new Uint8Array(1))[0] & 15 >> c / 4).toString(16));</script>".utf8)
            type = "text/html"
        } else if path == "/__mica__/compiler.mjs" {
            body = Data(UBlockCompiler.module.utf8); type = "text/javascript"
        } else if path.hasPrefix("/__lists__/"), let file = lists[String(path.dropFirst("/__lists__/".count))] {
            body = try? Data(contentsOf: file); type = "text/plain"
        } else {
            let relative = path.hasPrefix("/__mica__/ublock/") ? String(path.dropFirst("/__mica__/ublock/".count)) : String(path.dropFirst())
            let file = package.appendingPathComponent(relative).standardizedFileURL
            guard file.path.hasPrefix(package.path + "/"), (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { return fail(task) }
            body = try? Data(contentsOf: file)
            switch file.pathExtension { case "js", "mjs": type = "text/javascript"; case "json": type = "application/json"; case "html": type = "text/html"; default: type = "text/plain" }
        }
        guard let body else { return fail(task) }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": type + "; charset=utf-8", "Content-Length": String(body.count)])!
        task.didReceive(response); task.didReceive(body); task.didFinish()
    }
    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}
    private func fail(_ task: any WKURLSchemeTask) { task.didFailWithError(URLError(.fileDoesNotExist)) }
}

/// Waits for the first load of a web view to finish.
private final class NavigationWaiter: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?
    private var result: Result<Void, Error>?
    func wait() async throws {
        if let result { return try result.get() }
        try await withCheckedThrowingContinuation { continuation = $0 }
    }
    private func finish(_ value: Result<Void, Error>) {
        guard result == nil else { return }
        result = value; continuation?.resume(with: value); continuation = nil
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish(.success(())) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(.failure(error)) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(.failure(error)) }
}
