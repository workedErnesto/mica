import AppKit
import SwiftUI
import MicaCore

/// QA only (`--qa --ui-tour`): walks the shell through visual states so each can be captured from outside.
/// A step advances when the file `tour-next` appears in the QA profile, so screenshots stay in sync.
@MainActor
enum UITour {
    static func run(store: Store) async {
        guard let browser = store.active, let window = browser.controller?.window else { return }
        let trigger = store.root.appendingPathComponent("tour-next")
        func log(_ text: String) { FileHandle.standardError.write(Data(("TOUR " + text + "\n").utf8)) }
        func step(_ name: String) async {
            log("READY " + name)
            while !FileManager.default.fileExists(atPath: trigger.path) { try? await Task.sleep(nanoseconds: 100_000_000) }
            try? FileManager.default.removeItem(at: trigger)
        }
        func settle() async { try? await Task.sleep(nanoseconds: 900_000_000) }
        // Which view would receive a mouse down at points inside the title band.
        if let frame = window.contentView?.superview {
            for (name, point) in [("sidebar toggle", NSPoint(x: Chrome.lightsInset + 16, y: window.frame.height - Chrome.bar / 2)), ("back", NSPoint(x: Chrome.lightsInset + Chrome.item + 16, y: window.frame.height - Chrome.bar / 2)), ("address", NSPoint(x: window.frame.width / 2, y: window.frame.height - Chrome.bar / 2))] {
                let hit = frame.hitTest(point)
                var chain: [String] = []; var view = hit
                while let current = view, chain.count < 6 { chain.append(String(describing: type(of: current))); view = current.superview }
                log("HIT \(name): " + chain.joined(separator: " < ") + (hit?.isDescendant(of: window.contentView!) == true ? " [content]" : " [chrome]"))
            }
        }
        browser.prefs.theme = .dark; browser.prefs.layout = .left; browser.prefs.sidebarCollapsed = false
        await settle(); await step("start-dark")
        browser.prefs.transparency = 1; await settle(); await step("glass-max")
        browser.prefs.frosted = false; await settle(); await step("glass-off")
        browser.prefs.frosted = true; browser.prefs.transparency = Preferences().transparency
        browser.selected?.load(URL(string: "https://example.com")!)
        browser.open(URL(string: "https://www.wikipedia.org")!, background: true)
        browser.open(URL(string: "https://webkit.org")!, background: true)
        let pinned = browser.add(saved: SavedTab(url: URL(string: "https://github.com/WebKit/WebKit")!), activate: false)
        browser.pin(pinned)
        try? await Task.sleep(nanoseconds: 4_000_000_000)
        await step("tabs-dark")
        if let frame = window.contentView?.superview {
            for (name, x) in [("back after load", Chrome.lightsInset + Chrome.item + 16), ("reload after load", Chrome.lightsInset + 3 * Chrome.item + 16)] {
                let hit = frame.hitTest(NSPoint(x: x, y: window.frame.height - Chrome.bar / 2))
                log("HIT \(name): " + String(describing: type(of: hit as Any)) + (hit.map { String(describing: type(of: $0)) } ?? "nil"))
            }
        }
        browser.commandBar = true; await settle(); await step("command-bar")
        browser.commandBar = false; browser.showFind = true; await settle(); await step("find-bar")
        browser.showFind = false; browser.panel = .history; await settle(); await step("history-panel")
        browser.panel = .extensions; await settle(); await step("extensions-panel")
        browser.panel = nil; browser.prefs.sidebarCollapsed = true; await settle(); await step("collapsed")
        browser.prefs.sidebarCollapsed = false; browser.prefs.layout = .right; await settle(); await step("right")
        browser.prefs.theme = .custom; browser.prefs.accent = "#3E7BFA"; await settle(); await step("custom-accent")
        browser.prefs.theme = .dark; browser.prefs.toolbar.place(.downloads, in: .trailing); browser.prefs.toolbar.place(.newTab, in: .leading); await settle(); await step("toolbar-custom")
        browser.prefs.toolbar = ToolbarLayout()
        browser.prefs.layout = .top; await settle(); await step("top")
        browser.prefs.layout = .tabsAbove; await settle()
        // Tabs share the title bar band with the window buttons: which view takes a mouse down on a tab, on the plus and past it.
        if let frame = window.contentView?.superview {
            let y = window.frame.height - Chrome.bar / 2
            for (name, x) in [("tab in title band", Chrome.lightsInset + 60), ("free title band", window.frame.width - 40), ("address row", window.frame.width / 2)] {
                let hit = frame.hitTest(NSPoint(x: x, y: name == "address row" ? y - Chrome.bar : y))
                log("HIT \(name): " + (hit.map { String(describing: type(of: $0)) + " moves window: \($0.mouseDownCanMoveWindow)" } ?? "nil"))
            }
        }
        await step("tabs-above")
        browser.prefs.layout = .left; browser.prefs.theme = .light; await settle(); await step("tabs-light")
        _ = browser.add(); await settle(); await step("start-light")
        browser.panel = .history; await settle(); await step("history-light")
        browser.showClearData = true; await settle(); await step("clear-data-light")
        browser.showClearData = false; browser.panel = nil; try? await Task.sleep(nanoseconds: 500_000_000)
        browser.showSettings = true; await settle(); await step("settings")
        browser.settingsSection = .appearance; await settle(); await step("settings-appearance")
        browser.settingsSection = .start; await settle(); await step("settings-start")
        // Address field: the sample in settings and the field itself in each style.
        browser.selected?.load(URL(string: "https://ru.wikipedia.org/wiki/%D0%A1%D0%BB%D1%8E%D0%B4%D0%B0")!)
        browser.settingsSection = .space; try? await Task.sleep(nanoseconds: 2_000_000_000)
        // The address group is the last one in the section: scroll the tallest scroll view down to it.
        func scrollDown() {
            func all(_ view: NSView) -> [NSScrollView] { (view as? NSScrollView).map { [$0] } ?? [] + view.subviews.flatMap(all) }
            guard let content = window.contentView, let scroll = all(content).max(by: { ($0.documentView?.frame.height ?? 0) < ($1.documentView?.frame.height ?? 0) }), let document = scroll.documentView else { return }
            let y = document.isFlipped ? max(0, document.frame.height - scroll.contentView.bounds.height) : 0
            scroll.contentView.scroll(to: NSPoint(x: 0, y: y)); scroll.reflectScrolledClipView(scroll.contentView)
        }
        scrollDown(); await settle(); await step("settings-address")
        browser.prefs.address = AddressStyle(full: true, dimSubdomain: true, dimPath: true); await settle(); scrollDown(); await settle(); await step("settings-address-full")
        // A pinned page keeps its pin hidden until the pointer is over the field.
        let pinnedPage = browser.selected?.url
        if let pinnedPage { browser.prefs.start.shortcuts.append(StartShortcut(title: "слюды", url: pinnedPage)) }
        browser.showSettings = false; await settle()
        log("ADDRESS " + AddressDisplay.parts(browser.selected?.url?.absoluteString ?? "", style: browser.prefs.address).map { ($0.dim ? "~" : "") + $0.text }.joined(separator: " | "))
        await step("address-full")
        browser.prefs.address = AddressStyle(full: false, dimSubdomain: true); await settle(); await step("address-site-dim")
        browser.prefs.theme = .dark; browser.prefs.address = AddressStyle(full: true, dimSubdomain: true, dimPath: true); await settle(); await step("address-full-dark")
        if let pinnedPage { browser.removeStartShortcut(pinnedPage) }
        browser.prefs.theme = .light; browser.prefs.address = AddressStyle(); browser.showSettings = true
        // Profiles: a second profile with its own look, the editor, the menu, the colour panel and history marks.
        let work = store.addProfile(from: browser.profileID)
        store.updateProfile(work.id) { $0.name = "работа"; $0.icon = "briefcase" }
        let study = store.addProfile(from: browser.profileID)
        store.updateProfile(study.id) { $0.name = "учёба"; $0.icon = "graduationcap"; $0.background = "#C9B79C"; $0.glyph = .light }
        browser.editingProfile = work.id; browser.settingsSection = .profiles; await settle(); await step("settings-profiles")
        browser.prefs.theme = .dark; browser.editingProfile = study.id; await settle(); await step("settings-profiles-dark")
        browser.prefs.theme = .light; store.removeProfile(study.id)
        if let view = window.contentView {
            let rect = window.convertToScreen(NSRect(x: view.bounds.midX, y: view.bounds.midY, width: 24, height: 24))
            MicaPopover.shared.show(below: rect, in: window) { ColorPanel(hex: "#3E7BFA", presets: ProfileCatalog.backgrounds, label: "") { hex in store.updateProfile(work.id) { $0.background = hex } } }
            await settle(); await step("color-panel")
            MicaPopover.shared.close(animated: false)
        }
        browser.showSettings = false; try? await Task.sleep(nanoseconds: 500_000_000)
        browser.switchProfile(to: work.id); browser.prefs.theme = .dark; browser.prefs.layout = .top
        browser.selected?.load(URL(string: "https://example.org")!)
        try? await Task.sleep(nanoseconds: 2_000_000_000); await step("profile-work")
        // Each profile keeps its own language and case: two windows side by side, each in its own.
        browser.prefs.language = .en; browser.prefs.lowercase = false
        let standardWindow = store.newWindow(profile: Profile.standardID)
        await settle()
        log("TEXT work=\(browser.text("новая вкладка", "Новая вкладка")) | \(browser.windowTitle) ; standard=\(standardWindow.text("новая вкладка", "Новая вкладка")) | \(standardWindow.windowTitle) ; menu=\(store.text("новая вкладка", "Новая вкладка"))")
        await step("profiles-two-languages")
        standardWindow.controller?.close(); window.makeKeyAndOrderFront(nil)
        browser.prefs.language = .ru; browser.prefs.lowercase = true
        // The profile menu switches both ways, from the standard profile and from another one.
        for target in [Profile.standardID, work.id, Profile.standardID, work.id] {
            ProfileMenu.entries(browser: browser, store: store).first { $0.profile?.id == target }?.action()
            try? await Task.sleep(nanoseconds: 400_000_000)
            log("SWITCH \(target == work.id ? "work" : "standard") -> \(browser.profileID == target ? "ok" : "FAILED")")
        }
        if let view = window.contentView {
            MicaMenu.shared.show(ProfileMenu.entries(browser: browser, store: store), below: window.convertToScreen(NSRect(x: view.bounds.maxX - 220, y: view.bounds.maxY - Chrome.bar, width: 28, height: 28)), in: window)
            await settle(); await step("profile-menu")
            MicaMenu.shared.close(animated: false)
        }
        browser.panel = .history; await settle(); await step("history-profiles")
        browser.panel = nil; browser.switchProfile(to: Profile.standardID); await settle(); await step("profile-standard-again")
        store.removeProfile(work.id)
        browser.showSettings = true
        (NSApp.delegate as? AppDelegate)?.showAbout(nil); await settle(); await step("about-panel")
        NSApp.windows.first { $0.className.contains("About") || $0.title.isEmpty && $0.frame.width < 400 && $0 !== window }?.close()
        browser.settingsSection = .search; await settle(); await step("settings-search")
        browser.settingsSection = .about; await settle(); await step("settings-about")
        browser.settingsSection = .space
        browser.showSettings = false; try? await Task.sleep(nanoseconds: 500_000_000)
        browser.customizingToolbar = true; await settle(); await step("customize-toolbar")
        browser.customizingToolbar = false
        browser.prefs.userName = "Алекс"; await settle(); await step("greeting")
        browser.customizingStart = true; await settle(); await step("start-customize")
        browser.prefs.start.setVisible(.bookmarks, false); await settle(); await step("start-customize-hidden")
        browser.customizingStart = false; browser.prefs.start.setVisible(.bookmarks, true)
        browser.prefs.language = .en; await settle(); await step("greeting-en")
        browser.showSettings = true; browser.settingsSection = .appearance; await settle(); await step("settings-en")
        browser.settingsSection = .about; await settle(); await step("settings-about-en")
        browser.showSettings = false; browser.prefs.language = .ru; browser.prefs.userName = ""
        try? await Task.sleep(nanoseconds: 500_000_000)
        browser.onboardingStep = 0; browser.showOnboarding = true; await settle(); await step("onboarding")
        browser.onboardingStep = 1; await settle(); await step("onboarding-import")
        browser.onboardingStep = 2; await settle(); await step("onboarding-space")
        browser.onboardingStep = 3; await settle(); await step("onboarding-appearance")
        browser.prefs.theme = .custom; browser.prefs.accent = "#D6409F"; store.preferences.appIcon = "kitty-kuromi"; await settle(); await step("onboarding-custom")
        browser.prefs.theme = .dark; store.preferences.appIcon = nil; browser.onboardingStep = 0; await settle(); await step("onboarding-dark")
        browser.prefs.theme = .light
        browser.showOnboarding = false; try? await Task.sleep(nanoseconds: 500_000_000)
        browser.selected?.load(URL(string: "https://self-signed.badssl.com/")!); try? await Task.sleep(nanoseconds: 3_000_000_000); await step("error-light")
        window.setContentSize(NSSize(width: 640, height: 620)); await settle(); await step("narrow")
        window.setContentSize(NSSize(width: 1180, height: 780)); browser.prefs.theme = .system
        let incognito = store.newWindow(privateMode: true); await settle(); await step("incognito")
        incognito.controller?.window?.close()
        log("DONE")
    }
}
