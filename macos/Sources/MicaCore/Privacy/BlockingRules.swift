import Foundation

public enum BlockingRules {
    public static let domains = ["doubleclick.net", "googlesyndication.com", "google-analytics.com", "googletagmanager.com", "adservice.google.com", "adsystem.com", "amazon-adsystem.com", "adsrvr.org", "adnxs.com", "criteo.com", "criteo.net", "taboola.com", "outbrain.com", "scorecardresearch.com", "quantserve.com", "hotjar.com", "clarity.ms", "segment.io", "segment.com", "mixpanel.com", "amplitude.com", "connect.facebook.net", "analytics.tiktok.com", "bat.bing.com", "ads-twitter.com", "static.ads-twitter.com", "snap.licdn.com"]
    /// A listed domain excludes itself and its subdomains; matching never crosses a label boundary.
    public static func matchingExceptions(host: String, exceptions: [String]) -> [String] {
        let host = host.lowercased()
        return exceptions.filter { let domain = $0.lowercased(); return !domain.isEmpty && (host == domain || host.hasSuffix("." + domain)) }
    }
    public static func parseDomains(_ text: String) throws -> [String] {
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty && !$0.hasPrefix("#") }
        guard lines.count <= 20000, lines.allSatisfy({ $0.count <= 253 && $0.range(of: #"^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z](?:[a-z0-9-]{0,61}[a-z0-9])?$"#, options: .regularExpression) != nil }) else { throw CocoaError(.fileReadCorruptFile) }
        return Array(Set(lines)).sorted()
    }
    public static func json(exceptions: [String], domains: [String] = domains) throws -> String {
        var rules: [[String: Any]] = domains.map { domain in
            ["trigger": ["url-filter": "^https?://([^/]+\\.)?" + NSRegularExpression.escapedPattern(for: domain) + "[/:]", "load-type": ["third-party"]], "action": ["type": "block"]]
        }
        if !exceptions.isEmpty { rules.append(["trigger": ["url-filter": ".*", "if-top-url": exceptions.map { "^https?://([^/]+\\.)?" + NSRegularExpression.escapedPattern(for: $0) + "[/:]" }], "action": ["type": "ignore-previous-rules"]]) }
        return String(data: try JSONSerialization.data(withJSONObject: rules, options: [.sortedKeys]), encoding: .utf8)!
    }
}
