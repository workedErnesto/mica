import XCTest
@testable import MicaCore

/// Behaviour shared with Windows. Expectations come from this implementation (MICA_WRITE_VECTORS=1 fills them);
/// windows/tests/Mica.Core.Tests checks the same file, so the two cores cannot drift apart silently.
final class SharedVectorTests: XCTestCase {
    static let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../shared/fixtures/core/vectors.json").standardizedFileURL

    func actual(_ section: String, _ c: [String: Any]) -> Any {
        func engine() -> SearchEngine { SearchEngine(rawValue: c["engine"] as? String ?? "") ?? .duckduckgo }
        switch section {
        case "address":
            switch AddressParser.resolve(c["input"] as! String, engine: engine()) {
            case .web(let url): return "web:" + url.absoluteString
            case .external(let url): return "external:" + url.absoluteString
            case .rejected(let reason): return "rejected:" + reason
            }
        case "origin": return Origin.string(URL(string: c["url"] as! String)) ?? NSNull()
        case "localFile": return URL(string: c["url"] as! String).map(AddressParser.openableFile) ?? false
        case "version":
            guard let a = AppVersion(c["a"] as! String), let b = AppVersion(c["b"] as! String) else { return "invalid" }
            return a < b ? -1 : a > b ? 1 : 0
        case "checksum": return UpdatePolicy.parseChecksum(c["text"] as! String) ?? NSNull()
        case "filename": return DownloadSafety.filename(c["name"] as! String)
        case "downloadKind": return DownloadKind.of(c["name"] as! String).rawValue
        case "copy": return Copy.text(c["low"] as! String, c["regular"] as! String, lowercase: c["lowercase"] as! Bool, language: Language(rawValue: c["language"] as! String)!)
        case "greeting":
            var p = Preferences(); p.userName = c["name"] as! String; p.greetByName = c["greet"] as! Bool; p.language = Language(rawValue: c["language"] as! String)!; p.lowercase = c["lowercase"] as! Bool
            return Greeting.text(p, hour: c["hour"] as! Int, seed: c["seed"] as! Int) ?? NSNull()
        case "period":
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            let start = ClearPeriod(rawValue: c["period"] as! String)!.start(before: now)
            return start == .distantPast ? NSNull() : Int(now.timeIntervalSince(start))
        case "notification":
            guard let n = WebNotification.parse(c) else { return NSNull() }
            return ["title": n.title, "body": n.body, "tag": n.tag, "silent": n.silent]
        case "chromeId": return ChromeStore.extensionID(from: c["input"] as! String) ?? NSNull()
        case "luminance": return HexColor.luminance(c["hex"] as! String).map { (($0 * 10000).rounded() / 10000) } ?? NSNull()
        case "shortcut": return StartPage.shortcutURL(c["input"] as! String, engine: engine())?.absoluteString ?? NSNull()
        case "profileName": return Profiles.name(c["input"] as! String)
        case "profileNext":
            let list = zip(c["icons"] as! [String], c["backgrounds"] as! [String]).map { Profile(name: "x", icon: $0, background: $1) }
            let next = Profiles.next(after: list, name: "", look: ProfileLook())
            return ["icon": next.icon, "background": next.background]
        case "profileText":
            // A profile without its own language or case takes the application-wide ones.
            var look = ProfileLook(); look.language = (c["lookLanguage"] as? String).flatMap(Language.init(rawValue:)); look.lowercase = c["lookLowercase"] as? Bool
            var global = Preferences(); global.language = Language(rawValue: c["language"] as! String)!; global.lowercase = c["lowercase"] as! Bool
            let p = look.applied(to: global)
            return p.language.rawValue + (p.lowercase ? "-low" : "-regular")
        case "profileGlyph": return Profiles.lightGlyph(on: c["hex"] as! String, glyph: ProfileGlyph(rawValue: c["glyph"] as? String ?? "auto") ?? .auto) ? "light" : "dark"
        default: XCTFail("unknown section \(section)"); return NSNull()
        }
    }

    func testSharedVectors() throws {
        var root = try JSONSerialization.jsonObject(with: Data(contentsOf: Self.file)) as! [String: Any]
        let write = ProcessInfo.processInfo.environment["MICA_WRITE_VECTORS"] == "1"
        for (section, value) in root where !section.hasPrefix("$") {
            var cases = value as! [[String: Any]]
            for index in cases.indices {
                let got = actual(section, cases[index])
                if write { cases[index]["expect"] = got; continue }
                guard let expected = cases[index]["expect"] else { XCTFail("\(section)[\(index)] has no expect; run with MICA_WRITE_VECTORS=1"); continue }
                XCTAssertEqual(NSDictionary(dictionary: ["v": got]), NSDictionary(dictionary: ["v": expected]), "\(section)[\(index)] \(cases[index])")
            }
            root[section] = cases
        }
        if write {
            let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            try data.write(to: Self.file)
        }
    }
}
