import XCTest
@testable import MicaCore

final class CoreTests: XCTestCase {
    func testAddressParsing() {
        XCTAssertEqual(AddressParser.resolve(" example.com/a?q=1 "), .web(URL(string: "https://example.com/a?q=1")!))
        XCTAssertEqual(AddressParser.resolve("localhost:8091/test"), .web(URL(string: "http://localhost:8091/test")!))
        XCTAssertEqual(AddressParser.resolve("127.0.0.1:8080"), .web(URL(string: "http://127.0.0.1:8080")!))
        XCTAssertEqual(AddressParser.resolve("hello Swift", engine: .google), .web(URL(string: "https://www.google.com/search?q=hello%20Swift")!))
        XCTAssertEqual(AddressParser.resolve("mailto:test@example.com"), .external(URL(string: "mailto:test@example.com")!))
    }
    func testRejectExecutableAndLocalSchemes() {
        for input in ["javascript:alert(1)", "https://user:password@example.com", "data:text/html,hello", "file:///etc/passwd", "x-apple.systempreferences:security", "https:", "about:blank"] { if case .rejected = AddressParser.resolve(input) {} else { XCTFail(input) } }
    }
    func testQueryEncoding() {
        let query = "ООО + GitHub & Apple #?"
        for engine in SearchEngine.allCases { XCTAssertEqual(URLComponents(url: engine.search(query), resolvingAgainstBaseURL: false)?.queryItems?.first?.value, query) }
    }
    func testOriginIncludesNondefaultPort() {
        XCTAssertEqual(Origin.string(URL(string: "https://EXAMPLE.com:443/page")), "https://example.com")
        XCTAssertEqual(Origin.string(URL(string: "https://example.com:8443/page")), "https://example.com:8443")
        XCTAssertNil(Origin.string(URL(string: "file:///tmp/example")))
        XCTAssertFalse(Origin.secure("http://example.com"))
    }
    func testSessionsRejectUnsafeURLsAndDuplicateIDs() {
        let id = UUID()
        let valid = SavedTab(id: id, url: URL(string: "https://example.com"))
        let invalid = SavedTab(id: id, url: URL(string: "javascript:alert(1)"))
        let window = SavedWindow(tabs: [invalid, valid, valid], selected: invalid.id)
        let result = Session(windows: [window]).validated().windows[0]
        XCTAssertEqual(result.tabs, [valid]); XCTAssertEqual(result.selected, valid.id)
    }
    func testSessionsKeepOpenedLocalFilesOnly() {
        let page = SavedTab(url: URL(string: "file:///Users/me/page.html"), access: Data([1, 2, 3]))
        let system = SavedTab(url: URL(string: "file:///etc/passwd"))
        let share = SavedTab(url: URL(string: "file://server/share/page.html"))
        let result = Session(windows: [SavedWindow(tabs: [system, page, share], selected: system.id)]).validated().windows[0]
        XCTAssertEqual(result.tabs, [page]); XCTAssertEqual(result.selected, page.id)
        XCTAssertFalse(AddressParser.navigable(page.url!))
        let decoded = try? JSONDecoder().decode(SavedTab.self, from: Data(#"{"id":"\#(UUID().uuidString)","title":"","pinned":false}"#.utf8))
        XCTAssertNotNil(decoded); XCTAssertNil(decoded?.access)
    }
    func testPinnedOrderAndMoveBoundaries() {
        let a = SavedTab(title: "a"), b = SavedTab(title: "b"), pin = SavedTab(title: "pin", pinned: true)
        let tabs = [pin, a, b]
        XCTAssertEqual(TabPolicy.moving(tabs, id: b.id, before: a.id), [pin, b, a])
        XCTAssertEqual(TabPolicy.moving(tabs, id: b.id, before: pin.id), tabs)
    }
    func testRestorePolicyHonorsSelectedAndExceptions() {
        let selected = SavedTab(url: URL(string: "https://mail.example.com"))
        let background = SavedTab(url: URL(string: "https://example.com"))
        var preferences = Preferences()
        XCTAssertTrue(TabPolicy.shouldLoadOnRestore(selected, selected: selected.id, preferences: preferences))
        XCTAssertFalse(TabPolicy.shouldLoadOnRestore(background, selected: selected.id, preferences: preferences))
        preferences.eagerHosts = ["example.com"]
        XCTAssertTrue(TabPolicy.shouldLoadOnRestore(background, selected: selected.id, preferences: preferences))
    }
    func testSettingsRoundTripAndSafeDefaults() throws {
        var p = Preferences(); XCTAssertTrue(p.blocking); XCTAssertTrue(p.lowercase)
        p.layout = .right; p.search = .kagi; p.theme = .dark; p.eagerHosts = ["GitHub.com"]
        XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(p)), p)
    }
    func testCasePreservesDynamicNames() {
        let names = "Apple, GitHub, Google Chrome, ООО, ДПС"
        XCTAssertEqual(Copy.text("источник: ", "Источник: ", lowercase: true) + names, "источник: " + names)
        XCTAssertEqual(Copy.text("источник: ", "Источник: ", lowercase: false) + names, "Источник: " + names)
    }
    func testPermissionIdentityAndRoundTrip() throws {
        let camera = SitePermission(origin: "https://a.com", capability: .camera, decision: .deny)
        let microphone = SitePermission(origin: "https://a.com", capability: .microphone, decision: .allow)
        XCTAssertNotEqual(camera.id, microphone.id)
        XCTAssertEqual(try JSONDecoder().decode([SitePermission].self, from: JSONEncoder().encode([camera, microphone])), [camera, microphone])
    }
    func testSafeDownloadFilename() {
        XCTAssertEqual(DownloadSafety.filename("../../secret.txt"), "secret.txt")
        XCTAssertEqual(DownloadSafety.filename(".."), "download")
        XCTAssertEqual(DownloadSafety.filename("report\n:2026.pdf"), "report2026.pdf")
        XCTAssertEqual(DownloadSafety.filename("ДПС — Отчёт.pdf"), "ДПС — Отчёт.pdf")
    }
    func testArchiveTraversal() {
        for entry in ["../file", "/etc/passwd", "dir/../../bad", "a\\b", "nul\0bad"] { XCTAssertFalse(PackageSafety.safeEntry(entry), entry) }
        for entry in ["manifest.json", "scripts/app.js", "_locales/ru/messages.json"] { XCTAssertTrue(PackageSafety.safeEntry(entry), entry) }
    }
    func testDomainListValidation() throws {
        XCTAssertEqual(try BlockingRules.parseDomains("# source\nads.example.com\npgl.example0101\nADS.EXAMPLE.COM"), ["ads.example.com", "pgl.example0101"])
        XCTAssertThrowsError(try BlockingRules.parseDomains("<html>error</html>"))
        XCTAssertThrowsError(try BlockingRules.parseDomains("ads_bad.example.com"))
        XCTAssertThrowsError(try BlockingRules.parseDomains("localhost"))
    }
    func testBlockingRulesActuallyMatchDomainNotSubstring() throws {
        let json = try BlockingRules.json(exceptions: ["example.com"])
        let rules = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])
        XCTAssertEqual(rules.count, BlockingRules.domains.count + 1)
        let trigger = try XCTUnwrap(rules.first?["trigger"] as? [String: Any])
        let regex = try NSRegularExpression(pattern: XCTUnwrap(trigger["url-filter"] as? String))
        func matches(_ text: String) -> Bool { regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil }
        XCTAssertTrue(matches("https://ads.doubleclick.net/script.js"))
        XCTAssertFalse(matches("https://notdoubleclick.net/script.js"))
        XCTAssertFalse(matches("https://example.com/doubleclick.net"))
        XCTAssertEqual((rules.last?["action"] as? [String: String])?["type"], "ignore-previous-rules")
    }
    func testAtomicPersistence() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("state.json")
        try Persistence.write(Preferences(), at: url)
        var next = Preferences(); next.lowercase = false
        try Persistence.write(next, at: url)
        XCTAssertEqual(try Persistence.read(Preferences.self, at: url), next)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int, 0o600)
    }
    func testExtensionStateRoundTrip() throws {
        let record = ExtensionRecord(name: "Test", version: "1", enabled: false, digest: "abc", source: "local", permissions: ["storage"], hosts: [])
        let round = try JSONDecoder().decode(ExtensionRecord.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(round.id, record.id); XCTAssertFalse(round.enabled); XCTAssertTrue(round.hosts.isEmpty)
    }
    func testPreferencesFromOlderBuildKeepSavedValuesAndDefaultNewOnes() throws {
        let old = #"{"layout":"top","theme":"dark","lowercase":false,"frosted":false,"density":0.6,"search":"Kagi","blocking":false,"restore":true,"lazyRestore":false,"eagerHosts":["mail.example"],"blockingExceptions":[],"onboardingComplete":true}"#
        let p = try JSONDecoder().decode(Preferences.self, from: Data(old.utf8))
        XCTAssertEqual(p.layout, .top); XCTAssertEqual(p.search, .kagi); XCTAssertFalse(p.lowercase); XCTAssertEqual(p.eagerHosts, ["mail.example"])
        XCTAssertFalse(p.sidebarCollapsed); XCTAssertEqual(p.sidebarWidth, Preferences().sidebarWidth)
        let wide = try JSONDecoder().decode(Preferences.self, from: Data(#"{"sidebarWidth":9000}"#.utf8))
        XCTAssertEqual(wide.sidebarWidth, Preferences.sidebarRange.upperBound)
    }
    func testTabsAboveLayoutRoundTripsAndOldValuesStayValid() throws {
        var p = Preferences(); p.layout = .tabsAbove
        let data = try JSONEncoder().encode(p)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains(#""layout":"tabsAbove""#))
        XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: data).layout, .tabsAbove)
        for (raw, layout) in [("left", TabLayout.left), ("right", .right), ("top", .top), ("tabsAbove", .tabsAbove)] {
            XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: Data(#"{"layout":"\#(raw)","theme":"dark"}"#.utf8)).layout, layout)
        }
        // An unknown layout keeps the rest of the file.
        let future = try JSONDecoder().decode(Preferences.self, from: Data(#"{"layout":"bottom","theme":"dark"}"#.utf8))
        XCTAssertEqual(future.layout, Preferences().layout); XCTAssertEqual(future.theme, .dark)
    }
    func testNarrowWindowKeepsChosenTopLayoutAndMovesSidebarToTop() {
        XCTAssertEqual(TabLayout.left.fitting(width: 759), .top)
        XCTAssertEqual(TabLayout.right.fitting(width: 640), .top)
        XCTAssertEqual(TabLayout.top.fitting(width: 640), .top)
        XCTAssertEqual(TabLayout.tabsAbove.fitting(width: 640), .tabsAbove)
        for layout in TabLayout.allCases { XCTAssertEqual(layout.fitting(width: TabLayout.narrowWidth), layout) }
        XCTAssertEqual(TabLayout.allCases.filter(\.horizontal), [.top, .tabsAbove])
        XCTAssertEqual(TabLayout.left.sidebarEdge, .left); XCTAssertEqual(TabLayout.right.sidebarEdge, .right)
        XCTAssertNil(TabLayout.top.sidebarEdge); XCTAssertNil(TabLayout.tabsAbove.sidebarEdge)
    }
    func testYandexUsesTextParameterAndUnknownEngineFallsBack() throws {
        let url = SearchEngine.yandex.search("погода")
        XCTAssertEqual(url.host, "yandex.ru")
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.name, "text")
        XCTAssertTrue(SearchEngine.yandex.isSearch(url, for: "погода"))
        let p = try JSONDecoder().decode(Preferences.self, from: Data(#"{"search":"Altavista","layout":"right"}"#.utf8))
        XCTAssertEqual(p.search, .duckduckgo); XCTAssertEqual(p.layout, .right)
    }
    func testToolbarPlacementKeepsEachItemInOneZone() throws {
        var t = ToolbarLayout()
        XCTAssertEqual(t.zone(of: .newTab), .hidden)
        t.place(.downloads, in: .trailing)
        XCTAssertEqual(t.zone(of: .downloads), .trailing); XCTAssertFalse(t.sidebar.contains(.downloads))
        t.place(.back, in: .hidden)
        XCTAssertTrue(t.items(in: .hidden).contains(.back)); XCTAssertFalse(t.leading.contains(.back))
        t.shift(.reload, by: -5)
        XCTAssertEqual(t.leading.first, .reload)
        t.shift(.reload, by: 1)
        XCTAssertEqual(t.leading, [.sidebar, .reload, .forward])
        let json = #"{"leading":["back","back","unknown"],"trailing":["back","settings"],"sidebar":[],"addressWidth":99999}"#
        let decoded = try JSONDecoder().decode(ToolbarLayout.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.leading, [.back]); XCTAssertEqual(decoded.trailing, [.settings]); XCTAssertEqual(decoded.addressWidth, ToolbarLayout.addressRange.upperBound)
    }
    func testToolbarWithoutSidebarMovesSidebarItemsRight() {
        let t = ToolbarLayout()
        let top = t.resolved(sidebarAvailable: false)
        XCTAssertFalse(top.leading.contains(.sidebar)); XCTAssertEqual(top.trailing, t.sidebar); XCTAssertTrue(top.sidebar.isEmpty)
        XCTAssertEqual(t.resolved(sidebarAvailable: true).sidebar, t.sidebar)
    }
    func testStartPageSectionsShortcutsAndFrequentSites() throws {
        var start = StartPage()
        start.setVisible(.bookmarks, true); start.setVisible(.custom, false); start.shift(.bookmarks, by: -1)
        XCTAssertEqual(start.sections, [.bookmarks, .frequent])
        XCTAssertNil(StartPage.shortcutURL("hello world", engine: .duckduckgo))
        XCTAssertEqual(StartPage.shortcutURL("github.com", engine: .duckduckgo), URL(string: "https://github.com"))
        let a = StartShortcut(title: "A", url: URL(string: "https://a.com")!), b = StartShortcut(title: "B", url: URL(string: "https://b.com")!), c = StartShortcut(title: "C", url: URL(string: "https://c.com")!)
        start.shortcuts = [a, b, c]
        start.moveShortcut(c.id, before: a.id); XCTAssertEqual(start.shortcuts.map(\.title), ["C", "A", "B"])
        start.shiftShortcut(c.id, by: 2); XCTAssertEqual(start.shortcuts.map(\.title), ["A", "B", "C"])
        let history = ["https://x.com/1", "https://x.com/2", "https://y.com", "https://hidden.com", "https://hidden.com/a", "https://z.invalid"].map { Visit(url: URL(string: $0)!, title: "") }
        XCTAssertEqual(StartPage.frequent(history, excluding: ["hidden.com"], limit: 8).map(\.url.absoluteString), ["https://x.com", "https://y.com"])
        let bad = #"{"sections":["frequent","frequent","nope"],"frequentCount":99,"shortcuts":[{"id":"6F9619FF-8B86-D011-B42D-00CF4FC964FF","title":"x","url":"javascript:alert(1)"}]}"#
        let decoded = try JSONDecoder().decode(StartPage.self, from: Data(bad.utf8))
        XCTAssertEqual(decoded.sections, [.frequent]); XCTAssertEqual(decoded.frequentCount, 16); XCTAssertTrue(decoded.shortcuts.isEmpty)
    }
    func testCustomThemeAccentAndOlderPreferences() throws {
        XCTAssertEqual(HexColor.string(red: 1, green: 0.5, blue: 0), "#FF8000")
        XCTAssertNotNil(HexColor.parse("#6e56cf")); XCTAssertNil(HexColor.parse("#12345"))
        XCTAssertGreaterThan(HexColor.luminance("#FFFFFF")!, 0.99); XCTAssertLessThan(HexColor.luminance("#000000")!, 0.01)
        let p = try JSONDecoder().decode(Preferences.self, from: Data(#"{"theme":"custom","customBase":"custom","accent":"zzz","transparency":4}"#.utf8))
        XCTAssertEqual(p.theme, .custom); XCTAssertEqual(p.customBase, .system); XCTAssertEqual(p.accent, Preferences().accent); XCTAssertEqual(p.transparency, 1)
        XCTAssertNil(p.appIcon); XCTAssertEqual(p.toolbar, ToolbarLayout()); XCTAssertEqual(p.start, StartPage())
        var q = Preferences(); q.appIcon = "base-blue"; q.toolbar.place(.newTab, in: .trailing); q.start.shortcuts = [StartShortcut(title: "GitHub", url: URL(string: "https://github.com")!)]
        XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(q)), q)
    }
}
