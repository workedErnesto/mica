import XCTest
@testable import MicaCore

final class ProfileTests: XCTestCase {
    func testLegacyPreferencesBecomeTheStandardProfile() throws {
        var old = Preferences()
        old.layout = .right; old.theme = .custom; old.accent = "#3E7BFA"; old.userName = "Алекс"; old.start.frequentCount = 12; old.sidebarCollapsed = true
        let data = try JSONEncoder().encode(old)
        let look = try JSONDecoder().decode(ProfileLook.self, from: data)
        let profiles = Profiles.normalized([], fallback: look)
        XCTAssertEqual(profiles.count, 1)
        XCTAssertTrue(profiles[0].isStandard)
        XCTAssertEqual(profiles[0].look.applied(to: Preferences()).layout, .right)
        XCTAssertEqual(profiles[0].look.accent, "#3E7BFA")
        XCTAssertEqual(profiles[0].look.userName, "Алекс")
        XCTAssertEqual(profiles[0].look.start.frequentCount, 12)
        XCTAssertTrue(profiles[0].look.sidebarCollapsed)
    }
    func testLookOverlaysOnlyItsOwnPart() {
        var global = Preferences(); global.search = .kagi; global.language = .en; global.lowercase = true; global.theme = .dark
        var look = ProfileLook(); look.theme = .light; look.layout = .top; look.language = .ru; look.lowercase = false
        let effective = look.applied(to: global)
        XCTAssertEqual(effective.search, .kagi); XCTAssertEqual(effective.language, .ru); XCTAssertFalse(effective.lowercase)
        XCTAssertEqual(effective.theme, .light); XCTAssertEqual(effective.layout, .top)
        XCTAssertEqual(ProfileLook(effective), look)
    }
    func testProfilesSavedWithoutLanguageTakeTheApplicationOne() throws {
        let old = ##"[{"id":"\##(UUID().uuidString)","name":"Работа","icon":"briefcase","background":"#3E7BFA","look":{"theme":"dark"},"pinned":[]}]"##
        let decoded = try JSONDecoder().decode([Profile].self, from: Data(old.utf8))
        XCTAssertNil(decoded[0].look.language); XCTAssertNil(decoded[0].look.lowercase)
        var global = Preferences(); global.language = .en; global.lowercase = false
        let profiles = Profiles.normalized(decoded, fallback: ProfileLook(global))
        XCTAssertEqual(profiles.map { $0.look.language }, [Language.en, Language.en]); XCTAssertEqual(profiles.map { $0.look.lowercase }, [false, false])
        var own = profiles[1]; own.look.language = Language.ru
        let again = try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(own))
        XCTAssertEqual(again.look.language, Language.ru); XCTAssertEqual(again.look.lowercase, Bool?.some(false))
    }
    func testProfileRoundTripAndRepair() throws {
        var look = ProfileLook(); look.transparency = 0.2
        let profile = Profile(name: "Работа", icon: "briefcase", background: "#3e7bfa", look: look, pinned: [SavedTab(url: URL(string: "https://mail.example.com"), title: "mail", pinned: true)])
        let decoded = try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(profile))
        XCTAssertEqual(decoded.name, "Работа"); XCTAssertEqual(decoded.background, "#3E7BFA"); XCTAssertEqual(decoded.look.transparency, 0.2); XCTAssertEqual(decoded.pinned.count, 1)
        let broken = #"{"id":"\#(UUID().uuidString)","name":"  x  ","icon":"no.such.symbol","background":"red","pinned":[{"id":"\#(UUID().uuidString)","url":"javascript:alert(1)","title":"","pinned":true}]}"#
        let repaired = try JSONDecoder().decode(Profile.self, from: Data(broken.utf8))
        XCTAssertEqual(repaired.name, "x"); XCTAssertEqual(repaired.icon, ProfileCatalog.standardIcon); XCTAssertEqual(repaired.background, ProfileCatalog.standardBackground)
        XCTAssertTrue(repaired.pinned.isEmpty); XCTAssertEqual(repaired.look, ProfileLook())
    }
    func testStandardProfileCannotBeRemovedAndStaysFirst() {
        let work = Profile(name: "work", icon: "briefcase", background: "#3E7BFA")
        let list = Profiles.normalized([work, .standard(), work])
        XCTAssertEqual(list.map(\.id), [Profile.standardID, work.id])
        XCTAssertEqual(Profiles.removing(Profile.standardID, from: list).count, 2)
        XCTAssertEqual(Profiles.removing(work.id, from: list).map(\.id), [Profile.standardID])
        XCTAssertEqual(Profiles.resolve(work.id, in: [.standard()]).id, Profile.standardID)
    }
    func testNewProfilesTakeUnusedIconAndBackground() {
        let first = Profiles.next(after: [.standard()], name: " Учёба ", look: ProfileLook())
        XCTAssertEqual(first.name, "Учёба")
        XCTAssertNotEqual(first.icon, ProfileCatalog.standardIcon)
        XCTAssertNotEqual(first.background, ProfileCatalog.standardBackground)
        XCTAssertTrue(ProfileCatalog.icons.contains(first.icon)); XCTAssertTrue(ProfileCatalog.backgrounds.contains(first.background))
    }
    func testNewProfileKeepsLookButNotTheSourceSites() {
        var look = ProfileLook(); look.theme = .dark; look.layout = .top
        look.start.shortcuts = [StartShortcut(title: "mail", url: URL(string: "https://mail.example.com")!)]; look.start.hiddenHosts = ["news.example.com"]
        let profile = Profiles.next(after: [.standard()], name: "x", look: look)
        XCTAssertEqual(profile.look.theme, .dark); XCTAssertEqual(profile.look.layout, .top)
        XCTAssertTrue(profile.look.start.shortcuts.isEmpty); XCTAssertTrue(profile.look.start.hiddenHosts.isEmpty)
        XCTAssertTrue(profile.pinned.isEmpty)
    }
    func testProfileOpeningDefaultsToAskAndRoundTrips() throws {
        XCTAssertEqual(Preferences().profileOpening, .ask)
        XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8)).profileOpening, .ask)
        XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: Data(#"{"profileOpening":"sideways"}"#.utf8)).profileOpening, .ask)
        var p = Preferences(); p.profileOpening = .newWindow
        let data = try JSONEncoder().encode(p)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"newWindow\""))
        XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: data).profileOpening, .newWindow)
    }
    func testVisitsWithoutProfileBelongToStandard() throws {
        let legacy = try JSONDecoder().decode(Visit.self, from: Data(#"{"id":"\#(UUID().uuidString)","url":"https://example.com","title":"","date":0}"#.utf8))
        XCTAssertNil(legacy.profile); XCTAssertEqual(Profiles.owner(of: legacy), Profile.standardID)
        let work = UUID()
        XCTAssertEqual(Profiles.owner(of: Visit(url: URL(string: "https://example.com")!, title: "", profile: work)), work)
    }
    func testSessionKeepsWindowProfile() {
        let id = UUID()
        let window = SavedWindow(tabs: [SavedTab(url: URL(string: "https://example.com"))], selected: nil, profile: id)
        XCTAssertEqual(Session(windows: [window]).validated().windows[0].profile, id)
    }
    func testNewToolbarControlAppearsInSidebarOfOldLayouts() throws {
        let old = #"{"leading":["sidebar","back"],"sidebar":["bookmarks","settings"],"known":["sidebar","back","forward","reload","newTab","bookmarks","history","downloads","extensions","incognito","settings"]}"#
        let layout = try JSONDecoder().decode(ToolbarLayout.self, from: Data(old.utf8))
        XCTAssertEqual(layout.zone(of: .profile), .sidebar)
        XCTAssertEqual(layout.sidebar.first, .profile)
    }
}
