import AppKit
import WebKit
import Combine
import MicaCore

/// Runs in a separate WebKit content world. Only the top-level HTTPS document can request actions.
///
/// Focusing a sign-in field shows the offer anchored to that field (PasswordOfferPanel): saved accounts of exactly
/// this origin, or a strong password for a new-password field. The page keeps the keyboard; Esc, a click elsewhere or
/// typing hide the offer for this focus only (PasswordOfferSession). After a form is sent, "save password?" is a
/// card (PasswordPrompt): the field it would point at is usually gone with the next page.
@MainActor
final class PasswordBridge: NSObject, WKScriptMessageHandler {
    weak var tab: Tab?
    private var presenting = false
    private let world = WKContentWorld.world(name: "mica.passwords")
    private var session = PasswordOfferSession()
    /// What is offered for the focused field and where the field is, in the page's CSS pixels.
    private struct Current {
        let field: Int
        let origin: String
        let offer: PasswordOffer
        let password: String
        var rect: CGRect
        var innerWidth: CGFloat
    }
    private var current: Current?
    private var panel: PasswordOfferPanel?
    /// Window state that can hide the offer (another tab, settings, the command bar), watched while it shows.
    private var watch: AnyCancellable?
    /// The page script forwards moves and keys only while it knows the offer is there: the field it was told about.
    private var scriptField: Int?
    /// VoiceOver hears about the offer once per focus of a field, not each time it comes back into view.
    private var announced: Int?

    init(tab: Tab, controller: WKUserContentController) {
        self.tab = tab
        super.init()
        controller.add(self, contentWorld: world, name: "micaPasswords")
        controller.addUserScript(WKUserScript(source: Self.script, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: world))
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let tab, let owner = tab.owner, !owner.privateMode, owner.selectedID == tab.id,
              let view = tab.webView, message.frameInfo.isMainFrame,
              let origin = Origin.string(message.frameInfo.request.url), Origin.secure(origin),
              origin == Origin.string(view.url), let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }
        let id = (body["id"] as? NSNumber)?.intValue
        switch type {
        case "focus":
            guard let id, let geometry = Self.geometry(body) else { return }
            session.apply(.focus(id))
            prepare(field: id, origin: origin, isNew: body["new"] as? Bool == true, maxLength: (body["max"] as? NSNumber)?.intValue ?? -1, geometry: geometry, owner: owner)
        case "move":
            guard let id, id == current?.field, let geometry = Self.geometry(body) else { return }
            current?.rect = geometry.rect; current?.innerWidth = geometry.innerWidth
            render()
        case "click":
            guard let id else { return }
            session.apply(.click(id))
            if let geometry = Self.geometry(body) { current?.rect = geometry.rect; current?.innerWidth = geometry.innerWidth }
            render()
        case "input":
            guard let id else { return }
            session.apply(.input(id)); render()
        case "blur":
            guard let id else { return }
            session.apply(.blur(id)); render()
        case "key":
            guard let id, id == session.field, session.visible, let panel, let key = body["key"] as? String else { return }
            switch key {
            case "Escape": choose(.dismiss)
            case "ArrowDown": panel.model.step(1)
            case "ArrowUp": panel.model.step(-1)
            case "Enter":
                if let index = panel.model.selected, panel.model.choices.indices.contains(index) { choose(panel.model.choices[index]) }
            default: break
            }
        case "submit":
            submitted(body, origin: origin, owner: owner, tab: tab)
        default: break
        }
    }

    /// The tab shows another document or goes away: whatever was offered belonged to the old one.
    func leave() {
        session.apply(.leave)
        current = nil
        render()
    }

    // MARK: Offer beside the field

    private struct Geometry { let rect: CGRect; let innerWidth: CGFloat }
    private static func geometry(_ body: [String: Any]) -> Geometry? {
        guard let r = body["rect"] as? [NSNumber], r.count == 4, let vw = (body["vw"] as? NSNumber)?.doubleValue, vw > 0 else { return nil }
        let values = r.map(\.doubleValue)
        guard values.allSatisfy(\.isFinite), values[2] >= 0, values[3] >= 0 else { return nil }
        return Geometry(rect: CGRect(x: values[0], y: values[1], width: values[2], height: values[3]), innerWidth: vw)
    }

    private func prepare(field: Int, origin: String, isNew: Bool, maxLength: Int, geometry: Geometry, owner: BrowserModel) {
        let manager = owner.store.passwords
        if manager.loading {
            // The vault opens on first use; the field may have lost focus by the time it is ready.
            Task { [weak self] in
                await manager.waitUntilReady()
                guard let self, self.session.field == field else { return }
                self.prepare(field: field, origin: origin, isNew: isNew, maxLength: maxLength, geometry: geometry, owner: owner)
            }
            return
        }
        guard manager.error == nil,
              let offer = PasswordOffer.decide(vault: manager.vault, origin: origin, isNew: isNew, maxLength: maxLength,
                                               offerPasswords: owner.store.preferences.offerPasswords, fillPasswords: owner.store.preferences.fillPasswords)
        else { current = nil; render(); return }
        // The same focus keeps its generated password while the panel follows the field.
        let password = current?.field == field && current?.offer == offer ? current!.password
            : offer == .generate ? PasswordGenerator.strong(maxLength: maxLength > 0 ? maxLength : nil) : ""
        current = Current(field: field, origin: origin, offer: offer, password: password, rect: geometry.rect, innerWidth: geometry.innerWidth)
        render()
    }

    /// Shows, moves or hides the panel for the current state. Called after every event and window change.
    private func render() {
        guard let tab, let owner = tab.owner, let view = tab.webView, let current, session.visible, session.field == current.field,
              owner.selectedID == tab.id, !owner.modal, !owner.commandBar, !owner.customizingToolbar,
              let host = view.superview, view.window != nil, Origin.string(view.url) == current.origin
        else { conceal(); return }
        let panel = self.panel ?? PasswordOfferPanel(browser: owner) { [weak self] choice in self?.choose(choice) }
        self.panel = panel
        if panel.model.origin != current.origin || panel.model.offer != current.offer || panel.model.password != current.password {
            panel.model.origin = current.origin; panel.model.offer = current.offer; panel.model.password = current.password
            panel.model.selected = nil
        }
        setScript(active: true, field: current.field)
        watchWindow(owner)
        let field = PasswordOfferPlacement.viewRect(css: current.rect, innerWidth: current.innerWidth, viewWidth: view.bounds.width)
        let size = CGSize(width: Chrome.offerWidth, height: PasswordOfferModel.height(for: current.offer))
        // A field scrolled out of the page hides the panel until it is back; the offer itself stays.
        guard let placement = PasswordOfferPlacement.place(field: field, bounds: view.bounds.size, panel: size, gap: Chrome.offerGap, margin: Radius.gutter) else {
            panel.hide(); return
        }
        let top = placement.frame
        let local = view.isFlipped ? top : NSRect(x: top.minX, y: view.bounds.height - top.maxY, width: top.width, height: top.height)
        panel.show(in: host, above: view, frame: host.convert(local, from: view), edge: placement.edge)
        if announced != current.field {
            announced = current.field
            NSAccessibility.post(element: view, notification: .announcementRequested, userInfo: [
                .announcement: owner.text("предложение пароля. стрелка вниз выбирает, Esc закрывает", "Предложение пароля. Стрелка вниз выбирает, Esc закрывает"),
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ])
        }
    }

    private func conceal() {
        panel?.hide()
        watch = nil
        if let field = scriptField { setScript(active: false, field: field) }
    }

    private func watchWindow(_ owner: BrowserModel) {
        guard watch == nil else { return }
        // objectWillChange fires before the change; the main queue sees the new state.
        watch = owner.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.render() }
    }

    private func setScript(active: Bool, field: Int) {
        guard (active ? field : nil) != scriptField, let view = tab?.webView else { return }
        scriptField = active ? field : nil
        Task { _ = try? await view.callAsyncJavaScript("return globalThis.micaOfferActive && globalThis.micaOfferActive(id, on)", arguments: ["id": field, "on": active], in: nil, contentWorld: world) }
    }

    private func choose(_ choice: PasswordOfferModel.Choice) {
        guard let current, let tab, let owner = tab.owner, let view = tab.webView, Origin.string(view.url) == current.origin else { return }
        let manager = owner.store.passwords
        switch choice {
        case .account(let login):
            session.apply(.accept)
            fill(view, username: login.username, password: login.password)
            manager.update { vault in if let index = vault.logins.firstIndex(where: { $0.id == login.id }) { vault.logins[index].used = Date() } }
        case .use(let password):
            session.apply(.accept)
            fill(view, username: nil, password: password)
        case .never:
            session.apply(.dismiss)
            let origin = current.origin
            manager.update { if !$0.never.contains(origin) { $0.never.append(origin) } }
        case .dismiss:
            session.apply(.dismiss)
        }
        render()
        // A click on the panel must leave the keyboard where it was: in the page's field.
        if let window = view.window, window.firstResponder !== view { window.makeFirstResponder(view) }
    }

    // MARK: Saving after a sign-in

    private func submitted(_ body: [String: Any], origin: String, owner: BrowserModel, tab: Tab) {
        guard owner.store.preferences.offerPasswords, let password = body["password"] as? String, !password.isEmpty,
              let username = body["username"] as? String else { return }
        let manager = owner.store.passwords
        guard !manager.loading, manager.error == nil else { return }
        switch manager.vault.capture(origin: origin, username: username, password: password) {
        case .known, .blocked: return
        case .new, .changed: break
        }
        session.apply(.leave); current = nil; render()
        // A form submission alone cannot prove that authentication succeeded.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self, weak owner] in
            guard let self, let owner, !self.presenting, owner.selectedID == tab.id else { return }
            self.present(.save(username: username), origin: origin, owner: owner) { answer in
                switch answer {
                case .save: manager.update { $0.save(origin: origin, username: username, password: password) }
                case .never: manager.update { if !$0.never.contains(origin) { $0.never.append(origin) } }
                default: break
                }
            }
        }
    }

    /// The card waits for its answer; another overlay or a system sheet on the window means mica does not ask now.
    /// The page gives up keyboard focus meanwhile so Return and Esc reach the card, as they reached the sheet before.
    private func present(_ kind: PasswordRequest.Kind, origin: String, owner: BrowserModel, completion: @escaping (PasswordRequest.Answer) -> Void) {
        guard let window = owner.controller?.window, window.attachedSheet == nil, !owner.modal, !owner.commandBar else { return }
        presenting = true
        window.makeFirstResponder(nil)
        owner.passwordPrompt = PasswordRequest(origin: origin, kind: kind) { [weak self] answer in self?.presenting = false; completion(answer) }
    }

    private func fill(_ view: WKWebView, username: String?, password: String) {
        Task { _ = try? await view.callAsyncJavaScript("return globalThis.micaFill(username, password)", arguments: ["username": username as Any? ?? NSNull(), "password": password], in: nil, contentWorld: world) }
    }

    /// Reports focus, geometry and keys of sign-in fields. Rectangles are in CSS pixels of the visual viewport, with
    /// `vw` the layout viewport width (`innerWidth`), so the host can scale them to its points under any zoom.
    private static let script = #"""
    (() => {
      let target = null, focused = null, field = 0, sequence = 0, active = false, armed = false, typed = false, frame = 0;
      const send = value => window.webkit.messageHandlers.micaPasswords.postMessage(value);
      const fields = form => Array.from((form || document).querySelectorAll('input'));
      const userField = form => fields(form).find(x => /^(username|email)$/i.test(x.autocomplete)) || fields(form).find(x => /^(text|email)$/i.test(x.type));
      const passwordFor = x => x.type === 'password' ? x : (x.form && userField(x.form) === x ? fields(x.form).find(i => i.type === 'password' && i.autocomplete !== 'new-password') : null);
      const geometry = () => {
        const r = focused.getBoundingClientRect(), v = window.visualViewport, scale = v ? v.scale : 1, left = v ? v.offsetLeft : 0, top = v ? v.offsetTop : 0;
        return { rect: [(r.left - left) * scale, (r.top - top) * scale, r.width * scale, r.height * scale], vw: window.innerWidth };
      };
      const move = () => {
        if (!active || !focused || frame) return;
        frame = requestAnimationFrame(() => { frame = 0; if (active && focused && focused.isConnected) send(Object.assign({ type: 'move', id: field }, geometry())); });
      };
      const sized = new ResizeObserver(move);
      document.addEventListener('focusin', e => {
        const x = e.target;
        if (!e.isTrusted || !(x instanceof HTMLInputElement) || x.disabled || x.readOnly) return;
        const pass = passwordFor(x);
        if (!pass || pass.disabled || pass.readOnly) return;
        // The page getting the keyboard back refocuses the same field without a blur first: still the same focus.
        if (x === focused) return;
        if (focused) sized.unobserve(focused);
        target = pass; focused = x; field = ++sequence; active = false; armed = false; typed = false;
        sized.observe(x);
        send(Object.assign({ type: 'focus', id: field, new: pass.autocomplete === 'new-password', max: pass.maxLength }, geometry()));
      }, true);
      document.addEventListener('focusout', e => {
        if (!e.isTrusted || e.target !== focused) return;
        const id = field, was = focused;
        // The window losing focus keeps the field active and must not end the offer; a real blur does.
        setTimeout(() => {
          if (document.activeElement === was || id !== field) return;
          sized.unobserve(was); focused = null; active = false; armed = false;
          send({ type: 'blur', id });
        }, 0);
      }, true);
      document.addEventListener('click', e => { if (e.isTrusted && focused && e.target === focused) { typed = false; send(Object.assign({ type: 'click', id: field }, geometry())); } }, true);
      // Typing hides the offer for this focus; the host hears it once, not for every key.
      document.addEventListener('input', e => { if (e.isTrusted && focused && e.target === focused && !typed) { typed = true; active = false; armed = false; send({ type: 'input', id: field }); } }, true);
      document.addEventListener('keydown', e => {
        if (!e.isTrusted || !active || !focused || e.target !== focused || e.isComposing) return;
        const stop = () => { e.preventDefault(); e.stopImmediatePropagation(); };
        if (e.key === 'Escape') { stop(); active = false; armed = false; send({ type: 'key', id: field, key: 'Escape' }); }
        else if (e.key === 'ArrowDown' || e.key === 'ArrowUp') { stop(); armed = true; send({ type: 'key', id: field, key: e.key }); }
        else if (e.key === 'Enter' && armed) { stop(); armed = false; send({ type: 'key', id: field, key: 'Enter' }); }
      }, true);
      document.addEventListener('scroll', move, { capture: true, passive: true });
      window.addEventListener('resize', move, { passive: true });
      if (window.visualViewport) { visualViewport.addEventListener('scroll', move, { passive: true }); visualViewport.addEventListener('resize', move, { passive: true }); }
      window.addEventListener('pagehide', () => { if (focused) { active = false; send({ type: 'blur', id: field }); } }, true);
      document.addEventListener('submit', e => {
        if (!e.isTrusted || !(e.target instanceof HTMLFormElement)) return;
        const inputs = fields(e.target), newPasswords = inputs.filter(x => x.type === 'password' && x.value && x.autocomplete === 'new-password');
        if (newPasswords.some(x => x.value !== newPasswords[0].value)) return;
        const pass = newPasswords[0] || inputs.find(x => x.type === 'password' && x.value);
        if (!pass) return;
        const user = userField(e.target);
        send({type:'submit', username:user ? user.value : '', password:pass.value});
      }, true);
      globalThis.micaOfferActive = (id, on) => { if (id === field) { active = on; if (!on) armed = false; else move(); } return active; };
      globalThis.micaFill = (username, password) => {
        if (!target || !target.isConnected || target.type !== 'password' || target.disabled || target.readOnly) return false;
        const set = (el, value) => { Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(el, value); el.dispatchEvent(new Event('input', {bubbles:true})); el.dispatchEvent(new Event('change', {bubbles:true})); };
        const user = target.form ? userField(target.form) : null;
        if (username !== null && user && !user.disabled && !user.readOnly) set(user, username);
        set(target, password);
        if (target.autocomplete === 'new-password' && target.form) {
          for (const other of fields(target.form)) if (other !== target && other.type === 'password' && other.autocomplete === 'new-password' && !other.value && !other.disabled && !other.readOnly) set(other, password);
        }
        return true;
      };
    })();
    """#
}
