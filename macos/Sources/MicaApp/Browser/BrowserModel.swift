import AppKit
import SwiftUI
import WebKit
import AVFoundation
import Combine
import MicaCore

@MainActor
final class BrowserModel: NSObject, ObservableObject, WKWebExtensionWindow {
    unowned let store: Store
    let privateMode: Bool
    let dataStore: WKWebsiteDataStore
    /// Incognito windows keep their own in-memory icons, so nothing they visit reaches normal windows or the disk.
    let favicons: Favicons
    @Published var tabs: [Tab] = []
    @Published var selectedID: UUID?
    @Published var focusAddress = 0
    @Published var panel: Panel?
    @Published var showFind = false
    /// ⌘G and ⌘⇧G: the find bar steps to the next or previous match; a closed bar opens instead.
    struct FindStep: Equatable { let id = UUID(); let backwards: Bool }
    @Published var findStep: FindStep?
    func stepFind(backwards: Bool) {
        guard selected?.webView != nil else { return }
        if showFind { findStep = FindStep(backwards: backwards) } else { showFind = true }
    }
    @Published var showSettings = false
    @Published var showClearData = false
    /// A window-level card (settings, onboarding, clearing data) covers the page; the web view takes no clicks meanwhile.
    var modal: Bool { showSettings || showOnboarding || showClearData || profilePrompt != nil }
    /// Profile chosen in the profile menu while mica still has to ask where to open it.
    @Published var profilePrompt: UUID?
    @Published var settingsSection: SettingsSection = .space
    /// Profile open in the profile editor of settings.
    @Published var editingProfile: UUID?
    @Published var onboardingStep = 0
    @Published var showOnboarding = false
    @Published var message: String?
    @Published var commandBar = false
    /// The top bar and sidebar footer accept dragged controls while the palette covers the page.
    @Published var customizingToolbar = false
    /// The start page shows every section with its controls in place, and a bar of shared options at the bottom.
    @Published var customizingStart = false
    @Published var fullScreen = false
    /// Set once the window is first ordered in; the content card and the start page play their entrance from it.
    @Published var entered = false
    weak var controller: BrowserWindow?
    /// Profile of this window: its start page, arrangement, theme, colours and greeting. Data is shared by all profiles.
    @Published private(set) var profileID: UUID
    var profile: Profile { store.profile(profileID) }
    /// Preferences in effect in this window. Writing splits them between the profile and the application.
    var prefs: Preferences {
        get { store.prefs(for: profileID) }
        set { store.setPrefs(newValue, for: profileID) }
    }
    var look: Look { Look(prefs) }
    private var profileWatch: AnyCancellable?
    var closed: [SavedTab] = []
    var transientPermissions: [SitePermission] = []
    lazy var downloads = DownloadManager(browser: self)
    var selected: Tab? { tabs.first { $0.id == selectedID } }
    var snapshot: SavedWindow { SavedWindow(tabs: tabs.map(\.saved), selected: selectedID, profile: profileID) }
    init(store: Store, privateMode: Bool, profile: UUID = Profile.standardID) {
        self.store = store; self.privateMode = privateMode; profileID = profile
        dataStore = privateMode ? .nonPersistent() : store.websiteDataStore
        favicons = privateMode ? Favicons(persistent: false) : store.favicons
        super.init()
        showOnboarding = !store.preferences.onboardingComplete && !privateMode
        // Views that observe only this window redraw when its profile is edited, in this or another window.
        var last = store.profile(profile)
        profileWatch = store.$profiles.sink { [weak self] list in
            guard let self else { return }
            let current = Profiles.resolve(self.profileID, in: list)
            guard current != last else { return }
            last = current
            self.objectWillChange.send()
        }
    }
    /// The window takes another profile's look. Pinned tabs belong to a profile, so this window's are kept for the old
    /// profile and the new profile's pinned tabs take their place, loaded when selected.
    func switchProfile(to id: UUID) {
        let target = store.profile(id).id
        guard target != profileID else { return }
        if !privateMode {
            rememberPinned()
            let selectedPinned = selected?.pinned == true
            for tab in tabs where tab.pinned { close(tab, remember: false) }
            for pin in store.profile(target).pinned { _ = add(saved: SavedTab(url: pin.url, title: pin.title, pinned: true), activate: false, restored: true) }
            if !tabs.contains(where: { !$0.pinned }) { _ = add() }
            else if selectedPinned || selected == nil, let first = tabs.first(where: { !$0.pinned }) ?? tabs.first { select(first) }
        }
        profileID = target
        controller?.applyProfile()
        store.updateTextStyle()
        store.scheduleSession()
    }
    /// Stores this window's pinned tabs as the profile's own.
    func rememberPinned() {
        guard !privateMode else { return }
        let pinned = tabs.filter(\.pinned).map(\.saved).filter { $0.url.map { ["http", "https"].contains($0.scheme?.lowercased() ?? "") } == true }
        store.updateProfile(profileID) { profile in
            if profile.pinned.map(\.url) != pinned.map(\.url) || profile.pinned.map(\.title) != pinned.map(\.title) { profile.pinned = pinned }
        }
    }
    /// Text of this window in its profile's language and case.
    var textStyle: TextStyle { TextStyle(prefs) }
    func text(_ low: String, _ regular: String) -> String { textStyle.text(low, regular) }
    func quoted(_ text: String) -> String { textStyle.quoted(text) }
    func profileName(_ profile: Profile) -> String { textStyle.profileName(profile) }
    var locale: Locale { textStyle.locale }
    @discardableResult func add(saved: SavedTab = SavedTab(), activate: Bool = true, restored: Bool = false, configuration: WKWebViewConfiguration? = nil) -> Tab {
        let tab = Tab(saved: saved, owner: self, restored: restored)
        if saved.pinned { tabs.insert(tab, at: tabs.prefix(while: { $0.pinned }).count) } else { tabs.append(tab) }
        if let configuration { tab.makeWebView(configuration: configuration) }
        if !privateMode { store.extensions.controller.didOpenTab(tab) }
        if activate { select(tab) }
        if !restored && tab.url != nil { tab.ensureLoaded() }
        store.scheduleSession()
        return tab
    }
    /// Takes the page off the start page's own sites of this window's profile.
    func removeStartShortcut(_ url: URL) { prefs.start.shortcuts.removeAll { $0.url == url } }
    func open(_ url: URL, background: Bool = false) { _ = add(saved: SavedTab(url: url), activate: !background) }
    func select(_ tab: Tab) {
        let previous = selected
        selectedID = tab.id
        tab.ensureLoaded()
        if !privateMode { store.extensions.controller.didActivateTab(tab, previousActiveTab: previous) }
        controller?.window?.title = windowTitle
        store.scheduleSession()
    }
    /// The window menu and Mission Control tell windows of different profiles apart by name.
    var windowTitle: String {
        var parts = ["mica"]
        if store.profiles.count > 1 || !profile.isStandard { parts.append(profileName(profile)) }
        if privateMode { parts.append(text("инкогнито", "Инкогнито")) }
        return parts.joined(separator: " — ")
    }
    func cycle(_ offset: Int) {
        guard !tabs.isEmpty else { return }
        let index = tabs.firstIndex(where: { $0.id == selectedID }) ?? 0
        select(tabs[(index + offset + tabs.count) % tabs.count])
    }
    func close(_ tab: Tab, remember: Bool = true) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        // No hidden reloads. Closing explicitly ends the tab, including forms and media.
        if remember { closed.insert(tab.saved, at: 0); closed = Array(closed.prefix(30)) }
        if !privateMode { store.extensions.controller.didCloseTab(tab, windowIsClosing: false) }
        tab.dispose()
        tabs.remove(at: index)
        if selectedID == tab.id {
            if let next = tabs.isEmpty ? nil : tabs[min(index, tabs.count - 1)] { select(next) }
            else if remember { _ = add() }
            else { selectedID = nil }
        }
        store.scheduleSession()
    }
    /// Closes every unpinned tab and leaves a fresh start page selected; the window stays open.
    /// The new tab comes first, so closing the selected tab never falls back to another one or adds a second page.
    func closeAll() {
        let doomed = tabs.filter { !$0.pinned }
        _ = add()
        for tab in doomed { close(tab) }
    }
    func reopen() { if var tab = closed.first { closed.removeFirst(); tab.id = UUID(); _ = add(saved: tab) } }
    func pin(_ tab: Tab) {
        tab.pinned.toggle(); tabs.removeAll { $0.id == tab.id }
        tabs.insert(tab, at: tabs.prefix(while: { $0.pinned }).count)
        if !privateMode { store.extensions.controller.didChangeTabProperties(.pinned, for: tab) }
        store.scheduleSession()
    }
    func move(_ id: UUID, before destination: UUID) {
        let oldIndex = tabs.firstIndex { $0.id == id } ?? 0
        let order = TabPolicy.moving(tabs.map(\.saved), id: id, before: destination)
        let lookup = Dictionary(uniqueKeysWithValues: tabs.map { ($0.id, $0) })
        tabs = order.compactMap { lookup[$0.id] }
        if let tab = lookup[id], !privateMode { store.extensions.controller.didMoveTab(tab, from: oldIndex, in: self) }
        store.scheduleSession()
    }
    func navigate(_ input: String) {
        switch AddressParser.resolve(input, engine: prefs.search) {
        case .web(let url): selected?.load(url)
        case .external(let url): Task { await external(url) }
        case .rejected: message = text("этот адрес или протокол не поддерживается", "Этот адрес или протокол не поддерживается")
        }
    }
    func external(_ url: URL) async {
        guard ["mailto", "tel"].contains(url.scheme?.lowercased() ?? "") else { message = text("этот протокол не поддерживается: ", "Этот протокол не поддерживается: ") + (url.scheme ?? ""); return }
        let result = await ask(title: text("открыть другое приложение?", "Открыть другое приложение?"), detail: url.absoluteString, buttons: [text("отмена", "Отмена"), text("открыть", "Открыть")], window: controller?.window)
        if result == 1 { NSWorkspace.shared.open(url) }
    }
    func dispose() {
        downloads.cancelAll()
        for tab in tabs { tab.dispose() }
        tabs.removeAll(); closed.removeAll(); transientPermissions.removeAll()
    }
    // Extension windows never expose private sessions.
    func tabs(for context: WKWebExtensionContext) -> [any WKWebExtensionTab] { privateMode ? [] : tabs }
    func activeTab(for context: WKWebExtensionContext) -> (any WKWebExtensionTab)? { privateMode ? nil : selected }
    func isPrivate(for context: WKWebExtensionContext) -> Bool { privateMode }
    func windowType(for context: WKWebExtensionContext) -> WKWebExtension.WindowType { .normal }
    func windowState(for context: WKWebExtensionContext) -> WKWebExtension.WindowState { controller?.window?.styleMask.contains(.fullScreen) == true ? .fullscreen : controller?.window?.isMiniaturized == true ? .minimized : .normal }
    func frame(for context: WKWebExtensionContext) -> CGRect { controller?.window?.frame ?? .zero }
    func screenFrame(for context: WKWebExtensionContext) -> CGRect { controller?.window?.screen?.frame ?? .zero }
    func focus(for context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) { controller?.showWindow(nil); completionHandler(nil) }
    func close(for context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) { controller?.window?.performClose(nil); completionHandler(nil) }
}
