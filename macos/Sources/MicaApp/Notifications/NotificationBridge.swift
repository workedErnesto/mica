import AppKit
import WebKit
import MicaCore

extension WKSecurityOrigin {
    /// Same form as `Origin.string`, so decisions match the address bar.
    var key: String? {
        var parts = URLComponents(); parts.scheme = self.protocol; parts.host = host
        if port > 0 { parts.port = port }
        return Origin.string(parts.url)
    }
}

/// The Notifications API for pages. Public WebKit has no notification delegate for WKWebView on macOS, so the page
/// world gets a standard `Notification` object whose calls come here through a message handler. Every call is checked
/// again on this side: top-level document, secure origin matching the address, saved decision. Page notifications from
/// open tabs are supported; push and service worker events are not, because nothing runs when the page is closed.
@MainActor
final class NotificationBridge: NSObject, WKScriptMessageHandlerWithReply {
    weak var tab: Tab?
    static let name = "micaNotifications"
    private var delivered: [String: String] = [:]
    /// Origins that got "not now" in this tab. A page cannot prove a user gesture, so it may not ask again until reopened.
    private var postponed = Set<String>()
    private var asking = false
    init(tab: Tab, controller: WKUserContentController, privateMode: Bool, permissions: [SitePermission]) {
        self.tab = tab
        super.init()
        controller.addScriptMessageHandler(self, contentWorld: .page, name: Self.name)
        controller.addUserScript(WKUserScript(source: Self.script(privateMode: privateMode, permissions: permissions), injectionTime: .atDocumentStart, forMainFrameOnly: true, in: .page))
    }
    func detach(from controller: WKUserContentController) {
        controller.removeScriptMessageHandler(forName: Self.name, contentWorld: .page)
        tab?.owner?.store.notifier.remove(Array(delivered.values)); delivered.removeAll()
    }
    static func state(of tab: Tab) -> NotificationState {
        guard let owner = tab.owner else { return .denied }
        return NotificationPolicy.state(origin: Origin.string(tab.webView?.url ?? tab.url), privateMode: owner.privateMode, permissions: owner.store.permissions)
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage, replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void) {
        // A popup shares its opener's content controller, so the sender is found by its web view.
        guard let opener = self.tab, let owner = opener.owner, let tab = owner.tabs.first(where: { $0.webView != nil && $0.webView === message.webView }),
              let view = tab.webView, message.frameInfo.isMainFrame,
              let origin = message.frameInfo.securityOrigin.key, origin == Origin.string(view.url),
              let body = message.body as? [String: Any], let type = body["type"] as? String else { replyHandler(nil, "denied"); return }
        let state = { NotificationBridge.state(of: tab) }
        switch type {
        case "state": replyHandler(state().rawValue, nil)
        case "request":
            let current = state()
            guard current == .default else { replyHandler(current.rawValue, nil); return }
            guard owner.store.preferences.notificationRequests else { replyHandler(NotificationState.denied.rawValue, nil); return }
            let selected = owner.selectedID == tab.id && owner.controller?.window?.isKeyWindow == true
            guard NotificationPolicy.mayAsk(origin: origin, privateMode: owner.privateMode, selected: selected, userGesture: body["gesture"] as? Bool == true, requestsAllowed: true),
                  !postponed.contains(origin), !asking else { replyHandler(current.rawValue, nil); return }
            asking = true
            Task {
                let answer = await ask(title: origin + ": " + owner.text("уведомления", "Уведомления"),
                                       detail: owner.text("сайт хочет показывать уведомления, пока вкладка открыта. macOS отдельно спросит разрешение для mica.", "Сайт хочет показывать уведомления, пока вкладка открыта. macOS отдельно спросит разрешение для mica."),
                                       buttons: [owner.text("не сейчас", "Не сейчас"), owner.text("запретить", "Запретить"), owner.text("разрешить", "Разрешить")], window: owner.controller?.window)
                asking = false
                switch answer {
                case 2:
                    guard await owner.store.notifier.authorize() else {
                        owner.message = owner.text("macOS запрещает уведомления mica. разрешите их в системных настройках, раздел «уведомления».", "macOS запрещает уведомления mica. Разрешите их в системных настройках, раздел «Уведомления».")
                        replyHandler(NotificationState.default.rawValue, nil); return
                    }
                    owner.store.setPermission(origin: origin, capability: .notifications, decision: .allow)
                case 1: owner.store.setPermission(origin: origin, capability: .notifications, decision: .deny)
                default: postponed.insert(origin)
                }
                replyHandler(state().rawValue, nil)
            }
        case "show":
            guard state() == .granted, let notification = WebNotification.parse(body) else { replyHandler(false, nil); return }
            Task {
                let identifier = await owner.store.notifier.show(notification, origin: origin, tab: tab)
                if let identifier { delivered[notification.id] = identifier }
                replyHandler(identifier != nil, nil)
            }
        case "close":
            if let id = body["id"] as? String, let identifier = delivered.removeValue(forKey: id) { owner.store.notifier.remove([identifier]) }
            replyHandler(true, nil)
        default: replyHandler(nil, "unknown")
        }
    }
    /// Tells an open page about a changed decision; new pages read it from the user script.
    static func push(_ tab: Tab) {
        tab.webView?.evaluateJavaScript("globalThis[Symbol.for('mica.notifications')]?.('state', '\(state(of: tab).rawValue)')", in: nil, in: .page, completionHandler: nil)
    }
    static func dispatch(_ tab: Tab, id: String, event: String) {
        if event == "close" { tab.notifications?.delivered.removeValue(forKey: id) }
        tab.webView?.callAsyncJavaScript("globalThis[Symbol.for('mica.notifications')]?.(event, id)", arguments: ["event": event, "id": id], in: nil, in: .page, completionHandler: nil)
    }
    static func script(privateMode: Bool, permissions: [SitePermission]) -> String {
        var states: [String: String] = [:]
        for record in permissions where record.capability == .notifications && record.decision != .ask { states[record.origin] = record.decision == .allow ? "granted" : "denied" }
        let json = (try? JSONSerialization.data(withJSONObject: states)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return "(() => { const STATES = \(json); const PRIVATE = \(privateMode);\n" + source + "\n})();"
    }
    private static let source = #"""
    const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.micaNotifications;
    if (!handler) return;
    const post = message => handler.postMessage(message);
    let state = location.protocol === 'https:' && !PRIVATE ? (STATES[location.origin] || 'default') : 'denied';
    const live = new Map(), ids = new WeakMap(), statuses = new Set();
    let counter = 0;
    const fire = (target, type) => {
      const event = new Event(type);
      const handlerProperty = target['on' + type];
      if (typeof handlerProperty === 'function') { try { handlerProperty.call(target, event); } catch (error) { setTimeout(() => { throw error; }); } }
      target.dispatchEvent(event);
    };
    const setState = value => {
      if (value !== 'granted' && value !== 'denied' && value !== 'default') return;
      if (value === state) return;
      state = value;
      for (const status of statuses) fire(status, 'change');
    };
    const text = value => value == null ? '' : String(value);
    const newID = () => (++counter) + '-' + Math.random().toString(36).slice(2, 10);
    class Notification extends EventTarget {
      constructor(title, options) {
        super();
        if (arguments.length === 0) throw new TypeError("Failed to construct 'Notification': 1 argument required, but only 0 present.");
        const o = options || {};
        this.title = String(title); this.body = text(o.body); this.tag = text(o.tag); this.data = o.data === undefined ? null : o.data;
        this.dir = o.dir || 'auto'; this.lang = text(o.lang); this.icon = text(o.icon); this.badge = text(o.badge); this.image = text(o.image);
        this.silent = o.silent === undefined ? null : !!o.silent; this.requireInteraction = !!o.requireInteraction; this.renotify = !!o.renotify;
        this.timestamp = typeof o.timestamp === 'number' ? o.timestamp : Date.now(); this.actions = []; this.vibrate = [];
        this.onclick = null; this.onshow = null; this.onerror = null; this.onclose = null;
        const id = newID(); ids.set(this, id);
        if (state !== 'granted') { setTimeout(() => fire(this, 'error')); return; }
        live.set(id, this);
        post({ type: 'show', id, title: this.title, body: this.body, tag: this.tag, silent: !!this.silent }).then(ok => {
          if (ok) fire(this, 'show'); else { live.delete(id); fire(this, 'error'); }
        }, () => { live.delete(id); fire(this, 'error'); });
      }
      close() {
        const id = ids.get(this);
        if (!live.delete(id)) return;
        post({ type: 'close', id }).catch(() => {});
        fire(this, 'close');
      }
      static get permission() { return state; }
      static get maxActions() { return 0; }
      static requestPermission(callback) {
        const finish = value => { setState(value); if (typeof callback === 'function') callback(state); return state; };
        if (state !== 'default') return Promise.resolve(finish(state));
        const gesture = !!(navigator.userActivation && navigator.userActivation.isActive);
        return post({ type: 'request', gesture }).then(finish, () => finish('default'));
      }
    }
    Object.defineProperty(window, 'Notification', { value: Notification, writable: true, configurable: true, enumerable: false });
    Object.defineProperty(globalThis, Symbol.for('mica.notifications'), { value: (kind, value) => {
      if (kind === 'state') { setState(value); return; }
      const target = live.get(value);
      if (!target) return;
      if (kind === 'close') live.delete(value);
      if (kind === 'click' || kind === 'close') fire(target, kind);
    } });
    if (navigator.permissions && navigator.permissions.query) {
      const query = navigator.permissions.query.bind(navigator.permissions);
      navigator.permissions.query = function (descriptor) {
        if (!descriptor || descriptor.name !== 'notifications') return query(descriptor);
        const status = new EventTarget();
        Object.defineProperty(status, 'state', { get: () => state === 'default' ? 'prompt' : state });
        Object.defineProperty(status, 'name', { value: 'notifications' });
        status.onchange = null;
        statuses.add(status);
        return Promise.resolve(status);
      };
    }
    if (window.ServiceWorkerRegistration) {
      // Shown from the page side; notificationclick never reaches the service worker, a click focuses the tab.
      ServiceWorkerRegistration.prototype.showNotification = function (title, options) {
        if (state !== 'granted') return Promise.reject(new TypeError('No notification permission has been granted for this origin.'));
        const o = options || {};
        return post({ type: 'show', id: newID(), title: String(title), body: text(o.body), tag: text(o.tag), silent: !!o.silent }).then(ok => {
          if (!ok) throw new TypeError('The notification could not be shown.');
        });
      };
      ServiceWorkerRegistration.prototype.getNotifications = function () { return Promise.resolve([]); };
    }
    post({ type: 'state' }).then(setState, () => {});
    """#
}
