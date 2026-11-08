import Foundation

/// State reported to the page as `Notification.permission`.
public enum NotificationState: String, Sendable { case granted, denied, `default` }

/// A notification a page asked to show, validated before it reaches the system.
public struct WebNotification: Equatable, Sendable {
    public static let titleLimit = 200
    public static let bodyLimit = 1000
    public static let tagLimit = 200
    public var id: String
    public var title: String
    public var body: String
    public var tag: String
    public var silent: Bool
    public init(id: String, title: String, body: String = "", tag: String = "", silent: Bool = false) {
        self.id = id; self.title = title; self.body = body; self.tag = tag; self.silent = silent
    }
    /// Reads a message posted by the page script. Untrusted: wrong types, empty titles and odd ids are rejected,
    /// long text is cut, control characters are removed.
    public static func parse(_ message: [String: Any]) -> WebNotification? {
        guard let id = message["id"] as? String, id.count <= 64, !id.isEmpty,
              id.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || $0 == "-" }),
              let rawTitle = message["title"] as? String else { return nil }
        let title = clean(rawTitle, limit: titleLimit)
        guard !title.isEmpty else { return nil }
        return WebNotification(id: id, title: title, body: clean(message["body"] as? String ?? "", limit: bodyLimit),
                               tag: clean(message["tag"] as? String ?? "", limit: tagLimit), silent: message["silent"] as? Bool ?? false)
    }
    static func clean(_ text: String, limit: Int) -> String {
        let kept = text.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) || $0 == "\n" }
        return String(String(String.UnicodeScalarView(kept)).trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
    }
}

public enum NotificationPolicy {
    /// What the page sees. Incognito windows refuse, like other browsers; a refusal from the system is not hidden.
    public static func state(origin: String?, privateMode: Bool, permissions: [SitePermission]) -> NotificationState {
        guard let origin, Origin.secure(origin), !privateMode else { return .denied }
        switch permissions.first(where: { $0.origin == origin && $0.capability == .notifications })?.decision ?? .ask {
        case .allow: return .granted
        case .deny: return .denied
        case .ask: return .default
        }
    }
    /// A new request may show a question only from a secure top-level page of the selected tab in a normal window,
    /// after a user gesture, while requests are allowed in settings.
    public static func mayAsk(origin: String?, privateMode: Bool, selected: Bool, userGesture: Bool, requestsAllowed: Bool) -> Bool {
        guard let origin, Origin.secure(origin) else { return false }
        return !privateMode && selected && userGesture && requestsAllowed
    }
    /// System identifier. Notifications with the same tag from one origin replace each other, as the standard asks.
    public static func identifier(origin: String, tab: UUID, notification: WebNotification) -> String {
        notification.tag.isEmpty ? "\(origin)|\(tab.uuidString)|\(notification.id)" : "\(origin)|tag|\(notification.tag)"
    }
}
