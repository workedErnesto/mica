import AppKit
import SwiftUI
import MicaCore

/// A password question of the page: save what was just typed, use a generated password, or fill a saved account.
/// Shown in this window's ModalCard instead of a system sheet, composed like the profile prompt.
struct PasswordRequest: Identifiable, Equatable {
    enum Kind { case save(username: String), generate(password: String), fill([SavedLogin]) }
    enum Answer { case save, never, use, fill(SavedLogin), later }
    let id = UUID()
    let origin: String
    let kind: Kind
    let answer: (Answer) -> Void
    static func == (a: PasswordRequest, b: PasswordRequest) -> Bool { a.id == b.id }
}

struct PasswordPrompt: View {
    let request: PasswordRequest
    @ObservedObject var browser: BrowserModel
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.look) private var look
    var body: some View {
        VStack(spacing: 0) {
            mark
                .scaleEffect(shown || reduced ? 1 : 0.8)
                .padding(.bottom, 14)
            Text(title)
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 4)
            Text(URL(string: request.origin)?.host ?? request.origin)
                .font(.system(size: 12)).foregroundStyle(Palette.text2)
                .lineLimit(1).truncationMode(.middle).help(request.origin)
                .padding(.bottom, 16)
            content
                .padding(.bottom, 16)
            VStack(spacing: Space.small) { buttons }
        }
        .padding(.horizontal, 22).padding(.top, 24).padding(.bottom, 18)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { withMotion(reduced ? nil : Motion.snappySpring) { shown = true } }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private var title: String {
        switch request.kind {
        case .save: return browser.text("сохранить пароль?", "Сохранить пароль?")
        case .generate: return browser.text("создать стойкий пароль?", "Создать стойкий пароль?")
        case .fill: return browser.text("заполнить учётную запись?", "Заполнить учётную запись?")
        }
    }

    /// The site's icon on its plate with a key badge: which site asks, and that the question is about a password.
    private var mark: some View {
        SiteIcon(url: URL(string: request.origin), favicons: browser.favicons, size: 56, tiled: true)
            .overlay(alignment: .bottomTrailing) {
                Glyph(name: "key", size: 10.5, weight: .semibold)
                    .foregroundStyle(look.onPrimary)
                    .frame(width: 22, height: 22)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(look.accent ?? Palette.primary))
                    .padding(2)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Palette.canvas))
                    .offset(x: 6, y: 6)
            }
    }

    @ViewBuilder private var content: some View {
        switch request.kind {
        case .save(let username):
            plate {
                AccountLine(name: username, browser: browser).padding(.horizontal, 12).frame(height: 36)
            }
        case .generate(let password):
            plate {
                Text(password)
                    .font(.system(size: 13, design: .monospaced)).foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    .frame(maxWidth: .infinity).padding(.horizontal, 12).padding(.vertical, 10)
            }
        case .fill(let logins):
            plate {
                VStack(spacing: 2) {
                    ForEach(Array(logins.enumerated()), id: \.element.id) { index, login in
                        AccountChoice(login: login, browser: browser) { answer(.fill(login)) }
                            .keyboardShortcut(index == 0 ? .defaultAction : nil)
                    }
                }
                .padding(4)
            }
        }
    }

    @ViewBuilder private var buttons: some View {
        switch request.kind {
        case .save:
            Button(browser.text("сохранить", "Сохранить")) { answer(.save) }
                .buttonStyle(MButtonStyle(kind: .primary, fill: true)).keyboardShortcut(.defaultAction)
            Button(browser.text("не сейчас", "Не сейчас")) { answer(.later) }
                .buttonStyle(MButtonStyle(kind: .secondary, fill: true)).keyboardShortcut(.cancelAction)
            Button(browser.text("никогда для этого сайта", "Никогда для этого сайта")) { answer(.never) }
                .buttonStyle(MButtonStyle(kind: .ghost, fill: true))
        case .generate:
            Button(browser.text("использовать", "Использовать")) { answer(.use) }
                .buttonStyle(MButtonStyle(kind: .primary, fill: true)).keyboardShortcut(.defaultAction)
            Button(browser.text("не сейчас", "Не сейчас")) { answer(.later) }
                .buttonStyle(MButtonStyle(kind: .secondary, fill: true)).keyboardShortcut(.cancelAction)
        case .fill:
            Button(browser.text("не сейчас", "Не сейчас")) { answer(.later) }
                .buttonStyle(MButtonStyle(kind: .secondary, fill: true)).keyboardShortcut(.cancelAction)
        }
    }

    /// The account or password the question is about, on the field fill so it reads as data, not as a button.
    private func plate<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(Palette.track))
    }

    private func answer(_ value: PasswordRequest.Answer) { browser.answerPassword(value) }
}

/// A user name with a person glyph; an empty one says that the account has none.
private struct AccountLine: View {
    let name: String
    @ObservedObject var browser: BrowserModel
    var body: some View {
        HStack(spacing: Space.small) {
            Glyph(name: "person", size: 12).foregroundStyle(Palette.text3)
            Text(name.isEmpty ? browser.text("без имени пользователя", "Без имени пользователя") : name)
                .font(.system(size: 13)).foregroundStyle(name.isEmpty ? Palette.text3 : Palette.ink)
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }
}

/// One saved account of the site; a click fills it.
private struct AccountChoice: View {
    let login: SavedLogin
    @ObservedObject var browser: BrowserModel
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            AccountLine(name: login.username, browser: browser)
                .padding(.horizontal, 8).frame(height: 32)
                .background(RoundedRectangle(cornerRadius: Radius.row - 4, style: .continuous).fill(hover ? Palette.hover : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.98))
        .onHover { hover = $0 }
        .animation(Motion.hover, value: hover)
    }
}
