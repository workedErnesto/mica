import AppKit
import SwiftUI
import MicaCore

/// What the anchored password offer shows. Owned by PasswordBridge; the panel only draws it and reports choices.
@MainActor
final class PasswordOfferModel: ObservableObject {
    enum Choice: Equatable {
        case account(SavedLogin)
        case use(password: String)
        case never
        /// Esc, or the VoiceOver escape gesture: not now, for this focus of the field.
        case dismiss
    }
    @Published var origin = ""
    @Published var offer: PasswordOffer = .generate
    @Published var password = ""
    /// Keyboard highlight over the rows and then the footer row, moved by the arrow keys in the page's field.
    @Published var selected: Int?
    @Published var edge: PasswordOfferPlacement.Edge = .above
    @Published var shown = false
    /// Weak: the window owns its tabs, a tab its password bridge, the bridge this panel.
    weak var browser: BrowserModel?

    /// Interface text in the window's language and letter case.
    func text(_ low: String, _ regular: String) -> String { browser?.text(low, regular) ?? regular }

    var choices: [Choice] {
        switch offer {
        case .fill(let logins): return logins.map { .account($0) }
        case .generate: return [.use(password: password), .never]
        }
    }

    /// The panel's height for these rows: padding, caption, rows up to `PasswordOffer.visibleRows`, footer.
    static func height(for offer: PasswordOffer) -> CGFloat {
        switch offer {
        case .fill(let logins): return 2 * Radius.panelPadding + Chrome.offerHeader + CGFloat(min(logins.count, PasswordOffer.visibleRows)) * Chrome.offerRow
        case .generate: return 2 * Radius.panelPadding + Chrome.offerHeader + Chrome.offerRow + Chrome.offerFooter
        }
    }

    func step(_ delta: Int) {
        let count = choices.count
        guard count > 0 else { return }
        guard let current = selected else { selected = delta > 0 ? 0 : count - 1; return }
        selected = (current + delta + count) % count
    }
}

/// The offer next to a sign-in field: an AppKit view over the web view, so the page can neither read nor draw it,
/// and everything outside it still reaches the page. It never becomes first responder: the field keeps the keyboard,
/// and the page script forwards the arrow keys, Return and Esc while the offer is showing.
@MainActor
final class PasswordOfferPanel: NSView {
    /// Room around the panel for its shadow; clicks there go to the page.
    static let shadowRoom: CGFloat = 16
    let model = PasswordOfferModel()
    private let hosting: NoFocusHostingView<PasswordOfferView>
    private var generation = 0

    init(browser: BrowserModel, choose: @escaping (PasswordOfferModel.Choice) -> Void) {
        hosting = NoFocusHostingView(rootView: PasswordOfferView(model: model, favicons: browser.favicons, choose: choose))
        super.init(frame: .zero)
        model.browser = browser
        // The bridge sets the frame from the placement; the hosting view must not size itself or its window.
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        addSubview(hosting)
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.insetBy(dx: Self.shadowRoom, dy: Self.shadowRoom).contains(local) else { return nil }
        return super.hitTest(point)
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Places the panel at `frame` (the panel itself, without the shadow room) in `host`, just above `page`.
    func show(in host: NSView, above page: NSView, frame: NSRect, edge: PasswordOfferPlacement.Edge) {
        generation += 1
        if superview !== host { removeFromSuperview(); host.addSubview(self, positioned: .above, relativeTo: page) }
        self.frame = frame.insetBy(dx: -Self.shadowRoom, dy: -Self.shadowRoom)
        hosting.frame = bounds
        isHidden = false
        guard !model.shown else { model.edge = edge; return }
        model.edge = edge
        model.selected = nil
        // The first frame is drawn at rest-before-entrance, then the spring (or a fade with Reduce Motion) brings it in.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            withAnimation(Motion.reduced ? Motion.hover : Motion.snappySpring) { self.model.shown = true }
        }
    }

    /// Fades out and leaves the view tree; a show in the meantime keeps it.
    func hide() {
        guard superview != nil, model.shown || !isHidden else { return }
        generation += 1
        let mark = generation
        withAnimation(Motion.hover) { model.shown = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + MotionTokens.hoverDuration + 0.05) { [weak self] in
            guard let self, self.generation == mark else { return }
            self.removeFromSuperview()
        }
    }
}

/// SwiftUI buttons inside must not take the keyboard from the page's field.
private final class NoFocusHostingView<Content: View>: NSHostingView<Content> {
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct PasswordOfferView: View {
    @ObservedObject var model: PasswordOfferModel
    let favicons: Favicons
    let choose: (PasswordOfferModel.Choice) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduced

    var body: some View {
        VStack(spacing: 0) {
            Text(caption)
                .font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.text3)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: Chrome.offerHeader, maxHeight: Chrome.offerHeader, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            rows
            if case .generate = model.offer {
                Hairline().padding(.horizontal, 4)
                FooterRow(title: model.text("никогда для этого сайта", "Никогда для этого сайта"), highlighted: model.selected == 1) { choose(.never) }
                    .frame(height: Chrome.offerFooter - 1)
            }
        }
        .padding(Radius.panelPadding)
        // The bridge sized the hosting view from the placement: the panel fills it inside the shadow room.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous).fill(Palette.raised))
        .overlay(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
        .shadow(color: Palette.menuShadow, radius: 8, y: 3)
        .scaleEffect(model.shown || reduced ? 1 : MotionTokens.popScale, anchor: model.edge == .above ? .bottom : .top)
        .offset(y: model.shown || reduced ? 0 : (model.edge == .above ? 4 : -4))
        .opacity(model.shown ? 1 : 0)
        .padding(PasswordOfferPanel.shadowRoom)
        .animation(Motion.hover, value: model.selected)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(model.text("предложение пароля", "Предложение пароля"))
        .accessibilityAction(.escape) { choose(.dismiss) }
    }

    private var caption: String {
        switch model.offer {
        case .fill: return model.text("сохранённые пароли", "Сохранённые пароли")
        case .generate: return model.text("новый пароль", "Новый пароль")
        }
    }

    @ViewBuilder private var rows: some View {
        switch model.offer {
        case .fill(let logins):
            let list = VStack(spacing: 0) {
                ForEach(Array(logins.enumerated()), id: \.element.id) { index, login in
                    OfferRow(highlighted: model.selected == index, action: { choose(.account(login)) }) {
                        SiteIcon(url: URL(string: login.origin), favicons: favicons, size: 24, tiled: true)
                    } title: {
                        Text(login.username.isEmpty ? model.text("без имени пользователя", "Без имени пользователя") : login.username)
                            .foregroundStyle(login.username.isEmpty ? Palette.text3 : Palette.ink)
                    } detail: {
                        Text(login.host).foregroundStyle(Palette.text2)
                    }
                    .accessibilityLabel((login.username.isEmpty ? model.text("без имени пользователя", "Без имени пользователя") : login.username) + ", " + login.host)
                }
            }
            if logins.count > PasswordOffer.visibleRows {
                ScrollView(.vertical) { list }
                    .scrollIndicators(.automatic)
                    .frame(height: CGFloat(PasswordOffer.visibleRows) * Chrome.offerRow)
            } else { list }
        case .generate:
            OfferRow(highlighted: model.selected == 0, action: { choose(.use(password: model.password)) }) {
                Glyph(name: "key", size: 11.5, weight: .semibold)
                    .foregroundStyle(Palette.text2)
                    .frame(width: 24, height: 24)
                    .background(RoundedRectangle(cornerRadius: 24 * 0.3, style: .continuous).fill(Palette.track))
            } title: {
                Text(model.text("использовать стойкий пароль", "Использовать стойкий пароль")).foregroundStyle(Palette.ink)
            } detail: {
                Text(model.password).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(Palette.text2)
            }
            .accessibilityLabel(model.text("использовать стойкий пароль", "Использовать стойкий пароль"))
        }
    }
}

/// A choice of the offer: leading tile, a title over a detail line. Hover and the keyboard highlight share one fill.
private struct OfferRow<Leading: View, Title: View, Detail: View>: View {
    let highlighted: Bool
    let action: () -> Void
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let title: () -> Title
    @ViewBuilder let detail: () -> Detail
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.small + 2) {
                leading()
                VStack(alignment: .leading, spacing: 1) {
                    title().font(.system(size: 13)).lineLimit(1).truncationMode(.middle)
                    detail().font(.system(size: 11)).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.small)
            .frame(height: Chrome.offerRow)
            .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(highlighted ? Palette.pressed : hover ? Palette.hover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.98))
        .onHover { hover = $0 }
        .animation(Motion.hover, value: hover)
        .accessibilityAddTraits(highlighted ? .isSelected : [])
    }
}

/// The quiet lasting choice under a generated password.
private struct FooterRow: View {
    let title: String
    let highlighted: Bool
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12)).foregroundStyle(hover || highlighted ? Palette.ink : Palette.text2)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(highlighted ? Palette.pressed : hover ? Palette.hover : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.98))
        .padding(.top, 2)
        .onHover { hover = $0 }
        .animation(Motion.hover, value: hover)
        .accessibilityAddTraits(highlighted ? .isSelected : [])
    }
}
