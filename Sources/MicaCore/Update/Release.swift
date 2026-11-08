import Foundation

/// Dotted numeric version such as 0.3.0; a leading "v" from a tag name is ignored.
public struct AppVersion: Comparable, CustomStringConvertible, Hashable, Sendable {
    public let parts: [Int]
    public init?(_ text: String) {
        var raw = text.trimmingCharacters(in: .whitespaces)
        if raw.lowercased().hasPrefix("v") { raw.removeFirst() }
        let components = raw.split(separator: ".", omittingEmptySubsequences: false)
        guard !components.isEmpty, components.count <= 4,
              components.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }) else { return nil }
        let parts = components.map { Int($0) }
        guard !parts.contains(where: { $0 == nil }) else { return nil }
        self.parts = parts.compactMap { $0 }
    }
    public var description: String { parts.map(String.init).joined(separator: ".") }
    public static func < (a: AppVersion, b: AppVersion) -> Bool {
        for i in 0..<max(a.parts.count, b.parts.count) {
            let x = i < a.parts.count ? a.parts[i] : 0, y = i < b.parts.count ? b.parts[i] : 0
            if x != y { return x < y }
        }
        return false
    }
    public static func == (a: AppVersion, b: AppVersion) -> Bool { !(a < b) && !(b < a) }
    public func hash(into hasher: inout Hasher) {
        var trimmed = parts; while trimmed.last == 0 { trimmed.removeLast() }
        hasher.combine(trimmed)
    }
}

/// The part of a GitHub release mica needs.
public struct Release: Decodable, Equatable, Sendable {
    public struct Asset: Decodable, Equatable, Sendable {
        public let name: String
        public let url: URL
        public let size: Int
        enum CodingKeys: String, CodingKey { case name, size, url = "browser_download_url" }
        public init(name: String, url: URL, size: Int) { self.name = name; self.url = url; self.size = size }
    }
    public let tag: String
    public let name: String?
    public let notes: String?
    public let page: URL
    public let draft: Bool
    public let prerelease: Bool
    public let assets: [Asset]
    enum CodingKeys: String, CodingKey { case tag = "tag_name", name, notes = "body", page = "html_url", draft, prerelease, assets }
    public init(tag: String, name: String?, notes: String?, page: URL, draft: Bool = false, prerelease: Bool = false, assets: [Asset]) {
        self.tag = tag; self.name = name; self.notes = notes; self.page = page; self.draft = draft; self.prerelease = prerelease; self.assets = assets
    }
    public var version: AppVersion? { AppVersion(tag) }
    public var disk: Asset? { assets.first { $0.name.lowercased().hasSuffix(".dmg") } }
    /// `<dmg name>.sha256`, the checksum file the release script publishes next to the image.
    public var checksum: Asset? { disk.flatMap { dmg in assets.first { $0.name == dmg.name + ".sha256" } } }
}

public enum UpdatePolicy {
    public static let repository = "workedErnesto/mica"
    public static let checkInterval: TimeInterval = 24 * 60 * 60
    public static var latestURL: URL { URL(string: "https://api.github.com/repos/\(repository)/releases/latest")! }

    public static func delaySinceLastCheck(_ last: Date?, now: Date = Date()) -> TimeInterval {
        guard let last else { return 0 }
        return max(0, min(checkInterval, checkInterval - now.timeIntervalSince(last)))
    }

    /// A release is offered when it is newer, installable, and the user has not declined it or all updates.
    public static func offer(_ release: Release, current: AppVersion, preferences: Preferences) -> Bool {
        guard preferences.updateChecks, !release.draft, !release.prerelease, let version = release.version, version > current,
              release.disk != nil, release.checksum != nil else { return false }
        if let skipped = preferences.skippedVersion.flatMap(AppVersion.init), skipped == version { return false }
        return true
    }

    /// First hexadecimal SHA-256 in a `shasum -a 256` line.
    public static func parseChecksum(_ text: String) -> String? {
        let token = text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).first.map(String.init)?.lowercased() ?? ""
        return token.utf8.count == 64 && token.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } ? token : nil
    }
}

/// How a copy of mica opened from a disk image relates to the one in Applications.
public enum InstallState: Equatable, Sendable {
    case notInstalled
    case older(AppVersion)
    case same
    case newer(AppVersion)
    public static func compare(running: AppVersion, installed: AppVersion?) -> InstallState {
        guard let installed else { return .notInstalled }
        if installed < running { return .older(installed) }
        if installed > running { return .newer(installed) }
        return .same
    }
    /// A path inside a mounted image or one Gatekeeper moved to a randomized read-only location.
    public static func runsFromDiskImage(_ path: String) -> Bool { path.hasPrefix("/Volumes/") || path.contains("/AppTranslocation/") }
}
