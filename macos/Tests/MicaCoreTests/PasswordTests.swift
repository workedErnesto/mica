import XCTest
import CryptoKit
@testable import MicaCore

final class PasswordTests: XCTestCase {
    func testEncryptedRoundTripAndTampering() throws {
        var vault = Vault()
        vault.save(origin: "https://example.com", username: "alice", password: "secret")
        let key = VaultCrypto.newKey()
        var data = try VaultCrypto.seal(vault, key: key)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("alice"))
        XCTAssertEqual(try VaultCrypto.open(data, key: key), vault)
        XCTAssertThrowsError(try VaultCrypto.open(data, key: VaultCrypto.newKey()))
        data[data.count - 1] ^= 1
        XCTAssertThrowsError(try VaultCrypto.open(data, key: key))
    }

    func testExactOriginAndCapture() {
        var vault = Vault()
        vault.save(origin: "https://example.com", username: "a", password: "p")
        XCTAssertEqual(vault.matches(for: "https://example.com").count, 1)
        for other in ["http://example.com", "https://www.example.com", "https://example.com:8443", "https://example.com.evil.test"] {
            XCTAssertTrue(vault.matches(for: other).isEmpty)
        }
        XCTAssertEqual(vault.capture(origin: "https://example.com", username: "a", password: "p"), .known(vault.logins[0]))
        vault.never.append("https://example.com")
        XCTAssertEqual(vault.capture(origin: "https://example.com", username: "a", password: "other"), .blocked)
    }

    func testStoreDoesNotOverwriteOnWrongKey() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("vault")
        let key = Data(repeating: 42, count: 32)
        let store = try VaultStore(url: url, keyData: key)
        try store.update { $0.save(origin: "https://example.com", username: "user", password: "password") }
        let original = try Data(contentsOf: url)
        XCTAssertThrowsError(try VaultStore(url: url, keyData: nil))
        XCTAssertThrowsError(try VaultStore(url: url, keyData: Data(repeating: 1, count: 32)))
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertEqual(try VaultStore(url: url, keyData: key).vault.logins.count, 1)
    }

    func testGeneratedPasswordLengthAndClasses() {
        for length in [8, 12, 19, 20] {
            for _ in 0..<50 {
                let password = PasswordGenerator.strong(maxLength: length)
                XCTAssertLessThanOrEqual(password.count, length)
                XCTAssertTrue(password.contains(where: { $0.isUppercase }))
                XCTAssertTrue(password.contains(where: { $0.isLowercase }))
                XCTAssertTrue(password.contains(where: { $0.isNumber }))
            }
        }
    }

    // MARK: Offer beside the field

    func testOfferPrefersAboveThenBelowAndAlignsLeadingEdges() {
        let panel = CGSize(width: 280, height: 100), bounds = CGSize(width: 1000, height: 700)
        let above = PasswordOfferPlacement.place(field: CGRect(x: 120, y: 300, width: 240, height: 36), bounds: bounds, panel: panel, gap: 6, margin: 8)
        XCTAssertEqual(above, .init(frame: CGRect(x: 120, y: 194, width: 280, height: 100), edge: .above))
        // Exactly enough room above (margin + panel + gap) still goes above; one point less flips below.
        XCTAssertEqual(PasswordOfferPlacement.place(field: CGRect(x: 120, y: 114, width: 240, height: 36), bounds: bounds, panel: panel, gap: 6, margin: 8)?.edge, .above)
        let below = PasswordOfferPlacement.place(field: CGRect(x: 120, y: 113, width: 240, height: 36), bounds: bounds, panel: panel, gap: 6, margin: 8)
        XCTAssertEqual(below, .init(frame: CGRect(x: 120, y: 155, width: 280, height: 100), edge: .below))
    }

    func testOfferIsClampedIntoThePage() {
        let panel = CGSize(width: 280, height: 100), bounds = CGSize(width: 1000, height: 700)
        XCTAssertEqual(PasswordOfferPlacement.place(field: CGRect(x: 900, y: 300, width: 200, height: 36), bounds: bounds, panel: panel, gap: 6, margin: 8)?.frame.minX, 712)
        XCTAssertEqual(PasswordOfferPlacement.place(field: CGRect(x: -40, y: 300, width: 200, height: 36), bounds: bounds, panel: panel, gap: 6, margin: 8)?.frame.minX, 8)
        // A page narrower than the panel narrows the panel to the page minus the margins.
        XCTAssertEqual(PasswordOfferPlacement.place(field: CGRect(x: 20, y: 300, width: 100, height: 36), bounds: CGSize(width: 200, height: 700), panel: panel, gap: 6, margin: 8)?.frame,
                       CGRect(x: 8, y: 194, width: 184, height: 100))
        // No room on either side: the side with more room, kept inside the page even if it covers part of the field.
        let tight = PasswordOfferPlacement.place(field: CGRect(x: 100, y: 120, width: 240, height: 36), bounds: CGSize(width: 1000, height: 220), panel: CGSize(width: 280, height: 180), gap: 6, margin: 8)
        XCTAssertEqual(tight?.edge, .above)
        XCTAssertEqual(tight?.frame.minY, 8)
        let taller = PasswordOfferPlacement.place(field: CGRect(x: 100, y: 20, width: 240, height: 36), bounds: CGSize(width: 1000, height: 150), panel: CGSize(width: 280, height: 180), gap: 6, margin: 8)
        XCTAssertEqual(taller?.edge, .below)
        XCTAssertEqual(taller?.frame.minY, 8)
    }

    func testOfferHidesWhileTheFieldIsScrolledAway() {
        let panel = CGSize(width: 280, height: 100), bounds = CGSize(width: 1000, height: 700)
        XCTAssertNil(PasswordOfferPlacement.place(field: CGRect(x: 100, y: -36, width: 240, height: 36), bounds: bounds, panel: panel, gap: 6, margin: 8))
        XCTAssertNil(PasswordOfferPlacement.place(field: CGRect(x: 100, y: 700, width: 240, height: 36), bounds: bounds, panel: panel, gap: 6, margin: 8))
        XCTAssertNil(PasswordOfferPlacement.place(field: CGRect(x: 1000, y: 300, width: 240, height: 36), bounds: bounds, panel: panel, gap: 6, margin: 8))
        XCTAssertEqual(PasswordOfferPlacement.place(field: CGRect(x: 100, y: -35, width: 240, height: 36), bounds: bounds, panel: panel, gap: 6, margin: 8)?.edge, .below)
    }

    func testOfferScalesCSSPixelsByPageZoom() {
        // innerWidth 800 CSS px in a 1000 pt view is 125 % zoom.
        XCTAssertEqual(PasswordOfferPlacement.viewRect(css: CGRect(x: 80, y: 200, width: 160, height: 32), innerWidth: 800, viewWidth: 1000), CGRect(x: 100, y: 250, width: 200, height: 40))
        XCTAssertEqual(PasswordOfferPlacement.viewRect(css: CGRect(x: 10, y: 10, width: 10, height: 10), innerWidth: 0, viewWidth: 1000), CGRect(x: 10, y: 10, width: 10, height: 10))
    }

    func testNotNowLastsForOneFocusOnly() {
        var session = PasswordOfferSession()
        session.apply(.focus(1)); XCTAssertTrue(session.visible)
        session.apply(.dismiss); XCTAssertFalse(session.visible)
        // The window regaining focus reports the same field again: still dismissed.
        session.apply(.focus(1)); XCTAssertFalse(session.visible)
        // A click into the field brings it back, as does the next focus after a blur.
        session.apply(.click(1)); XCTAssertTrue(session.visible)
        session.apply(.input(1)); XCTAssertFalse(session.visible)
        session.apply(.blur(1)); XCTAssertNil(session.field)
        session.apply(.focus(2)); XCTAssertTrue(session.visible)
        // A late blur of another field changes nothing; leaving the page ends everything.
        session.apply(.blur(1)); XCTAssertTrue(session.visible)
        session.apply(.input(7)); XCTAssertTrue(session.visible)
        session.apply(.leave); XCTAssertFalse(session.visible)
        XCTAssertNil(session.field)
    }

    func testOfferDecisionKeepsNeverForSavingAndGenerating() {
        var vault = Vault()
        vault.save(origin: "https://example.com", username: "a", password: "p")
        XCTAssertEqual(PasswordOffer.decide(vault: vault, origin: "https://example.com", isNew: false, maxLength: -1, offerPasswords: true, fillPasswords: true), .fill(vault.logins))
        XCTAssertEqual(PasswordOffer.decide(vault: vault, origin: "https://example.com", isNew: true, maxLength: -1, offerPasswords: true, fillPasswords: true), .generate)
        vault.never.append("https://example.com")
        // "Never for this site" stops generating there, since mica would never offer to save the result; filling stays.
        XCTAssertNil(PasswordOffer.decide(vault: vault, origin: "https://example.com", isNew: true, maxLength: -1, offerPasswords: true, fillPasswords: true))
        XCTAssertEqual(PasswordOffer.decide(vault: vault, origin: "https://example.com", isNew: false, maxLength: -1, offerPasswords: true, fillPasswords: true), .fill(vault.logins))
        XCTAssertNil(PasswordOffer.decide(vault: vault, origin: "https://example.com", isNew: false, maxLength: -1, offerPasswords: true, fillPasswords: false))
        XCTAssertNil(PasswordOffer.decide(vault: Vault(), origin: "https://example.com", isNew: true, maxLength: 6, offerPasswords: true, fillPasswords: true))
    }
}
