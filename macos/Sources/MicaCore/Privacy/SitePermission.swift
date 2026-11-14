import Foundation

public enum SiteCapability: String, Codable, CaseIterable, Sendable {
    case camera, microphone, notifications
    /// Capabilities that capture devices and are stopped when access is revoked.
    public var captures: Bool { self != .notifications }
}

public enum Decision: String, Codable, CaseIterable, Sendable { case ask, allow, deny }

public struct SitePermission: Codable, Identifiable, Equatable, Sendable {
    public var origin: String
    public var capability: SiteCapability
    public var decision: Decision
    public var id: String { origin + ":" + capability.rawValue }
    public init(origin: String, capability: SiteCapability, decision: Decision) { self.origin = origin; self.capability = capability; self.decision = decision }
}

/// A site that opens one kind of app link without asking, after "don't ask for this site" (t.me with tg:). Kept per
/// scheme, so a site allowed to open Telegram cannot open other apps silently.
public struct AppLinkPermission: Codable, Identifiable, Hashable, Sendable {
    public var origin: String
    public var scheme: String
    public var id: String { origin + " " + scheme }
    public init(origin: String, scheme: String) { self.origin = origin; self.scheme = scheme.lowercased() }
    /// The permission for a link a page opened: the page must be a web origin and the link an app link.
    public init?(origin: String?, url: URL) {
        guard let origin, origin.hasPrefix("https://") || origin.hasPrefix("http://"), AddressParser.external(url), let scheme = url.scheme else { return nil }
        self.init(origin: origin, scheme: scheme)
    }
    public static func allows(_ list: [AppLinkPermission], origin: String?, url: URL) -> Bool {
        guard let wanted = AppLinkPermission(origin: origin, url: url) else { return false }
        return list.contains(wanted)
    }
}
