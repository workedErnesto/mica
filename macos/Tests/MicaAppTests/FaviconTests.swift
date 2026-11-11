import AppKit
import XCTest
@testable import MicaApp

private final class IconProtocol: URLProtocol {
    static let lock = NSLock()
    static var requests: [URLRequest] = []
    static var handler: (URLRequest) -> (Int, String, Data) = { _ in (404, "text/plain", Data()) }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        let response = Self.handler(request)
        Self.lock.unlock()
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: response.0, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": response.1])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.2)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor final class FaviconTests: XCTestCase {
    func store(_ handler: @escaping (URLRequest) -> (Int, String, Data)) -> Favicons {
        IconProtocol.lock.lock(); IconProtocol.requests = []; IconProtocol.handler = handler; IconProtocol.lock.unlock()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [IconProtocol.self]
        config.httpShouldSetCookies = false; config.httpCookieStorage = nil
        return Favicons(persistent: false, session: URLSession(configuration: config))
    }
    func png() -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 4, bitsPerPixel: 32)!
        rep.bitmapData![0] = 255; rep.bitmapData![3] = 255
        return rep.representation(using: .png, properties: [:])!
    }
    func loaded(_ store: Favicons, _ url: URL, seconds: Double = 4) async -> Bool {
        let until = Date().addingTimeInterval(seconds)
        while Date() < until {
            if store.image(for: url) != nil { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return false
    }
    func testUnvisitedTileDiscoversIconAndDeduplicatesRequests() async {
        let png = png()
        let icons = store { request in
            request.url!.path == "/" ? (200, "text/html", Data("<link rel=icon href='/assets/logo.png'>".utf8)) : (200, "image/png", png)
        }
        let page = URL(string: "https://unvisited.example/action?private=1")!
        for _ in 0..<20 { XCTAssertNil(icons.image(for: page)) }
        let ready = await loaded(icons, page)
        XCTAssertTrue(ready)
        XCTAssertEqual(IconProtocol.requests.map { $0.url!.path }, ["/", "/assets/logo.png"])
        XCTAssertTrue(IconProtocol.requests.allSatisfy { $0.url?.query == nil && $0.value(forHTTPHeaderField: "Cookie") == nil && !$0.httpShouldHandleCookies })
        XCTAssertEqual(icons.image(for: page)?.size, NSSize(width: Favicons.pixels, height: Favicons.pixels))
        icons.clear()
    }
    func testRejectedHtmlIconFallsBackToOriginICO() async {
        let png = png()
        let icons = store { request in
            switch request.url!.path {
            case "/": return (200, "text/html", Data("<link rel=icon href='/bad.png'>".utf8))
            case "/bad.png": return (200, "text/html", Data("<title>challenge</title>".utf8))
            default: return (200, "image/png", png)
            }
        }
        let page = URL(string: "https://fallback.example/")!
        let ready = await loaded(icons, page)
        XCTAssertTrue(ready)
        XCTAssertEqual(IconProtocol.requests.map { $0.url!.path }, ["/", "/bad.png", "/favicon.ico"])
        icons.clear()
    }
    func testTemporaryFailureRetriesWithoutOpeningSite() async {
        let png = png()
        var rootRequests = 0
        let icons = store { request in
            if request.url!.path == "/" { rootRequests += 1; return (503, "text/html", Data()) }
            return rootRequests > 1 ? (200, "image/png", png) : (503, "text/html", Data())
        }
        let page = URL(string: "https://retry.example/")!
        let ready = await loaded(icons, page, seconds: 6)
        XCTAssertTrue(ready)
        XCTAssertEqual(rootRequests, 2)
        icons.clear()
    }
    func testRemoteFallbackSendsOnlyPublicHost() async {
        let png = png()
        let icons = store { request in
            request.url!.host == "icons.duckduckgo.com" ? (200, "image/png", png) : (403, "text/html", Data())
        }
        let page = URL(string: "https://public-site.org/private?token=secret#draft")!
        let ready = await loaded(icons, page)
        XCTAssertTrue(ready)
        XCTAssertEqual(IconProtocol.requests.last?.url?.absoluteString, "https://icons.duckduckgo.com/ip3/public-site.org.ico")
        XCTAssertNil(IconProtocol.requests.last?.value(forHTTPHeaderField: "Referer"))
        XCTAssertTrue(IconProtocol.requests.allSatisfy { $0.url?.query == nil && $0.value(forHTTPHeaderField: "Cookie") == nil })
        icons.clear()
    }

    func testTransparentCandidateFallsThroughToVisibleIcon() async {
        let visible = png()
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 4, bitsPerPixel: 32)!
        rep.bitmapData!.initialize(repeating: 0, count: 4)
        let empty = rep.representation(using: .png, properties: [:])!
        XCTAssertNil(Favicons.normalize(NSImage(data: empty)!))
        let icons = store { request in
            switch request.url!.path {
            case "/": return (200, "text/html", Data("<link rel=icon href='/empty.png'><link rel=icon href='/visible.png'>".utf8))
            case "/empty.png": return (200, "image/png", empty)
            default: return (200, "image/png", visible)
            }
        }
        let page = URL(string: "https://transparent.example/")!
        let ready = await loaded(icons, page)
        XCTAssertTrue(ready)
        XCTAssertEqual(IconProtocol.requests.map { $0.url!.path }, ["/", "/empty.png", "/visible.png"])
        icons.clear()
    }

    func testLegacyCopyStaysUntilSizedIconReplacesIt() async throws {
        let png = png()
        IconProtocol.lock.lock(); IconProtocol.requests = []; IconProtocol.handler = { request in
            request.url!.path == "/" ? (200, "text/html", Data("<link rel=icon href='/large.png' sizes='192x192'>".utf8)) : (200, "image/png", png)
        }; IconProtocol.lock.unlock()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [IconProtocol.self]
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let legacy = directory.appendingPathComponent("legacy.example.png"), sized = directory.appendingPathComponent("legacy.example@\(Favicons.pixels).png")
        try png.write(to: legacy)
        try png.write(to: directory.appendingPathComponent("current.example@\(Favicons.pixels).png"))
        let icons = Favicons(persistent: true, session: URLSession(configuration: config), cache: directory)

        // A copy at the current size is used as is: no request leaves.
        let current = await loaded(icons, URL(string: "https://current.example/")!)
        XCTAssertTrue(current)
        try? await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(IconProtocol.requests.isEmpty)

        // An older 64 px copy shows at once and is replaced by the page's larger icon.
        let page = URL(string: "https://legacy.example/")!
        let shown = await loaded(icons, page)
        XCTAssertTrue(shown)
        let until = Date().addingTimeInterval(4)
        while Date() < until, FileManager.default.fileExists(atPath: legacy.path) { try? await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(IconProtocol.requests.map { $0.url!.path }, ["/", "/large.png"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: sized.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
        XCTAssertNotNil(icons.image(for: page))
    }

    func testClearCancelsQueuedLookups() async {
        let png = png()
        let icons = store { _ in (200, "image/png", png) }
        for index in 0..<10 { icons.prefetch(URL(string: "https://cancel-\(index).example/")!) }
        icons.clear()
        try? await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(icons.icons.isEmpty)
        XCTAssertTrue(IconProtocol.requests.isEmpty)
    }
}
