import XCTest
import WebKit
@testable import MicaApp

final class SecurityOriginTests: XCTestCase {
    func testWebKitOriginKeyRejectsOpaqueOriginsAndNormalizesWebOrigins() {
        XCTAssertNil(WKSecurityOrigin.key(protocol: "", host: "", port: 0))
        XCTAssertNil(WKSecurityOrigin.key(protocol: "invalid scheme", host: "example.com", port: 0))
        XCTAssertNil(WKSecurityOrigin.key(protocol: "https", host: "", port: 0))
        XCTAssertEqual(WKSecurityOrigin.key(protocol: "https", host: "example.com", port: 443), "https://example.com")
        XCTAssertEqual(WKSecurityOrigin.key(protocol: "https", host: "example.com", port: 8443), "https://example.com:8443")
    }
}
