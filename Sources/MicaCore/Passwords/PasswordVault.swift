import Foundation
import CryptoKit
import Security

/// One saved sign-in. `origin` is scheme, host and a non-default port, as `Origin.string` builds it.
public struct SavedLogin: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var origin: String
    public var username: String
    public var password: String
    public var created: Date
    public var updated: Date
    public var used: Date?
    public init(id: UUID = UUID(), origin: String, username: String, password: String, created: Date = Date()) {
        self.id = id; self.origin = origin; self.username = username; self.password = password; self.created = created; self.updated = created
    }
    /// Host without the scheme, for lists and prompts.
    public var host: String { URL(string: origin)?.host ?? origin }
}

/// Everything the password store keeps. Encrypted as one blob, so the file reveals neither sites nor names.
public struct Vault: Codable, Equatable, Sendable {
    public var version = 1
    public var logins: [SavedLogin] = []
    /// Origins where the user chose "never for this site".
    public var never: [String] = []
    public init() {}

    /// What a captured sign-in means for the vault.
    public enum Capture: Equatable, Sendable {
        case new
        case changed(SavedLogin)
        case known(SavedLogin)
        case blocked
    }

    public func capture(origin: String, username: String, password: String) -> Capture {
        if never.contains(origin) { return .blocked }
        guard let existing = logins.first(where: { $0.origin == origin && $0.username == username }) else { return .new }
        return existing.password == password ? .known(existing) : .changed(existing)
    }

    /// Only the exact origin may receive a saved credential.
    public func matches(for origin: String) -> [SavedLogin] {
        guard let canonical = Origin.string(URL(string: origin)), canonical == origin else { return [] }
        return logins.filter { $0.origin == canonical }.sorted { ( $0.used ?? $0.updated ) > ( $1.used ?? $1.updated ) }
    }

    /// Adds or replaces the login with the same origin and username.
    @discardableResult public mutating func save(origin: String, username: String, password: String, now: Date = Date()) -> SavedLogin {
        if let index = logins.firstIndex(where: { $0.origin == origin && $0.username == username }) {
            logins[index].password = password; logins[index].updated = now
            return logins[index]
        }
        let login = SavedLogin(origin: origin, username: username, password: password, created: now)
        logins.append(login)
        return login
    }
}

public enum VaultCrypto {
    public enum Failure: Error, Equatable { case damaged }
    /// File layout: "MICAPW1" then the AES-GCM combined box (nonce, cipher text, tag).
    static let magic = Data("MICAPW1".utf8)

    public static func newKey() -> SymmetricKey { SymmetricKey(size: .bits256) }

    public static func seal(_ vault: Vault, key: SymmetricKey) throws -> Data {
        let plain = try JSONEncoder().encode(vault)
        guard let combined = try AES.GCM.seal(plain, using: key).combined else { throw Failure.damaged }
        return magic + combined
    }

    public static func open(_ data: Data, key: SymmetricKey) throws -> Vault {
        guard data.count > magic.count, data.prefix(magic.count) == magic else { throw Failure.damaged }
        let box = try AES.GCM.SealedBox(combined: data.dropFirst(magic.count))
        let vault = try JSONDecoder().decode(Vault.self, from: try AES.GCM.open(box, using: key))
        guard vault.version == 1 else { throw Failure.damaged }
        return vault
    }
}

/// Strong passwords in the shape browsers suggest: three groups of six letters and digits joined by hyphens,
/// with at least one capital letter and one digit. About 71 bits of entropy.
public enum PasswordGenerator {
    // Without look-alike characters (0/O, 1/l/I), so a password read from the screen can be typed.
    static let lower = Array("abcdefghijkmnopqrstuvwxyz")
    static let upper = Array("ABCDEFGHJKLMNPQRSTUVWXYZ")
    static let digits = Array("23456789")

    public static func strong<R: RandomNumberGenerator>(using generator: inout R) -> String {
        var chars = (0..<18).map { _ in lower.randomElement(using: &generator)! }
        var slots = Array(0..<18).shuffled(using: &generator)
        chars[slots.removeLast()] = upper.randomElement(using: &generator)!
        chars[slots.removeLast()] = digits.randomElement(using: &generator)!
        return [chars[0..<6], chars[6..<12], chars[12..<18]].map { String($0) }.joined(separator: "-")
    }

    /// A field with `maxlength` shorter than the grouped form gets a password of that length.
    /// Callers must not offer generated passwords for limits shorter than 8.
    public static func strong<R: RandomNumberGenerator>(maxLength: Int?, using generator: inout R) -> String {
        guard let maxLength, maxLength > 0, maxLength < 20 else { return strong(using: &generator) }
        let length = maxLength
        let all = lower + upper + digits
        var chars = (0..<length).map { _ in all.randomElement(using: &generator)! }
        var slots = Array(0..<length).shuffled(using: &generator)
        if !slots.isEmpty { chars[slots.removeLast()] = upper.randomElement(using: &generator)! }
        if !slots.isEmpty { chars[slots.removeLast()] = digits.randomElement(using: &generator)! }
        if !slots.isEmpty { chars[slots.removeLast()] = lower.randomElement(using: &generator)! }
        return String(chars)
    }

    public static func strong(maxLength: Int? = nil) -> String {
        var generator = SecureRandom()
        return strong(maxLength: maxLength, using: &generator)
    }
}

/// Bytes from the system's cryptographic generator.
public struct SecureRandom: RandomNumberGenerator {
    public init() {}
    public mutating func next() -> UInt64 {
        var value: UInt64 = 0
        let status = withUnsafeMutableBytes(of: &value) { SecRandomCopyBytes(kSecRandomDefault, 8, $0.baseAddress!) }
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
        return value
    }
}
