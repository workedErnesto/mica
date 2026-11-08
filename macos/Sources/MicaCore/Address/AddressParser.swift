import Foundation

public enum AddressTarget: Equatable, Sendable { case web(URL), external(URL), rejected(String) }

public enum AddressParser {
    public static func resolve(_ input: String, engine: SearchEngine = .duckduckgo) -> AddressTarget {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .rejected("empty") }
        if text.range(of: #"^[A-Za-z][A-Za-z0-9+.-]*:"#, options: .regularExpression) != nil,
           !text.hasPrefix("localhost:"), text.range(of: #"^[\w.-]+:\d+(/|$)"#, options: .regularExpression) == nil {
            guard let u = URL(string: text), let scheme = u.scheme?.lowercased() else { return .rejected("invalid URL") }
            if ["https", "http"].contains(scheme), let host = u.host, !host.isEmpty, u.user == nil, u.password == nil { return .web(u) }
            if ["mailto", "tel"].contains(scheme) { return .external(u) }
            return .rejected("unsupported scheme")
        }
        if !text.contains(where: { $0.isWhitespace }),
           (text.contains(".") || text.hasPrefix("localhost") || text.hasPrefix("[::1]")),
           let u = URL(string: (text.hasPrefix("localhost") || text.hasPrefix("127.") || text.hasPrefix("[::1]") ? "http://" : "https://") + text), let host = u.host, !host.isEmpty {
            return .web(u)
        }
        return .web(engine.search(text))
    }
    public static func navigable(_ url: URL) -> Bool {
        switch url.scheme?.lowercased() {
        case "http", "https": return url.host?.isEmpty == false && url.user == nil && url.password == nil
        case "about": return url.absoluteString == "about:blank"
        case "blob": return true
        default: return false
        }
    }
}
