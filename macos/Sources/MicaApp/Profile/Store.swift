import AppKit
import SwiftUI
import WebKit
import Combine
import CryptoKit
import MicaCore

@MainActor
final class Store: ObservableObject {
    static let shared = Store()
    let root: URL
    lazy var websiteDataStore: WKWebsiteDataStore = ProcessInfo.processInfo.arguments.contains("--qa") ? WKWebsiteDataStore(forIdentifier: UUID(uuidString: "4931E497-3225-4DAD-A8E3-87D4038B84EE")!) : .default()
    /// Application-wide preferences. The part a profile owns (ProfileLook) is read through `prefs(for:)`; its copy here
    /// only seeds the standard profile when preferences from a build before profiles are first loaded.
    @Published var preferences: Preferences { didSet { schedulePreferences(); if oldValue.appIcon != preferences.appIcon { AppIcons.apply(preferences.appIcon); flushPreferences(); AppIcons.announce(preferences.appIcon) }; if oldValue.blocking != preferences.blocking || oldValue.blockingExceptions != preferences.blockingExceptions { Task { await blocker.rebuild() } }; if oldValue.blocking != preferences.blocking { Task { await ublock.startBuiltin() } } else if oldValue.blockingExceptions != preferences.blockingExceptions { Task { await ublock.rebuild() } } } }
    /// The standard profile first. Each window shows one of them; deleting a profile moves its windows to the standard one.
    @Published var profiles: [Profile] { didSet { scheduleProfiles(); for window in windows { window.applyProfile() }; updateTextStyle() } }
    /// Language and case of text that belongs to no window (the menu bar, alerts without a window, extension and update
    /// messages): those of the profile of the window in front. A window's own text follows its profile (`BrowserModel.text`).
    @Published private(set) var textStyle = TextStyle(language: .ru, lowercase: true)
    @Published var bookmarks: [Visit] { didSet { save(bookmarks, "bookmarks.json") } }
    @Published var history: [Visit] { didSet { save(history, "history.json") } }
    @Published var permissions: [SitePermission] { didSet { save(permissions, "permissions.json") } }
    @Published var downloadRecords: [DownloadRecord] { didSet { save(downloadRecords, "downloads.json") } }
    /// A problem to tell the user. Shown once in the window in front, or in the first window when it opens.
    @Published var issue: String?
    func presentIssue() {
        guard let text = issue, let browser = active else { return }
        issue = nil
        browser.inform(text)
    }
    /// Text typed in a settings field but not yet added; closing settings asks before discarding it.
    @Published var settingsDraft = ""
    var windows: [BrowserWindow] = []
    lazy var blocker = Blocker(store: self)
    lazy var ublock = UBlockEngine(store: self)
    lazy var extensions = ExtensionManager(store: self)
    lazy var importer = ImportManager(store: self)
    lazy var updater = Updater(store: self)
    lazy var passwords = Passwords(store: self)
    lazy var notifier = Notifier(store: self)
    /// Site icons of normal windows; incognito windows keep their own (BrowserModel.favicons).
    lazy var favicons = Favicons(persistent: true)
    var sessionWork: DispatchWorkItem?
    var preferencesWork: DispatchWorkItem?
    var profilesWork: DispatchWorkItem?
    var shuttingDown = false
    private var unreadableFiles = Set<String>()
    var active: BrowserModel? { windows.first(where: { $0.window?.isKeyWindow == true })?.model ?? windows.last?.model }
    init() {
        let appRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("mica", isDirectory: true)
        let storageRoot = ProcessInfo.processInfo.arguments.contains("--qa") ? appRoot.appendingPathComponent("QA", isDirectory: true) : appRoot
        root = storageRoot
        try? FileManager.default.createDirectory(at: storageRoot, withIntermediateDirectories: true)
        var loadIssues: [String] = []
        func read<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
            let url = storageRoot.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            do { return try Persistence.read(type, at: url) }
            catch {
                let backup = storageRoot.appendingPathComponent("Recovery", isDirectory: true)
                try? FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
                try? FileManager.default.copyItem(at: url, to: backup.appendingPathComponent(UUID().uuidString + "-" + name))
                loadIssues.append(name + ": " + error.localizedDescription)
                return nil
            }
        }
        downloadRecords = read([DownloadRecord].self, "downloads.json") ?? []
        let loaded = read(Preferences.self, "preferences.json") ?? Preferences()
        preferences = loaded
        profiles = Profiles.normalized(read([Profile].self, "profiles.json") ?? [], fallback: ProfileLook(loaded))
        bookmarks = read([Visit].self, "bookmarks.json") ?? []
        history = read([Visit].self, "history.json") ?? []
        permissions = read([SitePermission].self, "permissions.json") ?? []
        textStyle = TextStyle(Profiles.resolve(nil, in: profiles).look.applied(to: loaded))
        unreadableFiles = Set(loadIssues.map { String($0.prefix { $0 != ":" }) })
        if !loadIssues.isEmpty { issue = "mica: " + loadIssues.joined(separator: "\n") }
        if ProcessInfo.processInfo.arguments.contains("--qa") { preferences.onboardingComplete = true; preferences.restore = false }
        // The first launch with profiles writes the standard profile made from the old preferences.
        if !FileManager.default.fileExists(atPath: storageRoot.appendingPathComponent("profiles.json").path) { save(profiles, "profiles.json") }
    }
    func text(_ low: String, _ regular: String) -> String { textStyle.text(low, regular) }
    var language: Language { textStyle.language }
    var lowercase: Bool { textStyle.lowercase }
    /// Called when another window comes in front or a profile changes.
    func updateTextStyle() {
        let style = TextStyle(prefs(for: active?.profileID))
        if style != textStyle { textStyle = style }
    }
    func capabilityName(_ capability: SiteCapability) -> String {
        switch capability {
        case .camera: return text("камера", "Камера")
        case .microphone: return text("микрофон", "Микрофон")
        case .notifications: return text("уведомления", "Уведомления")
        }
    }
    var locale: Locale { textStyle.locale }
    func save<T: Encodable>(_ value: T, _ name: String) {
        guard !unreadableFiles.contains(name) else { return }
        do { try Persistence.write(value, at: root.appendingPathComponent(name)) } catch { issue = text("не удалось сохранить данные: ", "Не удалось сохранить данные: ") + error.localizedDescription }
    }
    func schedulePreferences() {
        preferencesWork?.cancel()
        let work = DispatchWorkItem { [weak self] in guard let self else { return }; self.save(self.preferences, "preferences.json") }
        preferencesWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }
    func flushPreferences() { preferencesWork?.cancel(); save(preferences, "preferences.json"); profilesWork?.cancel(); save(profiles, "profiles.json") }
    /// Dragging a colour or the sidebar edge changes a profile many times a second; the file is written once it settles.
    func scheduleProfiles() {
        profilesWork?.cancel()
        let work = DispatchWorkItem { [weak self] in guard let self else { return }; self.save(self.profiles, "profiles.json") }
        profilesWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }
    func profile(_ id: UUID?) -> Profile { Profiles.resolve(id, in: profiles) }
    /// A name inside authored text: «…» in Russian, “…” in English.
    func quoted(_ text: String) -> String { textStyle.quoted(text) }
    func profileName(_ profile: Profile) -> String { textStyle.profileName(profile) }
    /// Preferences in effect for a window of this profile: the application-wide ones with the profile's look over them.
    func prefs(for id: UUID?) -> Preferences { profile(id).look.applied(to: preferences) }
    /// Splits an edited copy back: the profile's part goes to the profile, the rest to the application-wide preferences.
    func setPrefs(_ value: Preferences, for id: UUID?) {
        let look = ProfileLook(value)
        let global = ProfileLook(preferences).applied(to: value)
        if global != preferences { preferences = global }
        let target = profile(id).id
        if let index = profiles.firstIndex(where: { $0.id == target }), profiles[index].look != look { profiles[index].look = look }
    }
    func updateProfile(_ id: UUID, _ change: (inout Profile) -> Void) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        var copy = profiles[index]; change(&copy)
        copy.name = Profiles.name(copy.name)
        if copy.name.isEmpty && !copy.isStandard { return }
        if copy != profiles[index] { profiles[index] = copy }
    }
    /// A new profile starts from the look of the profile it was created from, with its own name, icon and background.
    @discardableResult func addProfile(from source: UUID?) -> Profile {
        let base = profile(source)
        let number = profiles.count + 1
        let profile = Profiles.next(after: profiles, name: text("профиль ", "Профиль ") + String(number), look: base.look)
        profiles.append(profile)
        return profile
    }
    /// Windows of a removed profile move to the standard one. History keeps the mark of the removed profile.
    func removeProfile(_ id: UUID) {
        guard id != Profile.standardID else { return }
        for window in windows where window.model.profileID == id { window.model.switchProfile(to: Profile.standardID) }
        profiles = Profiles.removing(id, from: profiles)
    }
    /// A window of this profile is brought forward, or a new one opens.
    func openProfile(_ id: UUID, newWindow forceNew: Bool = false) {
        if !forceNew, let window = windows.last(where: { $0.model.profileID == id && !$0.model.privateMode }) { window.showWindow(nil); NSApp.activate(ignoringOtherApps: true); return }
        _ = newWindow(profile: id)
    }
    /// Light or dark mode in effect: the custom theme brings its own base.
    static func appearanceMode(_ p: Preferences) -> Theme { p.theme == .custom ? p.customBase : p.theme }
    /// Each window sets its own appearance from its profile, so the application keeps the system one.
    func applyAppearance() { NSApp.appearance = nil }
    /// Opacity of the shell tint over the blur: 0.92 at zero transparency, 0.2 at full.
    static func glassTint(_ p: Preferences) -> Double { 0.92 - p.transparency * 0.72 }
    /// Opacity of the start page fill over the glass: opaque at zero transparency, 0.45 at full. It stays denser than
    /// the shell tint, so the start page still reads as the card. Web pages are never made transparent.
    static func startTint(_ p: Preferences) -> Double { 1 - p.transparency * 0.55 }
    /// The shell shows the frosted material: chosen in settings and not overridden by Reduce Transparency or Increase Contrast.
    static func glass(_ p: Preferences, reduceTransparency: Bool, contrast: ColorSchemeContrast) -> Bool {
        p.frosted && !reduceTransparency && contrast != .increased
    }
    /// Look of the window a menu or popover hangs from.
    func look(for window: NSWindow?) -> Look { Look(windows.first { $0.window === window }?.model.prefs ?? prefs(for: active?.profileID)) }
    func start() async {
        applyAppearance()
        AppIcons.apply(preferences.appIcon)
        AppIcons.announce(preferences.appIcon)
        // Left by builds that wrote the icon onto the bundle through a picked-file bookmark.
        UserDefaults.standard.removeObject(forKey: "bundleIconBookmark")
        await blocker.rebuild()
        if !ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--benchmark=") }) { await extensions.restore() }
        var saved: Session?
        let sessionURL = root.appendingPathComponent("session.json")
        if preferences.restore && FileManager.default.fileExists(atPath: sessionURL.path) {
            do {
                let raw = try Persistence.read(Session.self, at: sessionURL)
                guard raw.version == 1 else { throw CocoaError(.fileReadUnknown) }
                saved = raw.validated()
            } catch {
                unreadableFiles.insert("session.json")
                let recovery = root.appendingPathComponent("Recovery", isDirectory: true)
                try? FileManager.default.createDirectory(at: recovery, withIntermediateDirectories: true)
                try? FileManager.default.copyItem(at: sessionURL, to: recovery.appendingPathComponent(UUID().uuidString + "-session.json"))
                issue = text("сессия повреждена. исходный файл скопирован в Recovery: ", "Сессия повреждена. Исходный файл скопирован в Recovery: ") + error.localizedDescription
            }
        }
        if preferences.restore, let saved, !saved.windows.isEmpty {
            for window in saved.windows { _ = newWindow(saved: window) }
        } else { _ = newWindow() }
        Task { await ublock.startBuiltin() }
    }
    /// Without a profile the window takes the one of the window in front, so ⌘N and ⌘⇧N stay in the current profile.
    @discardableResult func newWindow(privateMode: Bool = false, saved: SavedWindow? = nil, profile: UUID? = nil) -> BrowserModel {
        let profileID = self.profile(saved?.profile ?? profile ?? active?.profileID).id
        let model = BrowserModel(store: self, privateMode: privateMode, profile: profileID)
        let controller = BrowserWindow(model: model)
        windows.append(controller)
        if let saved, !saved.tabs.isEmpty {
            for t in saved.tabs { _ = model.add(saved: t, activate: false, restored: true) }
            if let id = saved.selected, let t = model.tabs.first(where: { $0.id == id }) { model.select(t) }
            for t in model.tabs where TabPolicy.shouldLoadOnRestore(t.saved, selected: saved.selected, preferences: preferences) { t.ensureLoaded() }
        } else {
            // A new window of a profile opens with that profile's pinned tabs, loaded when first selected.
            if !privateMode { for pin in self.profile(profileID).pinned { _ = model.add(saved: SavedTab(url: pin.url, title: pin.title, pinned: true), activate: false, restored: true) } }
            _ = model.add()
        }
        if !privateMode { extensions.controller.didOpenWindow(model) }
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        scheduleSession()
        return model
    }
    func scheduleSession() {
        guard !shuttingDown else { return }
        sessionWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flushSession() }
        sessionWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }
    func flushSession() {
        let normal = windows.filter { !$0.model.privateMode }
        save(Session(windows: normal.map { $0.model.snapshot }), "session.json")
        // Each profile remembers the pinned tabs of its windows; with several windows the one in front wins.
        for window in normal.filter({ $0.window?.isKeyWindow != true }) + normal.filter({ $0.window?.isKeyWindow == true }) { window.model.rememberPinned() }
    }
    func record(_ tab: Tab) {
        guard tab.owner?.privateMode == false, let url = tab.url, ["https", "http"].contains(url.scheme ?? "") else { return }
        if let last = history.first, last.url == url, Date().timeIntervalSince(last.date) < 60 { return }
        history.insert(Visit(url: url, title: tab.title, profile: tab.owner?.profileID), at: 0)
        if history.count > 3000 { history = Array(history.prefix(3000)) }
    }
    func bookmark(_ tab: Tab) {
        guard let url = tab.url else { return }
        if let index = bookmarks.firstIndex(where: { $0.url == url }) { bookmarks.remove(at: index) }
        else { bookmarks.insert(Visit(url: url, title: tab.title), at: 0) }
    }
    func setPermission(origin: String, capability: SiteCapability, decision: Decision) {
        permissions.removeAll { $0.origin == origin && $0.capability == capability }
        if decision != .ask { permissions.append(SitePermission(origin: origin, capability: capability, decision: decision)) }
        for window in windows {
            for tab in window.model.tabs where Origin.string(tab.url) == origin {
                switch capability {
                case .camera: if decision != .allow { tab.webView?.setCameraCaptureState(.none, completionHandler: nil) }
                case .microphone: if decision != .allow { tab.webView?.setMicrophoneCaptureState(.none, completionHandler: nil) }
                case .notifications: NotificationBridge.push(tab)
                }
            }
        }
    }
    /// Removes what the clear-data panel selected, from the start of its period up to now. Bookmarks, open tabs
    /// and incognito windows are not touched; incognito data never reaches this store.
    func clear(_ choice: ClearChoice, now: Date = Date()) async {
        let start = choice.period.start(before: now)
        if choice.history { history = History.removing(history, since: start) }
        // Icons are not dated, so any history or cache clearing forgets all of them.
        if choice.history || choice.cache { favicons.clear() }
        if choice.permissions {
            permissions = []
            for window in windows { for tab in window.model.tabs { tab.webView?.setCameraCaptureState(.none, completionHandler: nil); tab.webView?.setMicrophoneCaptureState(.none, completionHandler: nil); NotificationBridge.push(tab) } }
        }
        var types = Set<String>()
        if choice.siteData { types.formUnion([WKWebsiteDataTypeCookies, WKWebsiteDataTypeLocalStorage, WKWebsiteDataTypeSessionStorage, WKWebsiteDataTypeIndexedDBDatabases, WKWebsiteDataTypeWebSQLDatabases, WKWebsiteDataTypeServiceWorkerRegistrations, WKWebsiteDataTypeFileSystem, WKWebsiteDataTypeHashSalt, WKWebsiteDataTypeMediaKeys, WKWebsiteDataTypeSearchFieldRecentSearches]) }
        if choice.cache { types.formUnion([WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache, WKWebsiteDataTypeFetchCache, WKWebsiteDataTypeOfflineWebApplicationCache]) }
        if !types.isEmpty { await websiteDataStore.removeData(ofTypes: types, modifiedSince: start) }
    }
}

/// Language and letter case of interface text, taken from a profile's preferences.
struct TextStyle: Equatable {
    var language: Language
    var lowercase: Bool
    init(language: Language, lowercase: Bool) { self.language = language; self.lowercase = lowercase }
    init(_ p: Preferences) { language = p.language; lowercase = p.lowercase }
    func text(_ low: String, _ regular: String) -> String { Copy.text(low, regular, lowercase: lowercase, language: language) }
    var locale: Locale { Locale(identifier: language == .ru ? "ru_RU" : "en_US") }
    /// A name inside authored text: «…» in Russian, “…” in English.
    func quoted(_ text: String) -> String { language == .en ? "“" + text + "”" : "«" + text + "»" }
    func profileName(_ profile: Profile) -> String { Profiles.displayName(profile, lowercase: lowercase, language: language) }
}
