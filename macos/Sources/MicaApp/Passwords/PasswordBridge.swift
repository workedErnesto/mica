import AppKit
import WebKit
import MicaCore

/// Runs in a separate WebKit content world. Only the top-level HTTPS document can request actions.
@MainActor
final class PasswordBridge: NSObject, WKScriptMessageHandler {
    weak var tab: Tab?
    private var presenting = false
    private let world = WKContentWorld.world(name: "mica.passwords")
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
        if type == "focus", !presenting {
            let manager = owner.store.passwords
            if manager.loading {
                Task { [weak self, weak view] in
                    await manager.waitUntilReady()
                    guard let self, let view, Origin.string(view.url) == origin,
                          (try? await view.callAsyncJavaScript("return globalThis.micaPasswordTargetFocused()", arguments: [:], in: nil, contentWorld: self.world)) as? Bool == true else { return }
                    self.userContentController(userContentController, didReceive: message)
                }
                return
            }
            guard manager.error == nil else { return }
            let isNew = body["new"] as? Bool == true
            let maximum = body["max"] as? Int ?? -1
            if isNew, owner.store.preferences.offerPasswords, maximum < 0 || maximum >= 8 {
                let password = PasswordGenerator.strong(maxLength: maximum > 0 ? maximum : nil)
                let alert = NSAlert(); alert.messageText = owner.text("создать стойкий пароль?", "Создать стойкий пароль?")
                alert.informativeText = password
                alert.addButton(withTitle: owner.text("использовать", "Использовать")); alert.addButton(withTitle: owner.text("не сейчас", "Не сейчас"))
                present(alert, owner: owner) { [weak self, weak view] result in
                    guard result == .alertFirstButtonReturn, let self, let view, Origin.string(view.url) == origin else { return }
                    self.fill(view, username: nil, password: password)
                }
            } else if !isNew, owner.store.preferences.fillPasswords {
                let matches = owner.store.passwords.vault.matches(for: origin)
                guard !matches.isEmpty else { return }
                let alert = NSAlert(); alert.messageText = owner.text("заполнить учётную запись?", "Заполнить учётную запись?")
                alert.informativeText = origin
                let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 280, height: 26))
                popup.addItems(withTitles: matches.map { $0.username.isEmpty ? owner.text("без имени пользователя", "Без имени пользователя") : $0.username })
                alert.accessoryView = popup
                alert.addButton(withTitle: owner.text("заполнить", "Заполнить")); alert.addButton(withTitle: owner.text("не сейчас", "Не сейчас"))
                present(alert, owner: owner) { [weak self, weak view] result in
                    guard result == .alertFirstButtonReturn, let self, let view, Origin.string(view.url) == origin, matches.indices.contains(popup.indexOfSelectedItem) else { return }
                    let login = matches[popup.indexOfSelectedItem]
                    self.fill(view, username: login.username, password: login.password)
                    owner.store.passwords.update { vault in if let index = vault.logins.firstIndex(where: { $0.id == login.id }) { vault.logins[index].used = Date() } }
                }
            }
        } else if type == "submit", owner.store.preferences.offerPasswords,
                  let password = body["password"] as? String, !password.isEmpty,
                  let username = body["username"] as? String {
            let manager = owner.store.passwords
            guard !manager.loading, manager.error == nil else { return }
            switch manager.vault.capture(origin: origin, username: username, password: password) {
            case .known, .blocked: return
            case .new, .changed: break
            }
            // A form submission alone cannot prove that authentication succeeded.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self, weak owner] in
                guard let self, let owner, !self.presenting, owner.selectedID == tab.id else { return }
                let alert = NSAlert(); alert.messageText = owner.text("сохранить пароль?", "Сохранить пароль?")
                alert.informativeText = origin + (username.isEmpty ? "" : "\n" + username)
                alert.addButton(withTitle: owner.text("сохранить", "Сохранить")); alert.addButton(withTitle: owner.text("не сейчас", "Не сейчас")); alert.addButton(withTitle: owner.text("никогда для этого сайта", "Никогда для этого сайта"))
                self.present(alert, owner: owner) { result in
                    if result == .alertFirstButtonReturn { manager.update { $0.save(origin: origin, username: username, password: password) } }
                    else if result == .alertThirdButtonReturn { manager.update { if !$0.never.contains(origin) { $0.never.append(origin) } } }
                }
            }
        }
    }
    private func present(_ alert: NSAlert, owner: BrowserModel, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        guard let window = owner.controller?.window, window.attachedSheet == nil else { return }
        presenting = true
        alert.beginSheetModal(for: window) { [weak self] result in self?.presenting = false; completion(result) }
    }
    private func fill(_ view: WKWebView, username: String?, password: String) {
        Task { _ = try? await view.callAsyncJavaScript("return globalThis.micaFill(username, password)", arguments: ["username": username as Any? ?? NSNull(), "password": password], in: nil, contentWorld: world) }
    }
    private static let script = #"""
    (() => {
      let target = null;
      const send = value => window.webkit.messageHandlers.micaPasswords.postMessage(value);
      const fields = form => Array.from((form || document).querySelectorAll('input'));
      const userField = form => fields(form).find(x => /^(username|email)$/i.test(x.autocomplete)) || fields(form).find(x => /^(text|email)$/i.test(x.type));
      document.addEventListener('focusin', e => {
        const x = e.target;
        if (!e.isTrusted || !(x instanceof HTMLInputElement) || x.disabled || x.readOnly) return;
        const pass = x.type === 'password' ? x : (x.form && userField(x.form) === x ? fields(x.form).find(i => i.type === 'password' && i.autocomplete !== 'new-password') : null);
        if (!pass || pass.disabled || pass.readOnly) return;
        target = pass;
        send({type:'focus', new:pass.autocomplete === 'new-password', max:pass.maxLength});
      }, true);
      document.addEventListener('submit', e => {
        if (!e.isTrusted || !(e.target instanceof HTMLFormElement)) return;
        const inputs = fields(e.target), newPasswords = inputs.filter(x => x.type === 'password' && x.value && x.autocomplete === 'new-password');
        if (newPasswords.some(x => x.value !== newPasswords[0].value)) return;
        const pass = newPasswords[0] || inputs.find(x => x.type === 'password' && x.value);
        if (!pass) return;
        const user = userField(e.target);
        send({type:'submit', username:user ? user.value : '', password:pass.value});
      }, true);
      globalThis.micaPasswordTargetFocused = () => !!target && target.isConnected && (document.activeElement === target || (target.form && document.activeElement === userField(target.form)));
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
