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
            if external(u) { return .external(u) }
            return .rejected("unsupported scheme")
        }
        if !text.contains(where: { $0.isWhitespace }),
           (text.contains(".") || text.hasPrefix("localhost") || text.hasPrefix("[::1]")),
           let u = URL(string: (text.hasPrefix("localhost") || text.hasPrefix("127.") || text.hasPrefix("[::1]") ? "http://" : "https://") + text), let host = u.host, !host.isEmpty {
            return .web(u)
        }
        return .web(engine.search(text))
    }
    /// File types mica shows when the system hands it a file. PDF is registered on Windows and as an alternative viewer on macOS.
    public static let fileExtensions: Set<String> = ["html", "htm", "xhtml", "xht", "pdf"]
    /// A local file the system opened in mica (Finder, Dock, Explorer, a restored tab of such a file). Never part of
    /// `navigable` and never produced by `resolve`: typed text and web pages cannot reach local files.
    /// Network shares (a host other than localhost), queries and credentials are refused.
    public static func openableFile(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "file", url.user == nil, url.password == nil, url.query == nil else { return false }
        let host = url.host?.lowercased() ?? ""
        guard host.isEmpty || host == "localhost" else { return false }
        let path = url.path
        guard path.hasPrefix("/"), !url.hasDirectoryPath, !path.hasSuffix("/") else { return false }
        return fileExtensions.contains(url.pathExtension.lowercased())
    }
    /// Schemes mica never hands to another app: its own web and local content, schemes that run code or carry a
    /// document inside the address, and system settings, which pages do not open.
    public static let refusedSchemes: Set<String> = ["http", "https", "file", "about", "blob", "data", "javascript", "vbscript",
        "view-source", "filesystem", "ws", "wss", "webkit-extension", "safari-web-extension", "chrome", "chrome-extension", "edge", "mica",
        "x-apple.systempreferences", "ms-settings"]
    /// A link for another app (tg:, mailto:, zoommtg:, slack:...). The system decides which app opens it; mica asks
    /// first and says when no app is installed.
    public static func external(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), !scheme.isEmpty, !refusedSchemes.contains(scheme) else { return false }
        return url.absoluteString.count <= 8192
    }
    /// Inline srcdoc documents belong to a child frame; they are never top-level addresses.
    public static func navigable(_ url: URL, mainFrame: Bool = true) -> Bool {
        switch url.scheme?.lowercased() {
        case "http", "https": return url.host?.isEmpty == false && url.user == nil && url.password == nil
        case "about": return url.absoluteString == "about:blank" || (!mainFrame && url.absoluteString == "about:srcdoc")
        case "blob": return true
        default: return false
        }
    }
}
