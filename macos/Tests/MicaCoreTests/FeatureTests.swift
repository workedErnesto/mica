import XCTest
import Security
import CryptoKit
@testable import MicaCore

final class FeatureTests: XCTestCase {
    func testLanguageDefaultsAndEnglishCopy() throws {
        XCTAssertEqual(Language.preferred(["ru-RU", "en-US"]), .ru)
        XCTAssertEqual(Language.preferred(["de-DE", "en-GB"]), .en)
        XCTAssertEqual(Language.preferred(["ja-JP"]), .en)
        // Preferences saved before the setting existed came from a Russian-only build.
        let old = try JSONDecoder().decode(Preferences.self, from: Data(#"{"layout":"left"}"#.utf8))
        XCTAssertEqual(old.language, .ru)
        var p = Preferences(); p.language = .en
        XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(p)).language, .en)
        XCTAssertEqual(Copy.text("готово", "Готово", lowercase: true, language: .en), "done")
        XCTAssertEqual(Copy.text("готово", "Готово", lowercase: false, language: .en), "Done")
        XCTAssertEqual(Copy.text("готово", "Готово", lowercase: true, language: .ru), "готово")
        // Untranslated brand-only text falls back to the source spelling.
        XCTAssertEqual(Copy.text("sonic", "Sonic", lowercase: true, language: .en), "sonic")
    }

    func testGreetingKeepsNameAndRespectsOptOut() {
        var p = Preferences(); p.language = .ru; p.lowercase = true
        XCTAssertNil(Greeting.text(p, hour: 10, seed: 0))
        p.userName = "  ДПС Эрнесто "
        let morning = Greeting.text(p, hour: 9, seed: 0)
        XCTAssertEqual(morning, "доброе утро, ДПС Эрнесто")
        for seed in 0..<20 { XCTAssertTrue(Greeting.text(p, hour: 15, seed: seed)!.contains("ДПС Эрнесто")) }
        XCTAssertEqual(Set((0..<20).map { Greeting.text(p, hour: 15, seed: $0)! }).count, Greeting.phrases(hour: 15, language: .ru).count)
        p.lowercase = false; XCTAssertEqual(Greeting.text(p, hour: 20, seed: 1), "Привет, ДПС Эрнесто")
        p.language = .en; XCTAssertEqual(Greeting.text(p, hour: 20, seed: 0), "Good evening, ДПС Эрнесто")
        XCTAssertEqual(Greeting.text(p, hour: 20, seed: -1), Greeting.text(p, hour: 20, seed: Greeting.phrases(hour: 20, language: .en).count - 1))
        p.greetByName = false; XCTAssertNil(Greeting.text(p, hour: 9, seed: 0))
        let long = try! JSONDecoder().decode(Preferences.self, from: Data(("{\"userName\":\"" + String(repeating: "я", count: 80) + "\"}").utf8))
        XCTAssertEqual(long.userName.count, Preferences.nameLimit)
    }

    func testToolbarDropInsertAndNewControlMigration() throws {
        var t = ToolbarLayout()
        t.insert(.settings, in: .leading, before: .back)
        XCTAssertEqual(t.leading, [.sidebar, .settings, .back, .forward, .reload]); XCTAssertFalse(t.sidebar.contains(.settings))
        t.insert(.settings, in: .trailing); XCTAssertEqual(t.trailing, [.settings]); XCTAssertFalse(t.leading.contains(.settings))
        t.insert(.settings, in: .hidden); XCTAssertEqual(t.zone(of: .settings), .hidden)
        t.insert(.back, in: .leading, before: .back); XCTAssertEqual(t.zone(of: .back), .leading)
        // A layout saved before the incognito control existed gets it in its default place, next to settings.
        let old = #"{"leading":["back"],"trailing":[],"sidebar":["history","settings"],"addressWidth":500}"#
        let migrated = try JSONDecoder().decode(ToolbarLayout.self, from: Data(old.utf8))
        XCTAssertEqual(migrated.sidebar, [.history, .incognito, .settings])
        XCTAssertEqual(migrated.known, ToolbarControl.allCases)
        // Once known, removing it sticks.
        var removed = migrated; removed.insert(.incognito, in: .hidden)
        XCTAssertEqual(try JSONDecoder().decode(ToolbarLayout.self, from: JSONEncoder().encode(removed)).zone(of: .incognito), .hidden)
    }

    func testToolbarInnerZonesSitNextToTheAddress() throws {
        var t = ToolbarLayout()
        t.insert(.reload, in: .leadingInner)
        t.insert(.downloads, in: .trailingInner)
        XCTAssertEqual(t.zone(of: .reload), .leadingInner); XCTAssertFalse(t.leading.contains(.reload))
        XCTAssertEqual(t.zone(of: .downloads), .trailingInner); XCTAssertFalse(t.sidebar.contains(.downloads))
        t.insert(.back, in: .leadingInner, before: .reload)
        XCTAssertEqual(t.leadingInner, [.back, .reload])
        t.shift(.reload, by: -1); XCTAssertEqual(t.leadingInner, [.reload, .back])
        let decoded = try JSONDecoder().decode(ToolbarLayout.self, from: JSONEncoder().encode(t))
        XCTAssertEqual(decoded, t)
        // Layouts saved before the inner zones load with them empty.
        let old = try JSONDecoder().decode(ToolbarLayout.self, from: Data(#"{"leading":["back"],"trailing":["settings"],"sidebar":[],"addressWidth":500}"#.utf8))
        XCTAssertTrue(old.leadingInner.isEmpty && old.trailingInner.isEmpty)
        // A duplicate across zones keeps the first, edge before inner.
        let dup = try JSONDecoder().decode(ToolbarLayout.self, from: Data(#"{"leading":["back"],"leadingInner":["back","reload"],"trailingInner":["reload"]}"#.utf8))
        XCTAssertEqual(dup.leadingInner, [.reload]); XCTAssertTrue(dup.trailingInner.isEmpty)
        // Without a sidebar the toggle disappears from every zone.
        var top = ToolbarLayout(); top.insert(.sidebar, in: .trailingInner)
        XCTAssertFalse(top.resolved(sidebarAvailable: false).trailingInner.contains(.sidebar))
    }

    func testChromeStoreAddresses() {
        let id = "eimadpbcbfnmbkopoojfekhnkhdbieeh"
        XCTAssertEqual(ChromeStore.extensionID(from: "https://chromewebstore.google.com/detail/dark-reader/" + id), id)
        XCTAssertEqual(ChromeStore.extensionID(from: "chromewebstore.google.com/detail/dark-reader/\(id)?hl=ru"), id)
        XCTAssertEqual(ChromeStore.extensionID(from: "https://chrome.google.com/webstore/detail/x/" + id), id)
        XCTAssertEqual(ChromeStore.extensionID(from: " \(id) "), id)
        XCTAssertNil(ChromeStore.extensionID(from: "https://evil.example/detail/x/" + id))
        XCTAssertNil(ChromeStore.extensionID(from: "https://chromewebstore.google.com/category/extensions"))
        XCTAssertNil(ChromeStore.extensionID(from: "eimadpbcbfnmbkopoojfekhnkhdbiee1"))
        let url = ChromeStore.downloadURL(id: id)
        XCTAssertEqual(url.host, "clients2.google.com")
        XCTAssertTrue(url.absoluteString.contains("acceptformat=crx3"))
    }

    // MARK: CRX3

    /// Builds a CRX3 the way the store does: developer RSA key, signed header with the ID, ZIP payload.
    private func makeCRX(signWith signer: SecKey? = nil, idOverride: Data? = nil, zip: Data = Data([0x50, 0x4b, 3, 4, 1, 2, 3, 4])) throws -> (crx: Data, id: String) {
        let attributes: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits as String: 2048]
        var error: Unmanaged<CFError>?
        let key = try XCTUnwrap(SecKeyCreateRandomKey(attributes as CFDictionary, &error))
        let publicKey = try XCTUnwrap(SecKeyCopyPublicKey(key))
        let pkcs1 = try XCTUnwrap(SecKeyCopyExternalRepresentation(publicKey, nil)) as Data
        let spki = der(0x30, der(0x30, Data([0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00])) + der(0x03, Data([0]) + pkcs1))
        let idBytes = idOverride ?? Data(SHA256.hash(data: spki).prefix(16))
        let signed = field(1, idBytes)
        var message = Data("CRX3 SignedData".utf8); message.append(0)
        var length = UInt32(signed.count).littleEndian; message.append(Data(bytes: &length, count: 4)); message.append(signed); message.append(zip)
        let signature = try XCTUnwrap(SecKeyCreateSignature(signer ?? key, .rsaSignatureMessagePKCS1v15SHA256, message as CFData, nil)) as Data
        let header = field(2, field(1, spki) + field(2, signature)) + field(10000, signed)
        var crx = Data("Cr24".utf8)
        var version = UInt32(3).littleEndian, size = UInt32(header.count).littleEndian
        crx.append(Data(bytes: &version, count: 4)); crx.append(Data(bytes: &size, count: 4)); crx.append(header); crx.append(zip)
        return (crx, ChromeStore.id(forPublicKey: spki))
    }
    private func der(_ tag: UInt8, _ body: Data) -> Data {
        var out = Data([tag])
        if body.count < 128 { out.append(UInt8(body.count)) }
        else { let bytes = withUnsafeBytes(of: UInt32(body.count).bigEndian, Array.init).drop { $0 == 0 }; out.append(0x80 | UInt8(bytes.count)); out.append(contentsOf: bytes) }
        return out + body
    }
    private func field(_ number: Int, _ body: Data) -> Data {
        func varint(_ v: Int) -> Data { var v = v, out = Data(); repeat { var b = UInt8(v & 0x7f); v >>= 7; if v > 0 { b |= 0x80 }; out.append(b) } while v > 0; return out }
        return varint(number << 3 | 2) + varint(body.count) + body
    }

    func testCRXVerifiesSignatureAndID() throws {
        let zip = Data([0x50, 0x4b, 3, 4] + Array(repeating: 7, count: 64))
        let (crx, id) = try makeCRX(zip: zip)
        let package = try CRXPackage(crx)
        XCTAssertEqual(package.crxID, id)
        XCTAssertEqual(package.archive, zip)
        XCTAssertNoThrow(try package.verify(expectedID: id))
        XCTAssertThrowsError(try package.verify(expectedID: String(repeating: "a", count: 32))) { XCTAssertEqual($0 as? CRXError, .idMismatch(expected: String(repeating: "a", count: 32), found: id)) }
        // A changed payload no longer matches the signature.
        var tampered = crx; tampered[tampered.count - 1] ^= 0xff
        XCTAssertThrowsError(try CRXPackage(tampered).verify(expectedID: id)) { XCTAssertEqual($0 as? CRXError, .badSignature) }
    }

    func testCRXRejectsForeignKeyAndDamagedFiles() throws {
        let other = try XCTUnwrap(SecKeyCreateRandomKey([kSecAttrKeyType as String: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits as String: 2048] as CFDictionary, nil))
        let (forged, id) = try makeCRX(signWith: other)
        XCTAssertThrowsError(try CRXPackage(forged).verify(expectedID: id)) { XCTAssertEqual($0 as? CRXError, .badSignature) }
        // The header names an ID that no included key produces.
        let (mismatch, _) = try makeCRX(idOverride: Data(repeating: 0, count: 16))
        let package = try CRXPackage(mismatch)
        XCTAssertEqual(package.crxID, String(repeating: "a", count: 32))
        XCTAssertThrowsError(try package.verify(expectedID: package.crxID)) { XCTAssertEqual($0 as? CRXError, .badSignature) }
        XCTAssertThrowsError(try CRXPackage(Data("PK\u{3}\u{4}zip".utf8))) { XCTAssertEqual($0 as? CRXError, .notCRX) }
        var v2 = Data("Cr24".utf8); v2.append(contentsOf: [2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
        XCTAssertThrowsError(try CRXPackage(v2)) { XCTAssertEqual($0 as? CRXError, .unsupportedVersion(2)) }
        var truncated = Data("Cr24".utf8); truncated.append(contentsOf: [3, 0, 0, 0, 0xff, 0xff, 0, 0, 1, 2])
        XCTAssertThrowsError(try CRXPackage(truncated)) { XCTAssertEqual($0 as? CRXError, .malformed) }
    }

    /// Optional check against a package downloaded from the store: MICA_CRX=/path/file.crx MICA_CRX_ID=<id> swift test
    func testRealStorePackageWhenProvided() throws {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["MICA_CRX"], let id = env["MICA_CRX_ID"] else { throw XCTSkip("no store package given") }
        let package = try CRXPackage(Data(contentsOf: URL(fileURLWithPath: path)))
        XCTAssertGreaterThanOrEqual(package.proofs.count, 1)
        XCTAssertNoThrow(try package.verify(expectedID: id))
    }

    /// Every authored Russian string has an English variant. Reads the app sources next to this package.
    func testEveryInterfaceStringHasEnglish() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let folder = root.appendingPathComponent("Sources/MicaApp")
        let files = (FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "swift" }
        XCTAssertGreaterThan(files.count, 20, "app sources not found under " + folder.path)
        let pattern = try NSRegularExpression(pattern: #"(?:text|item)\((?:[a-z]+, )?"((?:[^"\\]|\\.)*)", "((?:[^"\\]|\\.)*)""#)
        var missing = Set<String>()
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            for match in pattern.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
                let regular = String(source[Range(match.range(at: 2), in: source)!])
                guard regular.range(of: #"\p{Cyrillic}"#, options: .regularExpression) != nil, !regular.contains("\\(") else { continue }
                if English.table[regular] == nil { missing.insert(regular) }
            }
        }
        XCTAssertTrue(missing.isEmpty, "no English for:\n" + missing.sorted().joined(separator: "\n"))
    }

    func testClearPeriodsAndHistoryGrouping() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(ClearPeriod.hour.start(before: now), now.addingTimeInterval(-3600))
        XCTAssertEqual(ClearPeriod.month.start(before: now), now.addingTimeInterval(-28 * 86_400))
        XCTAssertEqual(ClearPeriod.all.start(before: now), .distantPast)
        func visit(_ url: String, _ ago: TimeInterval) -> Visit { var v = Visit(url: URL(string: url)!, title: ""); v.date = now.addingTimeInterval(-ago); return v }
        let visits = [visit("https://a.com", 60), visit("https://www.b.com/x", 7200), visit("https://b.com", 3 * 86_400), visit("https://c.com", 40 * 86_400)]
        XCTAssertEqual(History.count(visits, since: ClearPeriod.hour.start(before: now)), 1)
        XCTAssertEqual(History.removing(visits, since: ClearPeriod.day.start(before: now)).map(\.url.host), ["b.com", "c.com"])
        XCTAssertEqual(History.removing(visits, since: ClearPeriod.all.start(before: now)), [])
        XCTAssertEqual(History.removing(visits, host: "b.com").map(\.url.host), ["a.com", "c.com"])
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "UTC")!
        let days = History.days(visits.reversed(), calendar: calendar)
        XCTAssertEqual(days.map(\.visits.count), [2, 1, 1])
        XCTAssertEqual(days.first?.visits.first?.url.host, "a.com")
        var choice = ClearChoice(); choice.history = false; choice.cache = false
        XCTAssertTrue(choice.isEmpty)
        let old = try JSONDecoder().decode(Preferences.self, from: Data(#"{"layout":"left"}"#.utf8))
        XCTAssertEqual(old.clearing, ClearChoice())
        let partial = try JSONDecoder().decode(ClearChoice.self, from: Data(#"{"period":"week","siteData":true}"#.utf8))
        XCTAssertEqual(partial.period, .week); XCTAssertTrue(partial.siteData); XCTAssertTrue(partial.history)
    }
}

final class WebNotificationTests: XCTestCase {
    func testParseRejectsUntrustedShapes() {
        XCTAssertNil(WebNotification.parse(["id": "1"]))
        XCTAssertNil(WebNotification.parse(["id": "a b", "title": "x"]))
        XCTAssertNil(WebNotification.parse(["id": "1", "title": "   "]))
        XCTAssertNil(WebNotification.parse(["id": String(repeating: "a", count: 65), "title": "x"]))
        let long = WebNotification.parse(["id": "n-1", "title": String(repeating: "т", count: 500), "body": "a\u{0007}b", "silent": true])
        XCTAssertEqual(long?.title.count, WebNotification.titleLimit)
        XCTAssertEqual(long?.body, "ab")
        XCTAssertEqual(long?.silent, true)
    }
    func testStateFollowsDecisionsAndRefusesIncognitoAndHTTP() {
        let records = [SitePermission(origin: "https://mail.example", capability: .notifications, decision: .allow),
                       SitePermission(origin: "https://spam.example", capability: .notifications, decision: .deny),
                       SitePermission(origin: "https://cam.example", capability: .camera, decision: .allow)]
        XCTAssertEqual(NotificationPolicy.state(origin: "https://mail.example", privateMode: false, permissions: records), .granted)
        XCTAssertEqual(NotificationPolicy.state(origin: "https://mail.example", privateMode: true, permissions: records), .denied)
        XCTAssertEqual(NotificationPolicy.state(origin: "https://spam.example", privateMode: false, permissions: records), .denied)
        XCTAssertEqual(NotificationPolicy.state(origin: "https://cam.example", privateMode: false, permissions: records), .default)
        XCTAssertEqual(NotificationPolicy.state(origin: "http://mail.example", privateMode: false, permissions: records), .denied)
        XCTAssertFalse(NotificationPolicy.mayAsk(origin: "https://a.example", privateMode: false, selected: true, userGesture: false, requestsAllowed: true))
        XCTAssertFalse(NotificationPolicy.mayAsk(origin: "https://a.example", privateMode: false, selected: false, userGesture: true, requestsAllowed: true))
        XCTAssertFalse(NotificationPolicy.mayAsk(origin: "https://a.example", privateMode: false, selected: true, userGesture: true, requestsAllowed: false))
        XCTAssertTrue(NotificationPolicy.mayAsk(origin: "https://a.example", privateMode: false, selected: true, userGesture: true, requestsAllowed: true))
    }
    func testTaggedNotificationsReplaceEachOther() {
        let tab = UUID()
        let a = NotificationPolicy.identifier(origin: "https://a.example", tab: tab, notification: WebNotification(id: "1", title: "x", tag: "chat"))
        let b = NotificationPolicy.identifier(origin: "https://a.example", tab: UUID(), notification: WebNotification(id: "2", title: "y", tag: "chat"))
        let c = NotificationPolicy.identifier(origin: "https://a.example", tab: tab, notification: WebNotification(id: "3", title: "z"))
        XCTAssertEqual(a, b); XCTAssertNotEqual(a, c)
    }
}
