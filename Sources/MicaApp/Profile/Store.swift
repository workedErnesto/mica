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
    @Published var preferences: Preferences { didSet { schedulePreferences(); if oldValue.theme != preferences.theme || oldValue.customBase != preferences.customBase { applyAppearance() }; if oldValue.appIcon != preferences.appIcon { AppIcons.apply(preferences.appIcon); flushPreferences(); AppIcons.announce() }; if oldValue.blocking != preferences.blocking || oldValue.blockingExceptions != preferences.blockingExceptions { Task { await blocker.rebuild() } } } }
    @Published var bookmarks: [Visit] { didSet { save(bookmarks, "bookmarks.json") } }
    @Published var history: [Visit] { didSet { save(history, "history.json") } }
    @Published var permissions: [SitePermission] { didSet { save(permissions, "permissions.json") } }
    @Published var issue: String?
    /// Text typed in a settings field but not yet added; closing settings asks before discarding it.
    @Published var settingsDraft = ""
    var windows: [BrowserWindow] = []
    lazy var blocker = Blocker(store: self)
    lazy var extensions = ExtensionManager(store: self)
    var sessionWork: DispatchWorkItem?
    var preferencesWork: DispatchWorkItem?
    var shuttingDown = false
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
        preferences = read(Preferences.self, "preferences.json") ?? Preferences()
        bookmarks = read([Visit].self, "bookmarks.json") ?? []
        history = read([Visit].self, "history.json") ?? []
        permissions = read([SitePermission].self, "permissions.json") ?? []
        if !loadIssues.isEmpty { issue = "mica: " + loadIssues.joined(separator: "\n") }
        if ProcessInfo.processInfo.arguments.contains("--qa") { preferences.onboardingComplete = true; preferences.restore = false }
    }
    func text(_ low: String, _ regular: String) -> String { Copy.text(low, regular, lowercase: preferences.lowercase, language: preferences.language) }
    var locale: Locale { Locale(identifier: preferences.language == .ru ? "ru_RU" : "en_US") }
    func save<T: Encodable>(_ value: T, _ name: String) {
        do { try Persistence.write(value, at: root.appendingPathComponent(name)) } catch { issue = text("не удалось сохранить данные: ", "Не удалось сохранить данные: ") + error.localizedDescription }
    }
    func schedulePreferences() {
        preferencesWork?.cancel()
        let work = DispatchWorkItem { [weak self] in guard let self else { return }; self.save(self.preferences, "preferences.json") }
        preferencesWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }
    func flushPreferences() { preferencesWork?.cancel(); save(preferences, "preferences.json") }
    /// Light or dark mode in effect: the custom theme brings its own base.
    var appearanceMode: Theme { preferences.theme == .custom ? preferences.customBase : preferences.theme }
    func applyAppearance() {
        NSApp.appearance = appearanceMode == .system ? nil : NSAppearance(named: appearanceMode == .dark ? .darkAqua : .aqua)
    }
    var look: Look { Look(preferences) }
    /// Opacity of the shell tint over the blur: 0.92 at zero transparency, 0.2 at full.
    var glassTint: Double { 0.92 - preferences.transparency * 0.72 }
    func start() async {
        applyAppearance()
        AppIcons.apply(preferences.appIcon)
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
                let recovery = root.appendingPathComponent("Recovery", isDirectory: true)
                try? FileManager.default.createDirectory(at: recovery, withIntermediateDirectories: true)
                try? FileManager.default.copyItem(at: sessionURL, to: recovery.appendingPathComponent(UUID().uuidString + "-session.json"))
                issue = text("сессия повреждена. исходный файл скопирован в Recovery: ", "Сессия повреждена. Исходный файл скопирован в Recovery: ") + error.localizedDescription
            }
        }
        if preferences.restore, let saved, !saved.windows.isEmpty {
            for window in saved.windows { _ = newWindow(saved: window) }
        } else { _ = newWindow() }
    }
    @discardableResult func newWindow(privateMode: Bool = false, saved: SavedWindow? = nil) -> BrowserModel {
        let model = BrowserModel(store: self, privateMode: privateMode)
        let controller = BrowserWindow(model: model)
        windows.append(controller)
        if let saved, !saved.tabs.isEmpty {
            for t in saved.tabs { _ = model.add(saved: t, activate: false, restored: true) }
            if let id = saved.selected, let t = model.tabs.first(where: { $0.id == id }) { model.select(t) }
            for t in model.tabs where TabPolicy.shouldLoadOnRestore(t.saved, selected: saved.selected, preferences: preferences) { t.ensureLoaded() }
        } else { _ = model.add() }
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
    }
    func record(_ tab: Tab) {
        guard tab.owner?.privateMode == false, let url = tab.url, ["https", "http"].contains(url.scheme ?? "") else { return }
        if let last = history.first, last.url == url, Date().timeIntervalSince(last.date) < 60 { return }
        history.insert(Visit(url: url, title: tab.title), at: 0)
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
        if decision != .allow {
            for window in windows {
                for tab in window.model.tabs where Origin.string(tab.url) == origin {
                    if capability == .camera { tab.webView?.setCameraCaptureState(.none, completionHandler: nil) }
                    else { tab.webView?.setMicrophoneCaptureState(.none, completionHandler: nil) }
                }
            }
        }
    }
    /// Removes what the clear-data panel selected, from the start of its period up to now. Bookmarks, open tabs
    /// and incognito windows are not touched; incognito data never reaches this store.
    func clear(_ choice: ClearChoice, now: Date = Date()) async {
        let start = choice.period.start(before: now)
        if choice.history { history = History.removing(history, since: start) }
        if choice.permissions {
            permissions = []
            for window in windows { for tab in window.model.tabs { tab.webView?.setCameraCaptureState(.none, completionHandler: nil); tab.webView?.setMicrophoneCaptureState(.none, completionHandler: nil) } }
        }
        var types = Set<String>()
        if choice.siteData { types.formUnion([WKWebsiteDataTypeCookies, WKWebsiteDataTypeLocalStorage, WKWebsiteDataTypeSessionStorage, WKWebsiteDataTypeIndexedDBDatabases, WKWebsiteDataTypeWebSQLDatabases, WKWebsiteDataTypeServiceWorkerRegistrations, WKWebsiteDataTypeFileSystem, WKWebsiteDataTypeHashSalt, WKWebsiteDataTypeMediaKeys, WKWebsiteDataTypeSearchFieldRecentSearches]) }
        if choice.cache { types.formUnion([WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache, WKWebsiteDataTypeFetchCache, WKWebsiteDataTypeOfflineWebApplicationCache]) }
        if !types.isEmpty { await websiteDataStore.removeData(ofTypes: types, modifiedSince: start) }
    }
}
