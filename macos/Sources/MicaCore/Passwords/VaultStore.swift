import Foundation
import CryptoKit
import Security

/// An encrypted vault. A missing key for an existing file is an error, never a new empty vault.
public final class VaultStore {
    public enum Failure: Error { case missingKey, invalidKey, keychain(OSStatus) }
    public let url: URL
    private let key: SymmetricKey
    public private(set) var vault: Vault

    public init(url: URL, keyData: Data?) throws {
        self.url = url
        guard let keyData else { throw Failure.missingKey }
        guard keyData.count == 32 else { throw Failure.invalidKey }
        key = SymmetricKey(data: keyData)
        if FileManager.default.fileExists(atPath: url.path) {
            vault = try VaultCrypto.open(Data(contentsOf: url), key: key)
        } else {
            vault = Vault()
        }
    }

    /// The in-memory value changes only after the encrypted file is written successfully.
    public func update(_ change: (inout Vault) -> Void) throws {
        var next = vault
        change(&next)
        let data = try VaultCrypto.seal(next, key: key)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
        vault = next
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

public enum VaultKeychain {
    /// QA uses a distinct item, and loss of the key cannot silently replace an existing vault.
    public static func loadOrCreate(account: String, vaultExists: Bool) throws -> Data {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: "app.mica.browser.password-vault",
                                    kSecAttrAccount as String: account]
        func load() throws -> Data? {
            var request = query
            request[kSecReturnData as String] = true
            request[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            let status = SecItemCopyMatching(request as CFDictionary, &result)
            if status == errSecItemNotFound { return nil }
            guard status == errSecSuccess else { throw VaultStore.Failure.keychain(status) }
            guard let data = result as? Data, data.count == 32 else { throw VaultStore.Failure.invalidKey }
            return data
        }
        if let data = try load() { return data }
        guard !vaultExists else { throw VaultStore.Failure.missingKey }
        var bytes = Data(count: 32)
        let randomStatus = bytes.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
        guard randomStatus == errSecSuccess else { throw VaultStore.Failure.keychain(randomStatus) }
        var item = query
        item[kSecValueData as String] = bytes
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        if status == errSecDuplicateItem, let existing = try load() { return existing }
        guard status == errSecSuccess else { throw VaultStore.Failure.keychain(status) }
        return bytes
    }
}
