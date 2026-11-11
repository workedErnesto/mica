import AppKit
import MicaCore
import SwiftUI
import WebKit

/// Site icons, keyed by host without `www.` plus a non-default port, so apps on different ports of localhost keep
/// their own. A normal profile keeps a 64 px PNG per key in Caches and reads it lazily; an incognito window owns a
/// separate instance that lives in memory only. The stored copy only fills the gap until a page loads: every finished
/// main-frame load reads the page's own `<link rel=icon>` candidates again in an isolated script world. Same-origin
/// requests use WebKit's session; other requests stay anonymous. Missing icons are discovered in the background.
@MainActor
final class Favicons: ObservableObject {
    @Published private(set) var icons: [String: NSImage] = [:]
    let persistent: Bool
    private let directory: URL?
    /// Keys whose disk copy was already looked up.
    private var probed = Set<String>()
    private var generation = 0
    private var refreshes: [String: UUID] = [:]
    private let diskQueue = DispatchQueue(label: "app.mica.favicons.disk", qos: .utility)
    private let suppliedSession: URLSession?
    private lazy var session: URLSession = {
        if let suppliedSession { return suppliedSession }
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
    private let glyphs = NSCache<NSImage, Glyph>()
    private final class Glyph { let luminance: Double?; init(_ luminance: Double?) { self.luminance = luminance } }

    init(persistent: Bool, session: URLSession? = nil) {
        self.persistent = persistent
        suppliedSession = session
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

    /// A miss starts a bounded background lookup, including sites that have never been opened.
    func image(for url: URL?, dark: Bool = false) -> NSImage? {
        guard let url, let base = Self.key(url) else { return nil }
        let key = dark ? base + Self.darkSuffix : base
        if let image = icons[key] { return image }
        Task { [weak self] in self?.prefetch(url) }
        return nil
    }

    private var pending: [(String, URL)] = []
    private var requests: [String: Task<Void, Never>] = [:]
    private var attempted: [String: Date] = [:]

    func prefetch(_ page: URL) {
        guard ["http", "https"].contains(page.scheme?.lowercased() ?? ""), let key = Self.key(page), icons[key] == nil,
              requests[key] == nil, !pending.contains(where: { $0.0 == key }),
              attempted[key].map({ Date().timeIntervalSince($0) >= 60 }) ?? true else { return }
        pending.append((key, page))
        pump()
    }

    private func pump() {
        while requests.count < 4, !pending.isEmpty {
            let (key, page) = pending.removeFirst()
            let generation = generation
            requests[key] = Task { [weak self] in
                guard let self else { return }
                defer {
                    if self.generation == generation { self.requests[key] = nil; self.attempted[key] = Date(); self.pump() }
                }
                if !self.probed.contains(key) {
                    self.probed.insert(key)
                    for storedKey in [key, key + Self.darkSuffix] {
                        guard let file = self.file(for: storedKey) else { continue }
                        let data = await self.read(file)
                        guard self.generation == generation, !Task.isCancelled else { return }
                        if self.icons[storedKey] == nil, let data, let image = NSImage(data: data), let normalized = Self.normalize(image) { self.icons[storedKey] = normalized.image }
                    }
                }
                guard self.icons[key] == nil else { return }
                if let name = FaviconDiscovery.bundledFile(page: page.absoluteString),
                   let file = Bundle.main.url(forResource: name, withExtension: nil, subdirectory: "Favicons"),
                   let data = await self.read(file), let image = NSImage(data: data), let normalized = Self.normalize(image),
                   self.generation == generation, !Task.isCancelled, self.icons[key] == nil {
                    self.store(normalized, as: key)
                    return
                }
                // Root only: background discovery must not replay a saved form/action URL or its query.
                guard var parts = URLComponents(url: page, resolvingAgainstBaseURL: false) else { return }
                parts.path = "/"; parts.query = nil; parts.fragment = nil; parts.user = nil; parts.password = nil
                guard let root = parts.url else { return }
                for delay in [0, 2, 8] {
                    if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
                    guard self.generation == generation, !Task.isCancelled, self.icons[key] == nil else { return }
                    let document = await self.fetch(root, userAgent: nil, html: true)
                    let links = document.map { FaviconDiscovery.links(html: String(decoding: $0.data, as: UTF8.self), page: $0.url.absoluteString) } ?? []
                    let resolved = document?.url ?? root
                    if let image = await self.download(Self.candidates(links.filter { !$0.dark }, page: resolved), userAgent: nil),
                       self.generation == generation, !Task.isCancelled, self.icons[key] == nil, let normalized = Self.normalize(image) {
                        self.store(normalized, as: key)
                        if let dark = await self.download(Self.candidates(links.filter(\.dark), page: resolved, fallback: false), userAgent: nil),
                           self.generation == generation, !Task.isCancelled, self.icons[key] === normalized.image,
                           let normalizedDark = Self.normalize(dark) { self.store(normalizedDark, as: key + Self.darkSuffix) }
                        return
                    }
                    if let remote = FaviconDiscovery.remoteURL(page: page.absoluteString).flatMap(URL.init(string:)),
                       let image = await self.download([remote], userAgent: nil), let normalized = Self.normalize(image),
                       self.generation == generation, !Task.isCancelled, self.icons[key] == nil {
                        self.store(normalized, as: key)
                        return
                    }
                }
            }
        }
    }

    /// Called whenever a main-frame navigation finishes; returns the icon the page declares now, or nil when it has
    /// none that loads. Nothing is reused from earlier loads, so a changed icon or another app on the same origin shows
    /// its own.
    func refresh(from webView: WKWebView, page: URL) async -> NSImage? {
        guard let scheme = page.scheme?.lowercased(), scheme == "http" || scheme == "https", let key = Self.key(page) else { return nil }
        let generation = generation, revision = UUID()
        refreshes[key] = revision
        let found = await Self.links(in: webView)
        guard self.generation == generation, refreshes[key] == revision, webView.url == page else { return nil }
        // Sites such as GitHub declare a white icon for dark schemes and a black one for light ones. The plain list
        // leaves the dark variants out; they are kept apart and shown only while mica itself is dark.
        let candidates = Self.candidates(found.links.filter { !$0.dark }, page: page)
        guard let image = await download(candidates, userAgent: found.userAgent, webView: webView, page: page) else { return nil }
        guard self.generation == generation, refreshes[key] == revision, webView.url == page, let normalized = Self.normalize(image) else { return nil }
        store(normalized, as: key)
        let darkLinks = found.links.filter(\.dark)
        if !darkLinks.isEmpty, let dark = await download(Self.candidates(darkLinks, page: page, fallback: false), userAgent: found.userAgent, webView: webView, page: page),
           self.generation == generation, refreshes[key] == revision, webView.url == page, let normalizedDark = Self.normalize(dark) {
            store(normalizedDark, as: key + Self.darkSuffix)
        } else if self.generation == generation, refreshes[key] == revision, webView.url == page { forget(key + Self.darkSuffix) }
        return normalized.image
    }

    static let darkSuffix = "~dark"

    /// Luminance of a neutral one-colour glyph on transparency (FaviconTone), measured once per image; nil for icons
    /// with colours, several tones or their own backdrop.
    func glyph(_ image: NSImage) -> Double? {
        if let known = glyphs.object(forKey: image) { return known.luminance }
        let luminance = Self.measure(image)
        glyphs.setObject(Glyph(luminance), forKey: image)
        return luminance
    }

    /// Reads the icon at the stored 64 px as straight-alpha sRGB, the form FaviconTone expects.
    static func measure(_ image: NSImage) -> Double? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil), let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let side = pixels
        var data = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                          space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .high
            context.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }
        for index in stride(from: 0, to: data.count, by: 4) {
            let alpha = Int(data[index + 3])
            guard alpha > 0, alpha < 255 else { continue }
            for channel in 0..<3 { data[index + channel] = UInt8(min(255, (Int(data[index + channel]) * 255 + alpha / 2) / alpha)) }
        }
        return FaviconTone.glyph(rgba: data)
    }

    private func store(_ normalized: (image: NSImage, png: Data), as key: String) {
        icons[key] = normalized.image
        probed.insert(key)
        if let file = file(for: key), let directory {
            let png = normalized.png
            diskQueue.async {
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try? png.write(to: file, options: .atomic)
            }
        }
    }

    /// The page no longer declares this variant: drop the stored copy so an older one is not shown.
    private func forget(_ key: String) {
        icons[key] = nil
        probed.insert(key)
        if let file = file(for: key) { diskQueue.async { try? FileManager.default.removeItem(at: file) } }
    }

    /// Clearing history or cache forgets every icon, in memory and on disk; open pages fetch theirs again on the next load.
    func clear() {
        generation += 1
        requests.values.forEach { $0.cancel() }; requests = [:]; pending = []; attempted = [:]
        icons = [:]; probed = []; refreshes = [:]
        if let directory { diskQueue.async { try? FileManager.default.removeItem(at: directory) } }
    }

    private func read(_ file: URL) async -> Data? {
        await withCheckedContinuation { continuation in
            diskQueue.async { continuation.resume(returning: try? Data(contentsOf: file)) }
        }
    }

    private func file(for key: String) -> URL? {
        guard let directory else { return nil }
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789.-")
        // The port separator becomes "_" like any other character outside the set: localhost_8501.png.
        let name = String(key.map { allowed.contains($0) ? $0 : "_" }.prefix(200))
        return directory.appendingPathComponent(name + ".png")
    }

    // MARK: Candidates

    typealias Link = FaviconLink

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
        FaviconDiscovery.candidates(links, page: page.absoluteString, fallback: fallback).compactMap(URL.init(string:))
    }

    // MARK: Download

    private func download(_ candidates: [URL], userAgent: String?, webView: WKWebView? = nil, page: URL? = nil) async -> NSImage? {
        for url in candidates {
            guard !Task.isCancelled else { return nil }
            var data: Data?
            if let webView, let page, Origin.string(url) == Origin.string(page), webView.url == page {
                data = await Self.fetchInPage(url, webView: webView)
            }
            if data == nil { data = await fetch(url, userAgent: userAgent)?.data }
            guard let data, let image = NSImage(data: data), image.isValid,
                  image.size.width > 0, image.size.height > 0, Self.normalize(image) != nil else { continue }
            return image
        }
        return nil
    }

    private func fetch(_ url: URL, userAgent: String?, html: Bool = false) async -> (data: Data, url: URL)? {
        if url.scheme?.lowercased() == "data" { return Self.decodeData(url.absoluteString).map { ($0, url) } }
        var request = URLRequest(url: url)
        request.httpShouldHandleCookies = false
        request.setValue(html ? "text/html,application/xhtml+xml" : "image/avif,image/webp,image/png,image/svg+xml,image/x-icon,image/*;q=0.8", forHTTPHeaderField: "Accept")
        if let userAgent { request.setValue(userAgent, forHTTPHeaderField: "User-Agent") }
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let final = http.url?.scheme?.lowercased(), final == "http" || final == "https",
                  response.expectedContentLength <= Int64(Self.byteLimit) else { bytes.task.cancel(); return nil }
            let mime = response.mimeType?.lowercased() ?? ""
            if html ? !(mime == "text/html" || mime == "application/xhtml+xml") : mime.hasPrefix("text/html") { bytes.task.cancel(); return nil }
            var data = Data()
            if response.expectedContentLength > 0 { data.reserveCapacity(Int(response.expectedContentLength)) }
            for try await byte in bytes {
                data.append(byte)
                if data.count > Self.byteLimit { bytes.task.cancel(); return nil }
            }
            return (data, response.url ?? url)
        } catch { return nil }
    }

    /// Same-origin icons can require the page's clearance/session. Keep cookies inside WebKit and obey CORS.
    private static func fetchInPage(_ url: URL, webView: WKWebView) async -> Data? {
        let script = """
        const controller = new AbortController();
        const timer = setTimeout(() => controller.abort(), 5000);
        try {
          const response = await fetch(url, {credentials:'same-origin', signal:controller.signal});
          if (!response.ok || (response.headers.get('content-type') || '').includes('text/html')) return null;
          if (Number(response.headers.get('content-length')) > limit) return null;
          const reader = response.body.getReader(); const chunks = []; let length = 0;
          while (true) {
            const {done, value} = await reader.read(); if (done) break;
            length += value.length;
            if (length > limit) { await reader.cancel(); return null; }
            chunks.push(value);
          }
          let binary = ''; for (const chunk of chunks) for (const byte of chunk) binary += String.fromCharCode(byte);
          return btoa(binary);
        } catch { return null; } finally { clearTimeout(timer); }
        """
        guard let encoded = try? await webView.callAsyncJavaScript(script, arguments: ["url": url.absoluteString, "limit": byteLimit], in: nil, contentWorld: .defaultClient) as? String else { return nil }
        return Data(base64Encoded: encoded)
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
        // Empty theme variants are sometimes cached by sites. They must not mask the ordinary icon forever.
        guard let pixels = rep.bitmapData,
              stride(from: 3, to: side * side * 4, by: 4).contains(where: { pixels[$0] >= 26 }),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        let result = NSImage(size: NSSize(width: side, height: side)); result.addRepresentation(rep)
        return (result, png)
    }
}

/// A site's favicon, slightly rounded, or its monogram until an icon is known. `icon`, when given, is the icon the
/// page itself declared on its latest load and wins over the stored icon of its origin. A neutral one-colour glyph
/// that would vanish on the surface (GitHub's white mark in the light theme) is drawn in ink instead.
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
    @Environment(\.self) private var environment
    var body: some View {
        // A dark variant comes from the same load as `icon`, so it wins while mica is dark.
        let image = (scheme == .dark ? favicons.image(for: url, dark: true) : nil) ?? icon ?? favicons.image(for: url)
        let side = tiled ? (size * 0.6).rounded() : size
        ZStack {
            if let image {
                ZStack {
                    if tiled { RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).fill(Palette.track) }
                    Image(nsImage: image).renderingMode(inked(image) ? .template : .original).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                        .foregroundStyle(Palette.ink)
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

    /// Contrast is measured against the surface of the current appearance, Increase Contrast included.
    private func inked(_ image: NSImage) -> Bool {
        guard let glyph = favicons.glyph(image) else { return false }
        let surface = Palette.surface.resolve(in: environment)
        let background = 0.2126 * Double(surface.linearRed) + 0.7152 * Double(surface.linearGreen) + 0.0722 * Double(surface.linearBlue)
        return FaviconTone.needsInk(glyph: glyph, background: background)
    }
}
