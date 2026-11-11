import AppKit
import SwiftUI
import MicaCore

/// Where to open a profile chosen in the profile menu. The composition of a system alert (mark on top, title, text,
/// buttons stacked full width, the remember box under them) drawn with mica's own card, buttons and switch.
/// The new window is the default because it leaves this window as it is; Return picks it, Esc or a click beside the
/// card cancels.
struct ProfileOpenPrompt: View {
    let profile: Profile
    @ObservedObject var store: Store
    @ObservedObject var browser: BrowserModel
    @State private var remember = false
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        VStack(spacing: 0) {
            ProfileMark(profile: profile, size: 56)
                .shadow(color: Color(hex: profile.background).opacity(0.35), radius: 12, y: 5)
                .scaleEffect(shown || reduced ? 1 : 0.8)
                .padding(.bottom, 14)
            Text(browser.text("открыть профиль ", "Открыть профиль ") + browser.quoted(browser.profileName(profile)) + "?")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 6)
            Text(browser.text("в этом окне закреплённые вкладки сменятся закреплёнными вкладками профиля, остальные вкладки останутся. в новом окне это окно не изменится.", "В этом окне закреплённые вкладки сменятся закреплёнными вкладками профиля, остальные вкладки останутся. В новом окне это окно не изменится."))
                .font(.system(size: 12)).foregroundStyle(Palette.text2).lineSpacing(2)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 18)
            VStack(spacing: Space.small) {
                Button(browser.text("в новом окне", "В новом окне")) { choose(.newWindow) }
                    .buttonStyle(MButtonStyle(kind: .primary, fill: true)).keyboardShortcut(.defaultAction)
                Button(browser.text("в этом окне", "В этом окне")) { choose(.here) }
                    .buttonStyle(MButtonStyle(kind: .secondary, fill: true))
                Button(browser.text("отмена", "Отмена")) { browser.profilePrompt = nil }
                    .buttonStyle(MButtonStyle(kind: .ghost, fill: true)).keyboardShortcut(.cancelAction)
            }
            .padding(.bottom, 14)
            Toggle(browser.text("запомнить выбор", "Запомнить выбор"), isOn: $remember)
                .toggleStyle(MToggleStyle()).font(.system(size: 12.5)).foregroundStyle(Palette.text2).fixedSize()
                .help(browser.text("ответ можно поменять в настройках, в разделе «профили».", "Ответ можно поменять в настройках, в разделе «профили»."))
        }
        .padding(.horizontal, 22).padding(.top, 24).padding(.bottom, 18)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { withMotion(reduced ? nil : Motion.snappySpring) { shown = true } }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
    private func choose(_ choice: ProfileOpening) {
        let id = profile.id
        if remember { store.preferences.profileOpening = choice }
        browser.profilePrompt = nil
        switch choice {
        case .here: withMotion(Motion.panel) { browser.switchProfile(to: id) }
        case .newWindow, .ask: store.openProfile(id)
        }
    }
}
