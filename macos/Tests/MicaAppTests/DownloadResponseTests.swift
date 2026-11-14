import Foundation
import XCTest
@testable import MicaApp

final class DownloadResponseTests: XCTestCase {
    func testResponseDispositionAndMimeType() {
        func response(_ disposition: String?) -> HTTPURLResponse {
            HTTPURLResponse(url: URL(string: "https://example.com/file")!, statusCode: 200, httpVersion: "HTTP/1.1",
                            headerFields: disposition.map { ["content-disposition": $0] })!
        }
        XCTAssertTrue(Tab.shouldDownload(response: response("attachment; filename=test.txt"), canShowMIMEType: true))
        XCTAssertTrue(Tab.shouldDownload(response: response(" ATTACHMENT ; filename=\"test.txt\""), canShowMIMEType: true))
        XCTAssertFalse(Tab.shouldDownload(response: response("inline; filename=attachment.txt"), canShowMIMEType: true))
        XCTAssertFalse(Tab.shouldDownload(response: response("attachment-extra"), canShowMIMEType: true))
        XCTAssertFalse(Tab.shouldDownload(response: response(nil), canShowMIMEType: true))
        XCTAssertTrue(Tab.shouldDownload(response: response(nil), canShowMIMEType: false))
    }
}
