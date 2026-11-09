import AppKit
import SwiftUI
import WebKit

/// Site icons, keyed by host without `www.` plus a non-default port, so apps on different ports of localhost keep
/// their own. A normal profile keeps a 64 px PNG per key in Caches and reads it lazily; an incognito window owns a
/// separate instance that lives in memory only. The stored copy only fills the gap until a page loads: every finished
/// main-frame load reads the page's own `<link rel=icon>` candidates again in an isolated script world and downloads
/// them without cookies, with `/favicon.ico` as the fallback, and the result replaces the stored copy.
@MainActor
final class Favicons: ObservableObject {
    @Published private(set) var icons: [String: NSImage] = [:]
    let persistent: Bool
    private let directory: URL?
    /// Keys whose disk copy was already looked up.
    private var probed = Set<String>()
    private var generation = 0
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        config.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: config)
    }()
    static let pixels = 64
    static let byteLimit = 1_000_000

    init(persistent: Bool) {
        self.persistent = persistent
        if persistent {
            let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(Bundle.main.bundleIdentifier ?? "mica", isDirectory: true)
            let qa = ProcessInfo.processInfo.arguments.contains("--qa")
            directory = caches.appendingPathComponent(qa ? "Favicons-QA" : "Favicons", isDirectory: true)
        } else { directory = nil }
    }

    /// `example.com` for www.example.com and example.com:443, `localhost:8501` for http://localhost:8501/app.
    static func key(_ url: URL?) -> String? {
        guard let url, let host = site(url.host) else { return nil }
        let defaultPort = ["http": 80, "https": 443][url.scheme?.lowercased() ?? ""]
        if let port = url.port, port != defaultPort { return host + ":" + String(port) }
        return host
    }

    /// Lowercased host without `www.`; also what the monogram letter is taken from.
    static func site(_ host: String?) -> String? {
        guard var host = host?.lowercased(), !host.isEmpty else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host.isEmpty ? nil : host
    }

    /// The stored icon of the page's origin. Safe to call from a view body: a missing icon schedules a disk read and
    /// publishes on a later turn. `dark` asks for the variant a site declares for a dark color scheme, if it has one.
    func image(for url: URL?, dark: Bool = false) -> NSImage? {
        guard let base = Self.key(url) else { return nil }
        let key = dark ? base + Self.darkSuffix : base
        if let image = icons[key] { return image }
        if let file = file(for: key), !probed.contains(key) {
            probed.insert(key)
            let generation = generation
            Task.detached(priority: .utility) {
                guard let data = try? Data(contentsOf: file) else { return }
                await MainActor.run { [weak self] in
                    guard let self, self.generation == generation, self.icons[key] == nil, let image = NSImage(data: data) else { return }
                    self.icons[key] = image
                }
            }
        }
        return nil
    }

    /// Called whenever a main-frame navigation finishes; returns the icon the page declares now, or nil when it has
    /// none that loads. Nothing is reused from earlier loads, so a changed icon or another app on the same origin shows
    /// its own.
    func refresh(from webView: WKWebView, page: URL) async -> NSImage? {
        guard let scheme = page.scheme?.lowercased(), scheme == "http" || scheme == "https", let key = Self.key(page) else { return nil }
        let generation = generation
        let found = await Self.links(in: webView)
        guard self.generation == generation else { return nil }
        // Sites such as GitHub declare a white icon for dark schemes and a black one for light ones. The plain list
        // leaves the dark variants out; they are kept apart and shown only while mica itself is dark.
        let candidates = Self.candidates(found.links.filter { !$0.dark }, page: page)
        guard let image = await download(candidates, userAgent: found.userAgent) else { return nil }
        guard self.generation == generation, let normalized = Self.normalize(image) else { return nil }
        store(normalized, as: key)
        let darkLinks = found.links.filter(\.dark)
        if !darkLinks.isEmpty, let dark = await download(Self.candidates(darkLinks, page: page, fallback: false), userAgent: found.userAgent),
           self.generation == generation, let normalizedDark = Self.normalize(dark) {
            store(normalizedDark, as: key + Self.darkSuffix)
        } else if self.generation == generation { forget(key + Self.darkSuffix) }
        return normalized.image
    }

    static let darkSuffix = "~dark"

    private func store(_ normalized: (image: NSImage, png: Data), as key: String) {
        icons[key] = normalized.image
        probed.insert(key)
        if let file = file(for: key), let directory {
            let png = normalized.png
            Task.detached(priority: .utility) {
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try? png.write(to: file, options: .atomic)
            }
        }
    }

    /// The page no longer declares this variant: drop the stored copy so an older one is not shown.
    private func forget(_ key: String) {
        icons[key] = nil
        probed.insert(key)
        if let file = file(for: key) { Task.detached(priority: .utility) { try? FileManager.default.removeItem(at: file) } }
    }

    /// Clearing history or cache forgets every icon, in memory and on disk; open pages fetch theirs again on the next load.
    func clear() {
        generation += 1
        icons = [:]; probed = []
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    private func file(for key: String) -> URL? {
        guard let directory else { return nil }
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789.-")
        // The port separator becomes "_" like any other character outside the set: localhost_8501.png.
        let name = String(key.map { allowed.contains($0) ? $0 : "_" }.prefix(200))
        return directory.appendingPathComponent(name + ".png")
    }

    // MARK: Candidates

    struct Link: Equatable {
        let href: String; let sizes: String; let type: String; let touch: Bool
        var media = ""
        /// Declared for `prefers-color-scheme: dark` only.
        var dark: Bool { media.contains("prefers-color-scheme") && media.contains("dark") }
    }

    /// Reads icon links in the `.defaultClient` world, so page scripts cannot see or alter the query.
    private static func links(in webView: WKWebView) async -> (links: [Link], userAgent: String?) {
        let script = """
        const out = [];
        for (const link of document.querySelectorAll('link[rel][href]')) {
          const rel = (link.getAttribute('rel') || '').toLowerCase().split(/\\s+/);
          const icon = rel.includes('icon');
          const touch = rel.includes('apple-touch-icon') || rel.includes('apple-touch-icon-precomposed');
          if (!icon && !touch) continue;
          out.push({ href: link.href, sizes: link.getAttribute('sizes') || '', type: (link.getAttribute('type') || '').toLowerCase(), touch: !icon, media: (link.getAttribute('media') || '').toLowerCase() });
          if (out.length >= 24) break;
        }
        return JSON.stringify({ links: out, ua: navigator.userAgent });
        """
        guard let json = try? await webView.callAsyncJavaScript(script, contentWorld: .defaultClient) as? String,
              let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else { return ([], nil) }
        let links = (object["links"] as? [[String: Any]] ?? []).compactMap { item -> Link? in
            guard let href = item["href"] as? String else { return nil }
            return Link(href: href, sizes: item["sizes"] as? String ?? "", type: item["type"] as? String ?? "", touch: item["touch"] as? Bool ?? false, media: item["media"] as? String ?? "")
        }
        return (links, object["ua"] as? String)
    }

    /// Best first: the smallest declared size of at least 32 px, PNG and ICO before SVG, then smaller sizes;
    /// `<origin>/favicon.ico` closes the list unless `fallback` is false. Only http, https and data URLs are kept.
    static func candidates(_ links: [Link], page: URL, fallback: Bool = true) -> [URL] {
        func edge(_ link: Link) -> Int {
            let sizes = link.sizes.lowercased()
            if sizes.contains("any") { return 256 }
            let values = sizes.split(separator: " ").compactMap { Int($0.split(separator: "x").first ?? "") }
            if let largest = values.max() { return largest }
            return link.touch ? 180 : 32
        }
        func vector(_ link: Link) -> Bool { link.type.contains("svg") || link.href.lowercased().hasSuffix(".svg") || link.href.lowercased().hasPrefix("data:image/svg") }
        func penalty(_ link: Link) -> Int {
            let size = edge(link)
            var score = size >= 32 ? size - 32 : 1000 + (32 - size)
            if vector(link) { score += 60 }
            if link.touch { score += 20 }
            return score
        }
        var result: [URL] = []
        for link in links.sorted(by: { penalty($0) < penalty($1) }) {
            guard let url = URL(string: link.href), let scheme = url.scheme?.lowercased(), ["http", "https", "data"].contains(scheme), !result.contains(url) else { continue }
            result.append(url)
            if result.count == 4 { break }
        }
        if fallback, var parts = URLComponents(url: page, resolvingAgainstBaseURL: false) {
            parts.path = "/favicon.ico"; parts.query = nil; parts.fragment = nil; parts.user = nil; parts.password = nil
            if let fallback = parts.url, !result.contains(fallback) { result.append(fallback) }
        }
        return result
    }

    // MARK: Download

    private func download(_ candidates: [URL], userAgent: String?) async -> NSImage? {
        for url in candidates {
            guard let data = await fetch(url, userAgent: userAgent), let image = NSImage(data: data), image.isValid,
                  image.size.width > 0, image.size.height > 0 else { continue }
            return image
        }
        return nil
    }

    private func fetch(_ url: URL, userAgent: String?) async -> Data? {
        if url.scheme?.lowercased() == "data" { return Self.decodeData(url.absoluteString) }
        var request = URLRequest(url: url)
        request.httpShouldHandleCookies = false
        request.setValue("image/avif,image/webp,image/png,image/svg+xml,image/x-icon,image/*;q=0.8", forHTTPHeaderField: "Accept")
        if let userAgent { request.setValue(userAgent, forHTTPHeaderField: "User-Agent") }
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let final = http.url?.scheme?.lowercased(), final == "http" || final == "https",
                  response.expectedContentLength <= Int64(Self.byteLimit) else { bytes.task.cancel(); return nil }
            let mime = response.mimeType?.lowercased() ?? ""
            if mime.hasPrefix("text/html") { bytes.task.cancel(); return nil }
            var data = Data()
            if response.expectedContentLength > 0 { data.reserveCapacity(Int(response.expectedContentLength)) }
            for try await byte in bytes {
                data.append(byte)
                if data.count > Self.byteLimit { bytes.task.cancel(); return nil }
            }
            return data
        } catch { return nil }
    }

    static func decodeData(_ string: String) -> Data? {
        guard string.lowercased().hasPrefix("data:"), let comma = string.firstIndex(of: ",") else { return nil }
        let header = string[string.index(string.startIndex, offsetBy: 5)..<comma].lowercased()
        let payload = String(string[string.index(after: comma)...])
        guard payload.count <= byteLimit * 4 / 3 + 4 else { return nil }
        if header.hasSuffix(";base64") { return Data(base64Encoded: payload.removingPercentEncoding ?? payload, options: .ignoreUnknownCharacters) }
        return (payload.removingPercentEncoding ?? payload).data(using: .utf8)
    }

    /// Draws the icon into a 64 px square (aspect kept), so memory and the disk copy stay small whatever the source.
    static func normalize(_ image: NSImage) -> (image: NSImage, png: Data)? {
        let side = pixels
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = NSSize(width: side, height: side)
        let source = image.size
        let scale = min(CGFloat(side) / source.width, CGFloat(side) / source.height)
        let drawn = NSSize(width: source.width * scale, height: source.height * scale)
        let rect = NSRect(x: (CGFloat(side) - drawn.width) / 2, y: (CGFloat(side) - drawn.height) / 2, width: drawn.width, height: drawn.height)
        NSGraphicsContext.saveGraphicsState()
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { NSGraphicsContext.restoreGraphicsState(); return nil }
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        image.draw(in: rect, from: .zero, operation: .copy, fraction: 1)
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        guard let png = rep.representation(using: .png, properties: [:]) else { return nil }
        let result = NSImage(size: NSSize(width: side, height: side)); result.addRepresentation(rep)
        return (result, png)
    }
}

/// A site's favicon, slightly rounded, or its monogram until an icon is known. `icon`, when given, is the icon the
/// page itself declared on its latest load and wins over the stored icon of its origin.
struct SiteIcon: View {
    let url: URL?
    var icon: NSImage? = nil
    @ObservedObject var favicons: Favicons
    var size: CGFloat = 16
    /// Plain monogram: the letter alone, for tiles that already draw their own plate.
    var plain = false
    var tint: Color = Palette.text2
    /// List rows: the icon sits on the same plate as the monogram and the download kinds, at 60 % of the tile.
    var tiled = false
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        // A dark variant comes from the same load as `icon`, so it wins while mica is dark.
        let image = (scheme == .dark ? favicons.image(for: url, dark: true) : nil) ?? icon ?? favicons.image(for: url)
        let side = tiled ? (size * 0.6).rounded() : size
        ZStack {
            if let image {
                ZStack {
                    if tiled { RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).fill(Palette.track) }
                    Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: side * 0.2, style: .continuous))
                        .frame(width: side, height: side)
                }
                .transition(.opacity)
            } else {
                Monogram(host: url?.host, size: size, plain: plain, tint: tint).transition(.opacity)
            }
        }
        .frame(width: size, height: size)
        .animation(Motion.hover, value: image.map(ObjectIdentifier.init))
        .accessibilityHidden(true)
    }
}
