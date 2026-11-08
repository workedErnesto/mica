import XCTest
@testable import MicaCore

final class ImportUpdateTests: XCTestCase {
    func testSelectedProfileFolderDiscovery() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let profile = root.appendingPathComponent("Default", isDirectory: true)
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("{}".utf8).write(to: profile.appendingPathComponent("Bookmarks"))
        XCTAssertEqual(ImportDiscovery.profiles(authorizedFolder: root).first?.path, profile)
        XCTAssertEqual(ImportDiscovery.profiles(authorizedFolder: profile).first?.browser.family, .chromium)
        XCTAssertEqual(ImportDiscovery.profiles(authorizedFolder: profile).first?.browser.id, "chromium")
        XCTAssertTrue(ImportDiscovery.profiles(authorizedFolder: root.appendingPathComponent("missing")).isEmpty)
    }

    func testChromiumTimeAndBookmarks() throws {
        // 2021-01-01T00:00:00Z
        XCTAssertEqual(ChromiumReader.date(13_253_932_800_000_000)?.timeIntervalSince1970, 1_609_459_200)
        XCTAssertNil(ChromiumReader.date(0))
        let json = """
        {"roots":{"bookmark_bar":{"type":"folder","children":[{"type":"url","name":"GitHub","url":"https://github.com/","date_added":"13253932800000000"},
        {"type":"folder","children":[{"type":"url","name":"","url":"https://apple.com/mac"},{"type":"url","name":"js","url":"javascript:alert(1)"}]}]},
        "other":{"type":"folder","children":[{"type":"url","name":"Duck","url":"https://duckduckgo.com"}]}}}
        """
        let marks = try ChromiumReader.bookmarks(json: Data(json.utf8))
        XCTAssertEqual(marks.map(\.title), ["GitHub", "apple.com", "Duck"])
        XCTAssertEqual(marks.first?.date.timeIntervalSince1970, 1_609_459_200)
    }

    func testChromiumSQLiteHistory() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try sqlite(folder.appendingPathComponent("History"), """
        CREATE TABLE urls(id INTEGER PRIMARY KEY, url TEXT, title TEXT, last_visit_time INTEGER, hidden INTEGER DEFAULT 0);
        INSERT INTO urls(url,title,last_visit_time) VALUES('https://a.example/','A',13253932800000000),('https://b.example/','B',13253932900000000),('chrome://settings','S',13253932950000000);
        """)
        let history = try ChromiumReader.history(folder)
        XCTAssertEqual(history.map(\.title), ["B", "A"])
    }

    func testGeckoProfilesHistoryBookmarks() throws {
        let ini = "[Install123]\nDefault=Profiles/b.release\n\n[Profile1]\nName=old\nIsRelative=1\nPath=Profiles/a.default\n\n[Profile0]\nName=default-release\nIsRelative=1\nPath=Profiles/b.release\nDefault=1\n"
        XCTAssertEqual(GeckoReader.parseProfiles(ini).map(\.name), ["default-release", "old"])
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try sqlite(folder.appendingPathComponent("places.sqlite"), """
        CREATE TABLE moz_places(id INTEGER PRIMARY KEY, url TEXT, title TEXT, last_visit_date INTEGER, hidden INTEGER DEFAULT 0);
        CREATE TABLE moz_bookmarks(id INTEGER PRIMARY KEY, type INTEGER, fk INTEGER, parent INTEGER, position INTEGER, title TEXT, dateAdded INTEGER);
        INSERT INTO moz_places(url,title,last_visit_date) VALUES('https://x.example/','X',1609459200000000),('place:sort=8','',NULL);
        INSERT INTO moz_bookmarks(type,fk,parent,position,title,dateAdded) VALUES(1,1,2,0,'Икс',1609459200000000),(1,2,2,1,'q',0),(2,NULL,1,0,'folder',0);
        """)
        XCTAssertEqual(try GeckoReader.history(folder).map(\.title), ["X"])
        XCTAssertEqual(try GeckoReader.bookmarks(folder).map(\.title), ["Икс"])
    }

    func testSafariExportFiles() throws {
        let html = """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <DL><p><DT><H3>Bar</H3><DL><p><DT><A HREF="https://example.com/?a=1&amp;b=2" ADD_DATE="1609459200">Tom &amp; Jerry</A>
        <DT><A HREF="https://apple.com">Apple</A></DL><p></DL>
        """
        let marks = SafariReader.bookmarks(html: html)
        XCTAssertEqual(marks.map(\.url.absoluteString), ["https://example.com/?a=1&b=2", "https://apple.com"])
        XCTAssertEqual(marks.first?.title, "Tom & Jerry")
        let json = #"{"metadata":{"browser_name":"Safari"},"history":[{"url":"https://example.com/","title":"Ex","time_usec":1609459200000000}]}"#
        XCTAssertEqual(try SafariReader.history(exportJSON: Data(json.utf8)).first?.date.timeIntervalSince1970, 1_609_459_200)
    }

    func testMergeKeepsNewestAndSkipsDuplicates() {
        var old = Visit(url: URL(string: "https://a.example")!, title: "A"); old.date = Date(timeIntervalSince1970: 100)
        var dup = Visit(url: URL(string: "https://a.example")!, title: "A2"); dup.date = Date(timeIntervalSince1970: 200)
        var fresh = Visit(url: URL(string: "https://b.example")!, title: "B"); fresh.date = Date(timeIntervalSince1970: 150)
        let history = ImportMerge.history([old], adding: [dup, fresh])
        XCTAssertEqual(history.added, 1)
        XCTAssertEqual(history.merged.map(\.title), ["B", "A"])
        let marks = ImportMerge.bookmarks([old], adding: [dup, fresh, fresh])
        XCTAssertEqual(marks.added, 1)
        XCTAssertEqual(ImportMerge.history([], adding: [old, fresh], limit: 1).merged.map(\.title), ["B"])
    }

    func testVersionsAndUpdatePolicy() throws {
        XCTAssertEqual(AppVersion("v0.3.0"), AppVersion("0.3"))
        XCTAssertLessThan(AppVersion("0.2.9")!, AppVersion("0.10.0")!)
        XCTAssertNil(AppVersion("beta"))
        XCTAssertNil(AppVersion("1..2"))
        XCTAssertNil(AppVersion("-1.2"))
        let json = """
        {"tag_name":"v0.3.0","name":"mica 0.3.0","body":"notes","html_url":"https://github.com/workedErnesto/mica/releases/tag/v0.3.0","draft":false,"prerelease":false,
        "assets":[{"name":"mica-0.3.0.dmg","size":10,"browser_download_url":"https://github.com/x/mica-0.3.0.dmg"},{"name":"mica-0.3.0.dmg.sha256","size":1,"browser_download_url":"https://github.com/x/mica-0.3.0.dmg.sha256"}]}
        """
        let release = try JSONDecoder().decode(Release.self, from: Data(json.utf8))
        var prefs = Preferences()
        XCTAssertTrue(UpdatePolicy.offer(release, current: AppVersion("0.2.0")!, preferences: prefs))
        XCTAssertFalse(UpdatePolicy.offer(release, current: AppVersion("0.3.0")!, preferences: prefs))
        prefs.skippedVersion = "0.3.0"
        XCTAssertFalse(UpdatePolicy.offer(release, current: AppVersion("0.2.0")!, preferences: prefs))
        prefs.skippedVersion = nil; prefs.updateChecks = false
        XCTAssertFalse(UpdatePolicy.offer(release, current: AppVersion("0.2.0")!, preferences: prefs))
        let unsigned = Release(tag: "v0.4.0", name: nil, notes: nil, page: release.page, assets: [release.assets[0]])
        XCTAssertFalse(UpdatePolicy.offer(unsigned, current: AppVersion("0.2.0")!, preferences: Preferences()))
        XCTAssertEqual(UpdatePolicy.parseChecksum(String(repeating: "aB", count: 32) + "  mica.dmg\n"), String(repeating: "ab", count: 32))
        XCTAssertNil(UpdatePolicy.parseChecksum("nope"))
        XCTAssertNil(UpdatePolicy.parseChecksum(String(repeating: "ａ", count: 64)))
        let now = Date(timeIntervalSince1970: 100_000)
        XCTAssertEqual(UpdatePolicy.delaySinceLastCheck(nil, now: now), 0)
        XCTAssertEqual(UpdatePolicy.delaySinceLastCheck(now.addingTimeInterval(-3600), now: now), 82_800)
        XCTAssertEqual(UpdatePolicy.delaySinceLastCheck(now.addingTimeInterval(-90_000), now: now), 0)
        XCTAssertEqual(UpdatePolicy.delaySinceLastCheck(now.addingTimeInterval(3600), now: now), 86_400)
        XCTAssertEqual(InstallState.compare(running: AppVersion("0.3.0")!, installed: AppVersion("0.2.0")), .older(AppVersion("0.2.0")!))
        XCTAssertEqual(InstallState.compare(running: AppVersion("0.3.0")!, installed: nil), .notInstalled)
        XCTAssertTrue(InstallState.runsFromDiskImage("/Volumes/mica/mica.app"))
        XCTAssertTrue(InstallState.runsFromDiskImage("/private/var/folders/x/AppTranslocation/ABC/d/mica.app"))
        XCTAssertFalse(InstallState.runsFromDiskImage("/Applications/mica.app"))
        // Preferences saved before updates existed load with checks on.
        let decoded = try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8))
        XCTAssertTrue(decoded.updateChecks)
    }

    /// Reads this Mac's real browsers. Runs only with MICA_REAL_IMPORT=1 .
    func testRealProfilesWhenAsked() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MICA_REAL_IMPORT"] == "1")
        for profile in ImportDiscovery.profiles() {
            let read = ImportReader.read(profile, kinds: Set(ImportKind.allCases))
            print("REAL", profile.browser.name, profile.name, "history", read.bundle.history.count, "bookmarks", read.bundle.bookmarks.count, "failures", read.failures)
        }
    }

    private func sqlite(_ url: URL, _ sql: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [url.path, sql]
        try process.run(); process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }
}
