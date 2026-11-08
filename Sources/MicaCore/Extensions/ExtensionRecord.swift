import Foundation

public struct ExtensionRecord: Codable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var version: String
    public var enabled: Bool
    public var digest: String
    public var source: String
    public var permissions: [String]
    public var hosts: [String]
    public init(id: UUID = UUID(), name: String, version: String, enabled: Bool, digest: String, source: String, permissions: [String], hosts: [String]) {
        self.id = id; self.name = name; self.version = version; self.enabled = enabled; self.digest = digest; self.source = source; self.permissions = permissions; self.hosts = hosts
    }
}

public enum PackageSafety {
    public static func safeEntry(_ name: String) -> Bool {
        !name.hasPrefix("/") && !name.contains("\\") && !name.split(separator: "/", omittingEmptySubsequences: false).contains("..") && !name.contains("\0")
    }
}
