import AppKit
import SwiftUI
import WebKit
import Combine
import CryptoKit
import MicaCore

/// A question or message of mica, or a dialog of a page, waiting in its window. Buttons follow the order the callers
/// pass: index 0 cancels (Esc, a click beside the card), the last is the default (Return).
struct AlertRequest: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let detail: String
    let buttons: [String]
    var destructive = false
    /// A page's dialog shows that site's icon.
    var site: URL?
    /// A switch under the buttons ("don't ask for t.me"); its state comes back with the answer.
    var remember: String?
    let answer: (Int, Bool) -> Void
    static func == (a: AlertRequest, b: AlertRequest) -> Bool { a.id == b.id }
}

/// Asks in the browser window with mica's card (AlertPrompt). A window that is not a browser window, or no window at
/// all, still gets the system alert so the answer always comes back.
@MainActor
func ask(title: String, detail: String, buttons: [String], window: NSWindow? = nil, destructive: Bool = false, site: URL? = nil) async -> Int {
    await askRemembering(title: title, detail: detail, buttons: buttons, window: window, destructive: destructive, site: site).index
}

/// The same question with a switch under the buttons (`remember` is its label); the answer carries its state.
@MainActor
func askRemembering(title: String, detail: String, buttons: [String], window: NSWindow? = nil, destructive: Bool = false, site: URL? = nil, remember: String? = nil) async -> (index: Int, remember: Bool) {
    let store = Store.shared
    let target = window ?? NSApp.keyWindow
    let browser = store.windows.first(where: { $0.window === target })?.model ?? (window == nil ? store.active : nil)
    if let browser, browser.controller?.window?.isVisible == true {
        return await withCheckedContinuation { continuation in
            let pending = AlertRequest(title: title, detail: detail, buttons: buttons.isEmpty ? [store.text("понятно", "Понятно")] : buttons, destructive: destructive, site: site, remember: remember) { continuation.resume(returning: (index: $0, remember: $1)) }
            browser.alerts.append(pending)
            // QA only (`--qa --qa-confirm`): the card is answered with its default button after two seconds.
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--qa") && arguments.contains("--qa-confirm") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { if browser.alerts.first?.id == pending.id { browser.answerAlert(pending.buttons.count - 1) } }
            }
        }
    }
    return await systemAsk(title: title, detail: detail, buttons: buttons, window: target, remember: remember)
}

@MainActor
private func systemAsk(title: String, detail: String, buttons: [String], window: NSWindow?, remember: String?) async -> (index: Int, remember: Bool) {
    let alert = NSAlert(); alert.messageText = title
    if let remember { alert.showsSuppressionButton = true; alert.suppressionButton?.title = remember }
    // NSAlert draws the bundle icon; the icon chosen in settings is the one in the Dock.
    alert.icon = NSApp.applicationIconImage
    if detail.count > 1600 {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 440, height: 240))
        scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        let text = NSTextView(frame: scroll.bounds)
        text.string = detail; text.font = .systemFont(ofSize: 12); text.isEditable = false; text.isSelectable = true; text.drawsBackground = false
        text.isVerticallyResizable = true; text.isHorizontallyResizable = false
        text.textContainer?.widthTracksTextView = true
        text.textContainer?.containerSize = NSSize(width: 440, height: CGFloat.greatestFiniteMagnitude)
        text.maxSize = NSSize(width: 440, height: CGFloat.greatestFiniteMagnitude)
        scroll.documentView = text; alert.accessoryView = scroll
    } else { alert.informativeText = detail }
    for button in buttons { alert.addButton(withTitle: button) }
    let index: Int
    if let window, window.attachedSheet == nil {
        index = await withCheckedContinuation { continuation in alert.beginSheetModal(for: window) { continuation.resume(returning: $0.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue) } }
    } else { index = alert.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue }
    return (index, alert.suppressionButton?.state == .on)
}

/// This window's questions over the shell and page. Messages of the window and problems of mica go to the same card.
struct AlertLayer: ViewModifier {
    @ObservedObject var browser: BrowserModel
    @ObservedObject var store: Store
    func body(content: Content) -> some View {
        content
            .overlay {
                if let request = browser.alerts.first {
                    ModalCard(width: 320, onDismiss: { browser.answerAlert(0) }) { AlertPrompt(request: request, browser: browser) }
                        .id(request.id).transition(.opacity)
                }
            }
            .animation(Motion.quick, value: browser.alerts.first?.id)
            .onChange(of: browser.message) { _, text in
                guard let text else { return }
                browser.message = nil
                browser.inform(text)
            }
            .onChange(of: store.issue) { _, _ in store.presentIssue() }
            .onAppear { store.presentIssue() }
    }
}

/// The card of a question: the composition of the profile question (title, text, buttons stacked full width), with
/// the site's icon on top for a page's dialog. The default button is on top and the cancelling
/// one at the bottom, as in the profile and password questions. Long text scrolls inside the card.
struct AlertPrompt: View {
    let request: AlertRequest
    @ObservedObject var browser: BrowserModel
    @State private var shown = false
    @State private var remembered = false
    @Environment(\.accessibilityReduceMotion) private var reduced
    private var long: Bool { request.detail.count > 160 || request.detail.contains("\n") }
    var body: some View {
        VStack(spacing: 0) {
            mark
            Text(request.title)
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .padding(.bottom, request.detail.isEmpty ? 18 : 6)
            if !request.detail.isEmpty {
                AlertDetail(text: request.detail, centered: !long)
                    .padding(.bottom, 18)
            }
            VStack(spacing: Space.small) {
                ForEach(order, id: \.self) { index in
                    Button(request.buttons[index]) { browser.answerAlert(index, remember: remembered) }
                        .buttonStyle(MButtonStyle(kind: kind(index), fill: true))
                        .keyboardShortcut(shortcut(index))
                }
            }
            if let remember = request.remember {
                Toggle(remember, isOn: $remembered)
                    .toggleStyle(MToggleStyle()).font(.system(size: 12.5)).foregroundStyle(Palette.text2).fixedSize()
                    .help(browser.text("решение можно отменить в настройках, в разделе «разрешения сайтов».", "Решение можно отменить в настройках, в разделе «Разрешения сайтов»."))
                    .padding(.top, 14)
            }
        }
        .padding(.horizontal, 22).padding(.top, 24).padding(.bottom, 18)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { withMotion(reduced ? nil : Motion.snappySpring) { shown = true } }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    /// Only a page's dialog carries a mark, the site's icon. mica's own questions have none: its icon belongs to
    /// "about mica".
    @ViewBuilder private var mark: some View {
        if let site = request.site {
            SiteIcon(url: site, favicons: browser.favicons, size: 56, tiled: true)
                .scaleEffect(shown || reduced ? 1 : 0.8)
                .padding(.bottom, 14)
        }
    }

    /// The default first, then the other answers, the cancelling one last.
    private var order: [Int] { Array(request.buttons.indices.reversed()) }
    private var last: Int { request.buttons.count - 1 }
    private func kind(_ index: Int) -> ButtonKind {
        if index == last { return request.destructive ? .destructive : .primary }
        return index == 0 ? .ghost : .secondary
    }
    private func shortcut(_ index: Int) -> KeyboardShortcut? {
        if index == last { return .defaultAction }
        return index == 0 ? .cancelAction : nil
    }
}

/// The text of a question. Short text is centred like a system alert; longer text with paragraphs reads from the
/// left and scrolls once it is taller than the card allows.
private struct AlertDetail: View {
    let text: String
    let centered: Bool
    @State private var height: CGFloat = 0
    private let limit: CGFloat = 280
    var body: some View {
        ScrollView {
            Text(text)
                .font(.system(size: 12)).foregroundStyle(Palette.text2).lineSpacing(2)
                .multilineTextAlignment(centered ? .center : .leading)
                .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        }
        .scrollIndicators(height > limit ? .automatic : .never)
        .scrollDisabled(height <= limit)
        .frame(height: min(max(height, 16), limit))
    }
}
