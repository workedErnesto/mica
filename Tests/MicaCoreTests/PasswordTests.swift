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
}
