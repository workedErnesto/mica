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
    /// A page's dialog shows that site's icon instead of mica's.
    var site: URL?
    let answer: (Int) -> Void
    static func == (a: AlertRequest, b: AlertRequest) -> Bool { a.id == b.id }
}

/// Asks in the browser window with mica's card (AlertPrompt). A window that is not a browser window, or no window at
/// all, still gets the system alert so the answer always comes back.
@MainActor
func ask(title: String, detail: String, buttons: [String], window: NSWindow? = nil, destructive: Bool = false, site: URL? = nil) async -> Int {
    let store = Store.shared
    let target = window ?? NSApp.keyWindow
    let browser = store.windows.first(where: { $0.window === target })?.model ?? (window == nil ? store.active : nil)
    if let browser, browser.controller?.window?.isVisible == true {
        return await withCheckedContinuation { continuation in
            let pending = AlertRequest(title: title, detail: detail, buttons: buttons.isEmpty ? ["OK"] : buttons, destructive: destructive, site: site) { continuation.resume(returning: $0) }
            browser.alerts.append(pending)
            // QA only (`--qa --qa-confirm`): the card is answered with its default button after two seconds.
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--qa") && arguments.contains("--qa-confirm") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { if browser.alerts.first?.id == pending.id { browser.answerAlert(pending.buttons.count - 1) } }
            }
        }
    }
    return await systemAsk(title: title, detail: detail, buttons: buttons, window: target)
}

@MainActor
private func systemAsk(title: String, detail: String, buttons: [String], window: NSWindow?) async -> Int {
    let alert = NSAlert(); alert.messageText = title
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
    if let window, window.attachedSheet == nil {
        return await withCheckedContinuation { continuation in alert.beginSheetModal(for: window) { continuation.resume(returning: $0.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue) } }
    }
    return alert.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
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

/// The card of a question: the composition of the profile question (mark on top, title, text, buttons stacked full
/// width) with mica's icon, or the site's icon for a page's dialog. The default button is on top and the cancelling
/// one at the bottom, as in the profile and password questions. Long text scrolls inside the card.
struct AlertPrompt: View {
    let request: AlertRequest
    @ObservedObject var browser: BrowserModel
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduced
    private var long: Bool { request.detail.count > 160 || request.detail.contains("\n") }
    var body: some View {
        VStack(spacing: 0) {
            mark
                .scaleEffect(shown || reduced ? 1 : 0.8)
                .padding(.bottom, 14)
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
                    Button(request.buttons[index]) { browser.answerAlert(index) }
                        .buttonStyle(MButtonStyle(kind: kind(index), fill: true))
                        .keyboardShortcut(shortcut(index))
                }
            }
        }
        .padding(.horizontal, 22).padding(.top, 24).padding(.bottom, 18)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { withMotion(reduced ? nil : Motion.snappySpring) { shown = true } }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    @ViewBuilder private var mark: some View {
        if let site = request.site {
            SiteIcon(url: site, favicons: browser.favicons, size: 56, tiled: true)
        } else {
            Image(nsImage: NSApp.applicationIconImage).resizable().interpolation(.high).frame(width: 56, height: 56)
                .accessibilityHidden(true)
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
