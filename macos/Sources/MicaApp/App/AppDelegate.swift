import AppKit
import SwiftUI
import WebKit
import Combine
import MicaCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = Store.shared
    private let launchStart = ProcessInfo.processInfo.systemUptime
    private var observer: AnyCancellable?
    private var profileObserver: AnyCancellable?
    private var selfTest: SmokeTest?
    /// Links and files that arrive before `store.start()` restores the session wait here, so a cold launch from a link
    /// neither opens a window that the restored session buries nor duplicates one.
    private var started = false
    private var pendingURLs: [URL] = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        store.notifier.start()
        buildMenu()
        QuitHold.shared.install()
        observer = store.$preferences.map { "\($0.lowercase)-\($0.language.rawValue)" }.removeDuplicates().sink { [weak self] _ in DispatchQueue.main.async { self?.buildMenu() } }
        profileObserver = store.$profiles.map { $0.map { "\($0.id)\($0.name)\($0.icon)\($0.background)" } }.removeDuplicates().sink { [weak self] _ in DispatchQueue.main.async { self?.buildMenu() } }
        Task {
            await store.start()
            started = true
            if !pendingURLs.isEmpty { let urls = pendingURLs; pendingURLs = []; openIncoming(urls) }
            store.updater.start()
            if ProcessInfo.processInfo.arguments.contains("--qa") {
                let seconds = ProcessInfo.processInfo.systemUptime - launchStart
                try? String(seconds).write(to: store.root.appendingPathComponent("startup-seconds.txt"), atomically: true, encoding: .utf8)
                if let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--benchmark=") }), let count = Int(argument.dropFirst("--benchmark=".count)), [0, 1, 10].contains(count) { await Benchmark.run(store: store, count: count) }
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-tour") && ProcessInfo.processInfo.arguments.contains("--qa") { await UITour.run(store: store) }
            if ProcessInfo.processInfo.arguments.contains("--smoke-test") && ProcessInfo.processInfo.arguments.contains("--qa") { let test = SmokeTest(store: store); selfTest = test; await test.run() }
        }
    }
    /// Right click on the Dock icon: every profile. Choosing one brings its window forward or opens one.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        for item in profileItems() { menu.addItem(item) }
        return menu
    }
    /// One item per profile with its mark; a check shows profiles that have an open window.
    fileprivate func profileItems() -> [NSMenuItem] {
        store.profiles.map { profile in
            let item = NSMenuItem(title: store.profileName(profile), action: #selector(openProfile(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = profile.id
            item.image = Self.mark(profile)
            item.state = store.windows.contains { $0.model.profileID == profile.id && !$0.model.privateMode } ? .on : .off
            return item
        }
    }
    /// The standard about panel with what mica is, the icon chosen in the Dock and the marketing version alone: the
    /// build number (always 1 for local builds) used to show up as "(1)" next to it.
    @objc func showAbout(_ sender: Any?) {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let body = NSMutableParagraphStyle(); body.alignment = .center; body.paragraphSpacing = 6
        let text = NSMutableAttributedString()
        func line(_ string: String, _ size: CGFloat = 11, color: NSColor = .secondaryLabelColor, link: URL? = nil) {
            var attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size), .foregroundColor: color, .paragraphStyle: body]
            if let link { attributes[.link] = link }
            text.append(NSAttributedString(string: string + "\n", attributes: attributes))
        }
        line(store.text("браузер на системном WebKit: вкладки не перезагружаются, когда вы к ним возвращаетесь.", "Браузер на системном WebKit: вкладки не перезагружаются, когда вы к ним возвращаетесь."), color: .labelColor)
        line(store.text("профили, блокировка трекеров, зашифрованные пароли и расширения Chrome Web Store и Firefox Add-ons. собственной телеметрии нет.", "Профили, блокировка трекеров, зашифрованные пароли и расширения Chrome Web Store и Firefox Add-ons. Собственной телеметрии нет."))
        line("github.com/workedErnesto/mica", link: URL(string: "https://github.com/workedErnesto/mica"))
        line(store.text("develop whoa with ❤️", "Develop whoa with ❤️"), color: .tertiaryLabelColor)
        if text.length > 0 { text.deleteCharacters(in: NSRange(location: text.length - 1, length: 1)) }
        var options: [NSApplication.AboutPanelOptionKey: Any] = [.applicationName: "mica", .applicationVersion: version, .version: "", .credits: text]
        if let icon = NSApp.applicationIconImage { options[.applicationIcon] = icon }
        NSApp.orderFrontStandardAboutPanel(options: options)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func openProfile(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        store.openProfile(id)
    }
    private static func mark(_ profile: Profile) -> NSImage? {
        let renderer = ImageRenderer(content: ProfileMark(profile: profile, size: 16))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        return renderer.nsImage
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { if !flag { _ = store.newWindow() }; return true }
    /// Web links from other apps, and local HTML, XHTML or PDF files from Finder, another app or a drop on the Dock icon.
    /// A file is registered in LocalFiles right away, while the sandbox extension LaunchServices granted is fresh; one
    /// mica cannot read still gets a tab that says so instead of vanishing.
    func application(_ application: NSApplication, open urls: [URL]) {
        let accepted = urls.filter { url in
            if url.isFileURL { guard AddressParser.openableFile(url) else { return false }; LocalFiles.shared.grant(url); return true }
            return ["http", "https"].contains(url.scheme?.lowercased() ?? "") && AddressParser.navigable(url)
        }
        guard !accepted.isEmpty else { return }
        if started { openIncoming(accepted) } else { pendingURLs += accepted }
    }
    /// Links and files from other apps never land in a private window. A blank new tab takes the first one instead of staying behind it.
    private func openIncoming(_ urls: [URL]) {
        let normal = store.windows.filter { !$0.model.privateMode }
        let browser = (normal.first { $0.window?.isKeyWindow == true } ?? normal.last)?.model ?? store.newWindow()
        var remaining = urls[...]
        if let tab = browser.selected, tab.url == nil, let first = remaining.first {
            tab.load(first); remaining = remaining.dropFirst()
        }
        for url in remaining { browser.open(url) }
        browser.controller?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let running = store.windows.contains { $0.model.downloads.items.contains { $0.state == .running || $0.state == .choosing } }
        if running {
            Task {
                let answer = await ask(title: store.text("завершить mica и отменить загрузки?", "Завершить mica и отменить загрузки?"), detail: store.text("незавершённые загрузки будут отменены", "Незавершённые загрузки будут отменены"), buttons: [store.text("отмена", "Отмена"), store.text("завершить", "Завершить")])
                if answer == 1 { prepareQuit() }
                sender.reply(toApplicationShouldTerminate: answer == 1)
            }; return .terminateLater
        }
        prepareQuit(); return .terminateNow
    }
    func prepareQuit() { store.flushPreferences(); store.sessionWork?.cancel(); store.flushSession(); store.shuttingDown = true; for window in store.windows { window.model.downloads.cancelAll() } }
    @objc func performCommand(_ sender: NSMenuItem) {
        let browser = store.active
        switch sender.representedObject as? String {
        case "newWindow": _ = store.newWindow()
        case "private": _ = store.newWindow(privateMode: true)
        case "customize": if let browser { browser.showSettings = false; browser.customizingToolbar = true }
        case "tab": _ = (browser ?? store.newWindow()).add(); store.active?.focusAddress += 1
        case "close": browser?.selected.map { browser?.close($0) }
        case "reopen": browser?.reopen()
        case "address": browser?.focusAddress += 1
        case "reload": browser?.selected?.reload()
        case "reloadHard": browser?.selected?.reloadFromOrigin()
        case "back": browser?.selected?.webView?.goBack()
        case "forward": browser?.selected?.webView?.goForward()
        case "find": browser?.showFind.toggle()
        case "findNext", "findPrevious": browser?.stepFind(backwards: sender.representedObject as? String == "findPrevious")
        case "sidebar": if let browser { withMotion(Motion.panel) { browser.prefs.sidebarCollapsed.toggle() } }
        case "bookmark": if let tab = browser?.selected { store.bookmark(tab) }
        case "history": browser?.panel = browser?.panel == .history ? nil : .history
        case "clearData": browser?.showClearData = true
        case "downloads": browser?.panel = browser?.panel == .downloads ? nil : .downloads
        case "extensions": browser?.panel = browser?.panel == .extensions ? nil : .extensions
        case "settings": browser?.showSettings = true
        case "next": browser?.cycle(1)
        case "previous": browser?.cycle(-1)
        case "zoomIn": if let web = browser?.selected?.webView { web.pageZoom = min(3, web.pageZoom + 0.1) }
        case "zoomOut": if let web = browser?.selected?.webView { web.pageZoom = max(0.5, web.pageZoom - 0.1) }
        case "zoomReset": browser?.selected?.webView?.pageZoom = 1
        case "print": if let web = browser?.selected?.webView { let operation = web.printOperation(with: NSPrintInfo.shared); operation.showsPrintPanel = true; operation.run() }
        default:
            if let command = sender.representedObject as? String, let index = Int(command), let browser, !browser.tabs.isEmpty { browser.select(browser.tabs[min(index, browser.tabs.count - 1)]) }
        }
    }
    private lazy var profileMenuDelegate = ProfileMenuDelegate(owner: self)
    /// The profiles menu rebuilds when it opens, so the checks follow windows opened and closed since.
    final class ProfileMenuDelegate: NSObject, NSMenuDelegate {
        weak var owner: AppDelegate?
        init(owner: AppDelegate) { self.owner = owner }
        func menuNeedsUpdate(_ menu: NSMenu) {
            MainActor.assumeIsolated {
                guard let owner else { return }
                menu.removeAllItems()
                for item in owner.profileItems() { menu.addItem(item) }
            }
        }
    }
    func buildMenu() {
        let main = NSMenu()
        func menu(_ title: String) -> NSMenu { let item = NSMenuItem(); item.title = title; let menu = NSMenu(title: title); item.submenu = menu; main.addItem(item); return menu }
        func item(_ menu: NSMenu, _ low: String, _ regular: String, _ key: String = "", _ command: String, _ modifiers: NSEvent.ModifierFlags = [.command]) {
            let item = NSMenuItem(title: store.text(low, regular), action: #selector(performCommand(_:)), keyEquivalent: key); item.target = self; item.representedObject = command; item.keyEquivalentModifierMask = modifiers; menu.addItem(item)
        }
        /// A second shortcut for a command (shared/keymap.json lists several): a hidden item that still answers its key.
        func alternate(_ menu: NSMenu, _ key: String, _ command: String, _ modifiers: NSEvent.ModifierFlags) {
            let item = NSMenuItem(title: command, action: #selector(performCommand(_:)), keyEquivalent: key); item.target = self; item.representedObject = command
            item.keyEquivalentModifierMask = modifiers; item.isHidden = true; item.allowsKeyEquivalentWhenHidden = true; menu.addItem(item)
        }
        let app = menu("mica")
        let about = NSMenuItem(title: store.text("о mica", "О mica"), action: #selector(showAbout(_:)), keyEquivalent: ""); about.target = self; app.addItem(about)
        item(app, "настройки…", "Настройки…", ",", "settings")
        app.addItem(.separator())
        let services = NSMenu(); let serviceItem = NSMenuItem(title: store.text("службы", "Службы"), action: nil, keyEquivalent: ""); serviceItem.submenu = services; app.addItem(serviceItem); NSApp.servicesMenu = services
        app.addItem(withTitle: store.text("скрыть mica", "Скрыть mica"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(withTitle: store.text("скрыть остальные", "Скрыть остальные"), action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h").keyEquivalentModifierMask = [.command, .option]
        app.addItem(withTitle: store.text("показать все", "Показать все"), action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        app.addItem(.separator()); app.addItem(withTitle: store.text("завершить mica", "Завершить mica"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let file = menu(store.text("файл", "Файл"))
        item(file, "новая вкладка", "Новая вкладка", "t", "tab"); item(file, "новое окно", "Новое окно", "n", "newWindow"); item(file, "новое окно инкогнито", "Новое окно инкогнито", "n", "private", [.command, .shift]); file.addItem(.separator())
        item(file, "закрыть вкладку", "Закрыть вкладку", "w", "close"); item(file, "восстановить вкладку", "Восстановить вкладку", "t", "reopen", [.command, .shift]); item(file, "печать…", "Печать…", "p", "print")
        let edit = menu(store.text("правка", "Правка"))
        // Undo and redo share Russian words with cancel and retry elsewhere, so their English is spelled out here.
        let english = store.preferences.language == .en
        for (low, regular, key, action) in [("отменить", "Отменить", "z", "undo:"), ("повторить", "Повторить", "Z", "redo:"), ("вырезать", "Вырезать", "x", "cut:"), ("копировать", "Копировать", "c", "copy:"), ("вставить", "Вставить", "v", "paste:"), ("выбрать всё", "Выбрать всё", "a", "selectAll:")] {
            let title = english && action == "undo:" ? (store.preferences.lowercase ? "undo" : "Undo") : english && action == "redo:" ? (store.preferences.lowercase ? "redo" : "Redo") : store.text(low, regular)
            edit.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
            if action == "paste:" {
                edit.addItem(withTitle: store.text("вставить без форматирования", "Вставить без форматирования"), action: Selector(("pasteAsPlainText:")), keyEquivalent: "v").keyEquivalentModifierMask = [.command, .option, .shift]
            }
        }
        item(edit, "найти на странице", "Найти на странице", "f", "find"); item(edit, "следующее совпадение", "Следующее совпадение", "g", "findNext"); item(edit, "предыдущее совпадение", "Предыдущее совпадение", "g", "findPrevious", [.command, .shift])
        let view = menu(store.text("вид", "Вид")); item(view, "увеличить", "Увеличить", "=", "zoomIn"); item(view, "уменьшить", "Уменьшить", "-", "zoomOut"); item(view, "исходный масштаб", "Исходный масштаб", "0", "zoomReset"); view.addItem(.separator()); item(view, "показать или скрыть боковую панель", "Показать или скрыть боковую панель", "s", "sidebar", [.command, .control]); item(view, "настроить панель инструментов…", "Настроить панель инструментов…", "", "customize")
        view.addItem(withTitle: store.text("полноэкранный режим", "Полноэкранный режим"), action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f").keyEquivalentModifierMask = [.command, .control]
        let go = menu(store.text("переход", "Переход")); item(go, "адресная строка", "Адресная строка", "l", "address"); item(go, "назад", "Назад", "[", "back"); item(go, "вперёд", "Вперёд", "]", "forward"); item(go, "перезагрузить", "Перезагрузить", "r", "reload"); item(go, "перезагрузить без кэша", "Перезагрузить без кэша", "r", "reloadHard", [.command, .shift]); item(go, "следующая вкладка", "Следующая вкладка", "\t", "next", [.control]); item(go, "предыдущая вкладка", "Предыдущая вкладка", "\t", "previous", [.control, .shift])
        // Safari's ⌘⇧] and ⌘⇧[ and Chrome's ⌘⌥→ and ⌘⌥← also switch tabs.
        alternate(go, "}", "next", [.command]); alternate(go, "{", "previous", [.command])
        alternate(go, String(Character(UnicodeScalar(NSRightArrowFunctionKey)!)), "next", [.command, .option]); alternate(go, String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!)), "previous", [.command, .option])
        for index in 1...9 { let title = store.text("вкладка ", "Вкладка ") + String(index); item(go, title, title, String(index), String(index == 9 ? 999 : index - 1)) }
        let library = menu(store.text("библиотека", "Библиотека")); item(library, "закладка для страницы", "Закладка для страницы", "d", "bookmark"); item(library, "история", "История", "y", "history"); item(library, "очистить историю…", "Очистить историю…", "\u{8}", "clearData", [.command, .shift]); item(library, "загрузки", "Загрузки", "j", "downloads", [.command, .shift]); item(library, "расширения", "Расширения", "e", "extensions", [.command, .shift])
        let profiles = menu(store.text("профили", "Профили"))
        profiles.delegate = profileMenuDelegate
        for entry in profileItems() { profiles.addItem(entry) }
        let windows = menu(store.text("окно", "Окно")); NSApp.windowsMenu = windows; windows.addItem(withTitle: store.text("свернуть", "Свернуть"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        NSApp.mainMenu = main
    }
}
