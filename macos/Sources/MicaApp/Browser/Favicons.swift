import AppKit
import SwiftUI
import WebKit

/// Site icons, keyed by host without `www.`. A normal profile keeps a 64 px PNG per host in Caches and reads it
/// lazily; an incognito window owns a separate instance that lives in memory only. Each host is fetched at most
/// once per session, after its page finishes loading: the page's own `<link rel=icon>` candidates are read in an
/// isolated script world and downloaded without cookies, with `/favicon.ico` as the fallback.
@MainActor
final class Favicons: ObservableObject {
    @Published private(set) var icons: [String: NSImage] = [:]
    let persistent: Bool
    private let directory: URL?
    /// Hosts fetched or being fetched this session, and hosts whose disk copy was already looked up.
    private var fetched = Set<String>()
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

    static func key(_ host: String?) -> String? {
        guard var host = host?.lowercased(), !host.isEmpty else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host.isEmpty ? nil : host
    }

    /// Safe to call from a view body: a missing icon schedules a disk read and publishes on a later turn.
    func image(for host: String?) -> NSImage? {
        guard let key = Self.key(host) else { return nil }
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

    /// Called when a main-frame navigation finishes. Repeated visits in one session reuse the first result.
    func refresh(from webView: WKWebView, page: URL) {
        guard let scheme = page.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let key = Self.key(page.host), !fetched.contains(key) else { return }
        fetched.insert(key)
        let generation = generation
        Task { [weak self, weak webView] in
            guard let webView else { return }
            let found = await Self.links(in: webView)
            guard let self, self.generation == generation else { return }
            let candidates = Self.candidates(found.links, page: page)
            guard let image = await self.download(candidates, userAgent: found.userAgent) else { return }
            guard self.generation == generation, let normalized = Self.normalize(image) else { return }
            self.icons[key] = normalized.image
            self.probed.insert(key)
            if let file = self.file(for: key), let directory = self.directory {
                let png = normalized.png
                Task.detached(priority: .utility) {
                    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    try? png.write(to: file, options: .atomic)
                }
            }
        }
    }

    /// Clearing history or cache forgets every icon, in memory and on disk; open pages fetch theirs again on the next load.
    func clear() {
        generation += 1
        icons = [:]; fetched = []; probed = []
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    private func file(for key: String) -> URL? {
        guard let directory else { return nil }
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789.-")
        let name = String(key.map { allowed.contains($0) ? $0 : "_" }.prefix(200))
        return directory.appendingPathComponent(name + ".png")
    }

    // MARK: Candidates

    struct Link: Equatable { let href: String; let sizes: String; let type: String; let touch: Bool }

    /// Reads icon links in the `.defaultClient` world, so page scripts cannot see or alter the query.
    private static func links(in webView: WKWebView) async -> (links: [Link], userAgent: String?) {
        let script = """
        const out = [];
        for (const link of document.querySelectorAll('link[rel][href]')) {
          const rel = (link.getAttribute('rel') || '').toLowerCase().split(/\\s+/);
          const icon = rel.includes('icon');
          const touch = rel.includes('apple-touch-icon') || rel.includes('apple-touch-icon-precomposed');
          if (!icon && !touch) continue;
          out.push({ href: link.href, sizes: link.getAttribute('sizes') || '', type: (link.getAttribute('type') || '').toLowerCase(), touch: !icon });
          if (out.length >= 24) break;
        }
        return JSON.stringify({ links: out, ua: navigator.userAgent });
        """
        guard let json = try? await webView.callAsyncJavaScript(script, contentWorld: .defaultClient) as? String,
              let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else { return ([], nil) }
        let links = (object["links"] as? [[String: Any]] ?? []).compactMap { item -> Link? in
            guard let href = item["href"] as? String else { return nil }
            return Link(href: href, sizes: item["sizes"] as? String ?? "", type: item["type"] as? String ?? "", touch: item["touch"] as? Bool ?? false)
        }
        return (links, object["ua"] as? String)
    }

    /// Best first: the smallest declared size of at least 32 px, PNG and ICO before SVG, then smaller sizes;
    /// `<origin>/favicon.ico` closes the list. Only http, https and data URLs are kept.
    static func candidates(_ links: [Link], page: URL) -> [URL] {
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
        if var parts = URLComponents(url: page, resolvingAgainstBaseURL: false) {
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

/// A site's favicon, slightly rounded, or its monogram until an icon is known.
struct SiteIcon: View {
    let host: String?
    @ObservedObject var favicons: Favicons
    var size: CGFloat = 16
    /// Plain monogram: the letter alone, for tiles that already draw their own plate.
    var plain = false
    var tint: Color = Palette.text2
    var body: some View {
        let image = favicons.image(for: host)
        ZStack {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
                    .transition(.opacity)
            } else {
                Monogram(host: host, size: size, plain: plain, tint: tint).transition(.opacity)
            }
        }
        .frame(width: size, height: size)
        .animation(Motion.hover, value: image != nil)
        .accessibilityHidden(true)
    }
}
