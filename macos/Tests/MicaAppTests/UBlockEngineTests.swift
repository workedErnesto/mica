import XCTest
@testable import MicaApp

final class UBlockEngineTests: XCTestCase {
    func testRecognisesUBlockOriginByGeckoID() {
        XCTAssertTrue(UBlockEngine.isUBlock(manifest: ["browser_specific_settings": ["gecko": ["id": "uBlock0@raymondhill.net"]]]))
        XCTAssertTrue(UBlockEngine.isUBlock(manifest: ["applications": ["gecko": ["id": "uBlock0@raymondhill.net"]]]))
        XCTAssertFalse(UBlockEngine.isUBlock(manifest: ["browser_specific_settings": ["gecko": ["id": "uBOLite@raymondhill.net"]]]))
        XCTAssertFalse(UBlockEngine.isUBlock(manifest: ["name": "uBlock Origin"]))
    }

    func testCompilerModuleIsEmbedded() {
        XCTAssertTrue(UBlockCompiler.module.contains("export async function build"))
        XCTAssertTrue(UBlockCompiler.module.contains("dnrRulesetFromRawLists"))
    }
}
