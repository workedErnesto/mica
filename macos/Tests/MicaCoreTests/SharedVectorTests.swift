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
        case "blockingExceptions": return BlockingRules.matchingExceptions(host: c["host"] as! String, exceptions: c["exceptions"] as! [String])
        case "navigation": return URL(string: c["url"] as! String).map { AddressParser.navigable($0, mainFrame: c["mainFrame"] as! Bool) } ?? false
        case "origin": return Origin.string(URL(string: c["url"] as! String)) ?? NSNull()
        case "localFile": return URL(string: c["url"] as! String).map(AddressParser.openableFile) ?? false
        case "externalScheme": return URL(string: c["url"] as! String).map(AddressParser.external) ?? false
        case "appLinkAllowed":
            let list = (c["allowed"] as! [[String]]).map { AppLinkPermission(origin: $0[0], scheme: $0[1]) }
            return URL(string: c["url"] as! String).map { AppLinkPermission.allows(list, origin: c["origin"] as? String, url: $0) } ?? false
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
        case "addressDisplay":
            // Quieter parts are marked with a leading ~.
            let style = AddressStyle(full: c["full"] as? Bool ?? false, dimSubdomain: c["dimSubdomain"] as? Bool ?? false, dimPath: c["dimPath"] as? Bool ?? false)
            return AddressDisplay.parts(c["url"] as! String, style: style).map { ($0.dim ? "~" : "") + $0.text }
        case "faviconRemote": return FaviconDiscovery.remoteURL(page: c["page"] as! String) ?? NSNull()
        case "faviconCatalog": return FaviconDiscovery.bundledFile(page: c["page"] as! String) ?? NSNull()
        case "faviconDiscovery":
            return FaviconDiscovery.candidates(FaviconDiscovery.links(html: c["html"] as! String, page: c["page"] as! String).filter { $0.dark == (c["dark"] as? Bool ?? false) }, page: c["page"] as! String, fallback: c["fallback"] as? Bool ?? true)
        case "faviconTone":
            // "ink" when the glyph is redrawn in the shell's ink, "keep" when its own colour reads, "image" for icons that are not a glyph.
            let pixels = (c["pixels"] as! String).split(separator: " ").flatMap { token -> [UInt8] in
                let value = UInt32(token, radix: 16)!
                return [UInt8(value >> 24), UInt8((value >> 16) & 0xff), UInt8((value >> 8) & 0xff), UInt8(value & 0xff)]
            }
            guard let glyph = FaviconTone.glyph(rgba: pixels) else { return "image" }
            return FaviconTone.needsInk(glyph: glyph, background: HexColor.luminance(c["background"] as! String)!) ? "ink" : "keep"
        case "pageFileName": return PageExport.fileName(title: c["title"] as! String, url: c["url"] as? String, format: PageFormat(rawValue: c["format"] as! String)!)
        case "pageImage":
            guard let size = PageExport.imagePixels(width: (c["width"] as! NSNumber).doubleValue, height: (c["height"] as! NSNumber).doubleValue, scale: (c["scale"] as! NSNumber).doubleValue) else { return NSNull() }
            return [size.width, size.height]
        case "availableName":
            let taken = Set(c["taken"] as! [String])
            return PageExport.availableName(c["name"] as! String, taken: taken.contains)
        case "webAddress": return WebAddress.resolve(c["ref"] as! String, against: c["base"] as! String) ?? NSNull()
        case "singleFilePage":
            let resources = (c["resources"] as! [[String: String]]).map { r in
                PageResource(url: r["url"]!, mime: r["mime"]!, data: r["text"].map { Data($0.utf8) } ?? Data(base64Encoded: r["base64"]!)!)
            }
            return SingleFilePage.build(html: c["html"] as! String, base: c["base"] as! String, resources: resources)
        case "profileGlyph": return Profiles.lightGlyph(on: c["hex"] as! String, glyph: ProfileGlyph(rawValue: c["glyph"] as? String ?? "auto") ?? .auto) ? "light" : "dark"
        case "passwordOffer":
            // Saved logins carry seconds since 2026 for their update and last use, so the order is defined.
            var vault = Vault()
            vault.never = c["never"] as? [String] ?? []
            for item in c["logins"] as! [[String: Any]] {
                var login = SavedLogin(origin: item["origin"] as! String, username: item["username"] as! String, password: "p", created: Date(timeIntervalSince1970: 1_767_225_600))
                login.updated = Date(timeIntervalSince1970: 1_767_225_600 + (item["updated"] as! NSNumber).doubleValue)
                login.used = (item["used"] as? NSNumber).map { Date(timeIntervalSince1970: 1_767_225_600 + $0.doubleValue) }
                vault.logins.append(login)
            }
            switch PasswordOffer.decide(vault: vault, origin: c["origin"] as! String, isNew: c["new"] as! Bool, maxLength: c["max"] as! Int,
                                        offerPasswords: c["offerPasswords"] as? Bool ?? true, fillPasswords: c["fillPasswords"] as? Bool ?? true) {
            case nil: return "none"
            case .generate: return "generate"
            case .fill(let logins): return "fill:" + logins.map(\.username).joined(separator: ",")
            }
        case "passwordOfferSession":
            // Events as "focus:1", "click:1", "input:1", "blur:1", "dismiss", "accept", "leave"; visibility after each.
            var session = PasswordOfferSession()
            return (c["events"] as! [String]).map { text -> Bool in
                let parts = text.split(separator: ":"), id = parts.count > 1 ? Int(parts[1])! : 0
                switch parts[0] {
                case "focus": session.apply(.focus(id))
                case "click": session.apply(.click(id))
                case "input": session.apply(.input(id))
                case "blur": session.apply(.blur(id))
                case "dismiss": session.apply(.dismiss)
                case "accept": session.apply(.accept)
                default: session.apply(.leave)
                }
                return session.visible
            }
        case "passwordOfferPlace":
            func size(_ key: String) -> CGSize { let v = (c[key] as! [NSNumber]).map(\.doubleValue); return CGSize(width: v[0], height: v[1]) }
            let f = (c["field"] as! [NSNumber]).map(\.doubleValue)
            let view = size("view")
            let field = PasswordOfferPlacement.viewRect(css: CGRect(x: f[0], y: f[1], width: f[2], height: f[3]), innerWidth: (c["innerWidth"] as! NSNumber).doubleValue, viewWidth: view.width)
            guard let placed = PasswordOfferPlacement.place(field: field, bounds: view, panel: size("panel"), gap: (c["gap"] as! NSNumber).doubleValue, margin: (c["margin"] as! NSNumber).doubleValue) else { return NSNull() }
            let r = placed.frame
            return [Double(r.minX), Double(r.minY), Double(r.width), Double(r.height), placed.edge.rawValue] as [Any]
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
