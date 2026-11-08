import Foundation
import CryptoKit
import Security

/// Chrome Web Store packages. The store serves CRX3 files: a signed protobuf header followed by a ZIP archive.
/// mica checks the developer signature and that the signing key matches the requested extension ID,
/// then hands the ZIP to the regular import with its permission prompt.
public enum ChromeStore {
    /// Version reported to the update service; extensions declare a minimum Chrome version.
    public static let productVersion = "142.0.0.0"

    /// Extension ID from a store address (`chromewebstore.google.com/detail/<slug>/<id>`, the older
    /// `chrome.google.com/webstore/detail/...`) or a bare 32-letter ID.
    public static func extensionID(from input: String) -> String? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if isID(text) { return text }
        guard let url = URL(string: text.contains("://") ? text : "https://" + text), let host = url.host?.lowercased(),
              host == "chromewebstore.google.com" || (host == "chrome.google.com" && url.path.hasPrefix("/webstore")) else { return nil }
        return url.pathComponents.last(where: isID)
    }
    public static func isID(_ text: String) -> Bool { text.count == 32 && text.allSatisfy { ("a"..."p").contains($0) } }
    public static func isDetailPage(_ url: URL?) -> Bool { url.map { extensionID(from: $0.absoluteString) != nil } ?? false }

    public static func downloadURL(id: String) -> URL {
        var c = URLComponents(string: "https://clients2.google.com/service/update2/crx")!
        c.queryItems = [.init(name: "response", value: "redirect"), .init(name: "prodversion", value: productVersion), .init(name: "acceptformat", value: "crx3"), .init(name: "x", value: "id=\(id)&installsource=ondemand&uc")]
        return c.url!
    }

    /// ID that a public key produces: first 16 bytes of its SHA-256, each nibble written as a letter a–p.
    public static func id(forPublicKey key: Data) -> String {
        let digest = SHA256.hash(data: key).prefix(16)
        return String(digest.flatMap { [$0 >> 4, $0 & 0x0f] }.map { Character(UnicodeScalar(UInt8(ascii: "a") + $0)) })
    }
}

public enum CRXError: Error, Equatable, LocalizedError {
    case notCRX, unsupportedVersion(UInt32), malformed, idMismatch(expected: String, found: String), badSignature
    public var errorDescription: String? {
        switch self {
        case .notCRX: return "not a CRX package"
        case .unsupportedVersion(let v): return "CRX version \(v) is not supported"
        case .malformed: return "CRX header is damaged"
        case .idMismatch(let expected, let found): return "package ID \(found) does not match \(expected)"
        case .badSignature: return "CRX signature check failed"
        }
    }
}

public struct CRXPackage {
    public struct Proof { public let publicKey: Data; public let signature: Data; public let ecdsa: Bool }
    public let proofs: [Proof]
    public let signedHeader: Data
    /// ID declared inside the signed header.
    public let crxID: String
    public let archive: Data

    public init(_ data: Data) throws {
        let bytes = [UInt8](data)
        guard bytes.count > 12, bytes[0..<4] == [0x43, 0x72, 0x32, 0x34] else { throw CRXError.notCRX }
        func u32(_ at: Int) -> UInt32 { UInt32(bytes[at]) | UInt32(bytes[at + 1]) << 8 | UInt32(bytes[at + 2]) << 16 | UInt32(bytes[at + 3]) << 24 }
        let version = u32(4)
        guard version == 3 else { throw CRXError.unsupportedVersion(version) }
        let headerSize = Int(u32(8))
        guard headerSize > 0, 12 + headerSize < bytes.count else { throw CRXError.malformed }
        let header = Array(bytes[12..<(12 + headerSize)])
        var proofs: [Proof] = []
        var signed: [UInt8]?
        for field in try Protobuf.fields(header) where field.wire == 2 {
            switch field.number {
            case 2, 3:
                var key: [UInt8]?, signature: [UInt8]?
                for inner in try Protobuf.fields(field.bytes) where inner.wire == 2 {
                    if inner.number == 1 { key = inner.bytes } else if inner.number == 2 { signature = inner.bytes }
                }
                if let key, let signature { proofs.append(Proof(publicKey: Data(key), signature: Data(signature), ecdsa: field.number == 3)) }
            case 10000: signed = field.bytes
            default: break
            }
        }
        guard let signed, let idBytes = try Protobuf.fields(signed).first(where: { $0.number == 1 && $0.wire == 2 })?.bytes, idBytes.count == 16 else { throw CRXError.malformed }
        self.proofs = proofs
        signedHeader = Data(signed)
        crxID = String(idBytes.flatMap { [$0 >> 4, $0 & 0x0f] }.map { Character(UnicodeScalar(UInt8(ascii: "a") + $0)) })
        archive = Data(bytes[(12 + headerSize)...])
        guard archive.starts(with: [0x50, 0x4b]) else { throw CRXError.malformed }
    }

    /// The signed header must name `expectedID`, and the key that produces this ID must have signed the package.
    public func verify(expectedID: String) throws {
        guard crxID == expectedID else { throw CRXError.idMismatch(expected: expectedID, found: crxID) }
        var message = Data("CRX3 SignedData".utf8); message.append(0)
        var length = UInt32(signedHeader.count).littleEndian
        message.append(Data(bytes: &length, count: 4)); message.append(signedHeader); message.append(archive)
        let developer = proofs.filter { ChromeStore.id(forPublicKey: $0.publicKey) == crxID }
        guard !developer.isEmpty, developer.allSatisfy({ Self.check($0, message: message) }) else { throw CRXError.badSignature }
    }

    static func check(_ proof: Proof, message: Data) -> Bool {
        guard let raw = SPKI.keyBits(proof.publicKey) else { return false }
        let attributes: [String: Any] = [kSecAttrKeyType as String: proof.ecdsa ? kSecAttrKeyTypeECSECPrimeRandom : kSecAttrKeyTypeRSA, kSecAttrKeyClass as String: kSecAttrKeyClassPublic]
        guard let key = SecKeyCreateWithData(raw as CFData, attributes as CFDictionary, nil) else { return false }
        let algorithm: SecKeyAlgorithm = proof.ecdsa ? .ecdsaSignatureMessageX962SHA256 : .rsaSignatureMessagePKCS1v15SHA256
        return SecKeyVerifySignature(key, algorithm, message as CFData, proof.signature as CFData, nil)
    }
}

/// Minimal protobuf reader: enough for CRX headers (varint and length-delimited fields).
enum Protobuf {
    struct Field { let number: Int; let wire: Int; let bytes: [UInt8] }
    static func fields(_ data: [UInt8]) throws -> [Field] {
        var result: [Field] = [], i = 0
        func varint() throws -> UInt64 {
            var value: UInt64 = 0, shift: UInt64 = 0
            while true {
                guard i < data.count, shift < 64 else { throw CRXError.malformed }
                let byte = data[i]; i += 1
                value |= UInt64(byte & 0x7f) << shift
                if byte & 0x80 == 0 { return value }
                shift += 7
            }
        }
        while i < data.count {
            let tag = try varint()
            let number = Int(tag >> 3), wire = Int(tag & 7)
            switch wire {
            case 0: _ = try varint(); result.append(Field(number: number, wire: 0, bytes: []))
            case 2:
                let length = Int(try varint())
                guard length >= 0, length <= data.count - i else { throw CRXError.malformed }
                result.append(Field(number: number, wire: 2, bytes: Array(data[i..<(i + length)]))); i += length
            case 1: guard data.count - i >= 8 else { throw CRXError.malformed }; i += 8
            case 5: guard data.count - i >= 4 else { throw CRXError.malformed }; i += 4
            default: throw CRXError.malformed
            }
        }
        return result
    }
}

/// SubjectPublicKeyInfo → the inner key bits Security expects (PKCS#1 for RSA, X9.63 point for EC).
enum SPKI {
    static func keyBits(_ der: Data) -> Data? {
        let b = [UInt8](der)
        var i = 0
        func header() -> (tag: UInt8, length: Int)? {
            guard i + 2 <= b.count else { return nil }
            let tag = b[i]; var length = Int(b[i + 1]); i += 2
            if length & 0x80 != 0 {
                let count = length & 0x7f
                guard count > 0, count <= 4, i + count <= b.count else { return nil }
                length = b[i..<(i + count)].reduce(0) { $0 << 8 | Int($1) }; i += count
            }
            return i + length <= b.count ? (tag, length) : nil
        }
        guard header()?.tag == 0x30, let algorithm = header(), algorithm.tag == 0x30 else { return nil }
        i += algorithm.length
        guard let bits = header(), bits.tag == 0x03, bits.length > 1, b[i] == 0 else { return nil }
        return Data(b[(i + 1)..<(i + bits.length)])
    }
}
