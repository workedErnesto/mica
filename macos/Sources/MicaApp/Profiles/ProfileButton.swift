import AppKit
import SwiftUI
import MicaCore

/// Profiles from the shell: switch this window, create a profile, open profile settings.
@MainActor
enum ProfileMenu {
    static func entries(browser: BrowserModel, store: Store) -> [MenuEntry] {
        var entries = store.profiles.map { profile in
            MenuEntry.profile(store.profileName(profile), profile: profile, checked: profile.id == browser.profileID) {
                Task { await open(profile.id, browser: browser, store: store) }
            }
        }
        entries.append(.divider)
        if store.profiles.count < Profiles.limit {
            entries.append(.item(browser.text("новый профиль…", "Новый профиль…"), symbol: "plus") { edit(browser: browser, profile: store.addProfile(from: browser.profileID).id) })
        }
        entries.append(.item(browser.text("настроить профили…", "Настроить профили…"), symbol: "gearshape") { edit(browser: browser, profile: browser.profileID) })
        return entries
    }
    /// Opens a profile chosen in the menu as the user set it up: in this window, in a new one, or after asking in
    /// ProfileOpenPrompt. Switching this window swaps its pinned tabs for the profile's, so until an answer is
    /// remembered mica asks.
    static func open(_ id: UUID, browser: BrowserModel, store: Store) async {
        guard id != browser.profileID else { return }
        switch store.preferences.profileOpening {
        case .ask: browser.profilePrompt = id
        case .here: withMotion(Motion.panel) { browser.switchProfile(to: id) }
        case .newWindow: store.openProfile(id)
        }
    }
    static func edit(browser: BrowserModel, profile: UUID) {
        browser.editingProfile = profile
        browser.settingsSection = .profiles
        browser.showSettings = true
    }
}

/// The window's profile mark; a click opens the profile menu under it.
struct ProfileButton: View {
    @ObservedObject var browser: BrowserModel
    @ObservedObject var store: Store
    var size: CGFloat = 28
    @State private var anchor = PopupAnchor()
    @State private var hover = false
    var body: some View {
        let profile = browser.profile
        let label = browser.text("профиль: ", "Профиль: ") + store.profileName(profile)
        Button {
            guard let view = anchor.view, let window = view.window else { return }
            let rect = window.convertToScreen(view.convert(view.bounds, to: nil))
            MicaMenu.shared.show(ProfileMenu.entries(browser: browser, store: store), below: rect, in: window)
        } label: {
            ProfileMark(profile: profile, size: size * 0.64)
                .id(profile.id)
                .transition(Motion.pop)
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: Radius.icon, style: .continuous).fill(hover ? Palette.hover : .clear))
                .contentShape(RoundedRectangle(cornerRadius: Radius.icon, style: .continuous))
        }
        .buttonStyle(PressStyle(scale: 0.9))
        .background(PopupAnchorView(anchor: anchor))
        .onHover { hover = $0 }
        .animation(Motion.hover, value: hover)
        .animation(Motion.quick, value: profile.id)
        .help(label)
        .accessibilityLabel(label)
    }
}
