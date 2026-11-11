import Foundation

public struct FaviconLink: Equatable, Sendable {
    public let href: String
    public let sizes: String
    public let type: String
    public let touch: Bool
    public var media: String
    public var dark: Bool { media.contains("prefers-color-scheme") && media.contains("dark") }
    public init(href: String, sizes: String = "", type: String = "", touch: Bool = false, media: String = "") {
        self.href = href; self.sizes = sizes; self.type = type; self.touch = touch; self.media = media
    }
}

/// Discovers icons without executing a page or sending the site's address to an icon service.
public enum FaviconDiscovery {
    public static func bundledFile(page: String) -> String? {
        guard let url = URL(string: page), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.port == nil || url.port == (url.scheme == "http" ? 80 : 443), var host = url.host?.lowercased() else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return FaviconCatalog.files[host]
    }

    /// The provider receives only a public hostname, never a path, query, port, credentials or local address.
    public static func remoteURL(page: String) -> String? {
        guard let url = URL(string: page), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.port == nil || url.port == (url.scheme == "http" ? 80 : 443), let host = url.host?.lowercased(),
              host.range(of: #"^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z][a-z0-9-]*$"#, options: .regularExpression) != nil,
              !["local", "localhost", "internal", "lan", "home", "corp", "test", "invalid", "example", "onion"].contains(String(host.split(separator: ".").last ?? "")) else { return nil }
        return "https://icons.duckduckgo.com/ip3/" + host + ".ico"
    }

    public static func links(html: String, page: String) -> [FaviconLink] {
        let bytes = Array(html.utf8)
        var index = 0, base = page, hasBase = false
        var links: [FaviconLink] = []
        while index < bytes.count, links.count < 24 {
            if SingleFilePage.starts(bytes, index, "<!--") {
                index = SingleFilePage.find(bytes, "-->", from: index + 4).map { $0 + 3 } ?? bytes.count
                continue
            }
            guard bytes[index] == 60, index + 1 < bytes.count, SingleFilePage.isLetter(bytes[index + 1]),
                  let tag = SingleFilePage.parseTag(bytes, index) else { index += 1; continue }
            index = tag.end
            if ["script", "style", "textarea", "title"].contains(tag.name) {
                index = SingleFilePage.findInsensitive(bytes, "</" + tag.name, from: index) ?? bytes.count
                continue
            }
            if tag.name == "base", !hasBase, let href = tag.value("href"), let resolved = WebAddress.resolve(href, against: page) {
                base = resolved; hasBase = true
            }
            guard tag.name == "link", let href = tag.value("href"), !href.isEmpty else { continue }
            let rel = Set((tag.value("rel") ?? "").lowercased().split(whereSeparator: \.isWhitespace).map(String.init))
            let icon = rel.contains("icon")
            guard icon || rel.contains("apple-touch-icon") || rel.contains("apple-touch-icon-precomposed"),
                  let resolved = WebAddress.resolve(href, against: base) else { continue }
            links.append(FaviconLink(href: resolved, sizes: tag.value("sizes") ?? "", type: (tag.value("type") ?? "").lowercased(), touch: !icon, media: (tag.value("media") ?? "").lowercased()))
        }
        return links
    }

    /// Ranked against `FaviconCatalog.pixels`, the size an icon is stored and shown at, so a tile is not filled by a
    /// stretched 32 px file. Best first: a raster `rel=icon` at least that large (closest size first), then SVG, then a
    /// large apple-touch-icon (an opaque square, so only ahead of icons that would have to be stretched), then smaller
    /// files, largest first. An icon without `sizes` counts as 32 px, a touch icon as 180 px.
    public static func candidates(_ links: [FaviconLink], page: String, fallback: Bool = true) -> [String] {
        let target = FaviconCatalog.pixels
        func penalty(_ link: FaviconLink) -> Int {
            let sizes = link.sizes.lowercased()
            let vector = link.type.contains("svg") || link.href.lowercased().split(separator: "?").first?.hasSuffix(".svg") == true || link.href.lowercased().hasPrefix("data:image/svg")
            if vector { return 2000 }
            let edge = sizes.contains("any") ? 256 : sizes.split(whereSeparator: \.isWhitespace).compactMap { Int($0.split(separator: "x").first ?? "") }.max() ?? (link.touch ? 180 : 32)
            if edge < target { return 5000 + (target - edge) * 2 + (link.touch ? 1 : 0) }
            return (link.touch ? 3000 : 0) + min(edge - target, 999)
        }
        var result: [String] = []
        for link in links.enumerated().sorted(by: { (penalty($0.element), $0.offset) < (penalty($1.element), $1.offset) }).map(\.element) {
            guard let scheme = WebAddress.parse(link.href).scheme, ["http", "https", "data"].contains(scheme), !result.contains(link.href) else { continue }
            result.append(link.href)
            if result.count == 4 { break }
        }
        if fallback, let resolved = WebAddress.resolve("/favicon.ico", against: page) {
            let icon = resolved.replacingOccurrences(of: #"^(https?://)[^/]*@"#, with: "$1", options: .regularExpression)
            if let scheme = WebAddress.parse(icon).scheme, ["http", "https"].contains(scheme), !result.contains(icon) { result.append(icon) }
        }
        return result
    }
}
