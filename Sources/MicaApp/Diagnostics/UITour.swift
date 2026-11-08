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
        store.preferences.theme = .dark; store.preferences.layout = .left; store.preferences.sidebarCollapsed = false
        await settle(); await step("start-dark")
        store.preferences.transparency = 1; await settle(); await step("glass-max")
        store.preferences.frosted = false; await settle(); await step("glass-off")
        store.preferences.frosted = true; store.preferences.transparency = Preferences().transparency
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
        browser.panel = nil; store.preferences.sidebarCollapsed = true; await settle(); await step("collapsed")
        store.preferences.sidebarCollapsed = false; store.preferences.layout = .right; await settle(); await step("right")
        store.preferences.theme = .custom; store.preferences.accent = "#3E7BFA"; await settle(); await step("custom-accent")
        store.preferences.theme = .dark; store.preferences.toolbar.place(.downloads, in: .trailing); store.preferences.toolbar.place(.newTab, in: .leading); await settle(); await step("toolbar-custom")
        store.preferences.toolbar = ToolbarLayout()
        store.preferences.layout = .top; await settle(); await step("top")
        store.preferences.layout = .left; store.preferences.theme = .light; await settle(); await step("tabs-light")
        _ = browser.add(); await settle(); await step("start-light")
        browser.panel = .history; await settle(); await step("history-light")
        browser.showClearData = true; await settle(); await step("clear-data-light")
        browser.showClearData = false; browser.panel = nil; try? await Task.sleep(nanoseconds: 500_000_000)
        browser.showSettings = true; await settle(); await step("settings")
        browser.settingsSection = .appearance; await settle(); await step("settings-appearance")
        browser.settingsSection = .start; await settle(); await step("settings-start")
        browser.settingsSection = .search; await settle(); await step("settings-search")
        browser.settingsSection = .about; await settle(); await step("settings-about")
        browser.settingsSection = .space
        browser.showSettings = false; try? await Task.sleep(nanoseconds: 500_000_000)
        browser.customizingToolbar = true; await settle(); await step("customize-toolbar")
        browser.customizingToolbar = false
        store.preferences.userName = "Алекс"; await settle(); await step("greeting")
        store.preferences.language = .en; await settle(); await step("greeting-en")
        browser.showSettings = true; browser.settingsSection = .appearance; await settle(); await step("settings-en")
        browser.settingsSection = .about; await settle(); await step("settings-about-en")
        browser.showSettings = false; store.preferences.language = .ru; store.preferences.userName = ""
        try? await Task.sleep(nanoseconds: 500_000_000)
        browser.onboardingStep = 0; browser.showOnboarding = true; await settle(); await step("onboarding")
        browser.onboardingStep = 1; await settle(); await step("onboarding-space")
        browser.onboardingStep = 2; await settle(); await step("onboarding-appearance")
        store.preferences.theme = .custom; store.preferences.accent = "#D6409F"; store.preferences.appIcon = "kitty-kuromi"; await settle(); await step("onboarding-custom")
        store.preferences.theme = .dark; store.preferences.appIcon = nil; browser.onboardingStep = 0; await settle(); await step("onboarding-dark")
        store.preferences.theme = .light
        browser.showOnboarding = false; try? await Task.sleep(nanoseconds: 500_000_000)
        browser.selected?.load(URL(string: "https://self-signed.badssl.com/")!); try? await Task.sleep(nanoseconds: 3_000_000_000); await step("error-light")
        window.setContentSize(NSSize(width: 640, height: 620)); await settle(); await step("narrow")
        window.setContentSize(NSSize(width: 1180, height: 780)); store.preferences.theme = .system
        let incognito = store.newWindow(privateMode: true); await settle(); await step("incognito")
        incognito.controller?.window?.close()
        log("DONE")
    }
}
