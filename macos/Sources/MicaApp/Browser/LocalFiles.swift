import Foundation
import MicaCore

/// Local files the system handed to mica in this process: Finder or another app opening a file, a file dropped on the
/// Dock icon, a restored tab of such a file. A file URL loads in a tab only through this registry. Typed text and web
/// pages never add to it: `AddressParser.resolve` and `navigable` keep `file:` out.
///
/// Sandbox: a file opened through LaunchServices comes with a read extension for that file only, valid while mica runs.
/// mica stores an app-scoped security-scoped bookmark of it in the session, so after a relaunch the restored tab regains
/// access to the same file. WebKit gets read access to the file alone: images or styles beside it are outside the
/// sandbox extension and do not load. Access stays open until mica quits, like the extension LaunchServices grants.
@MainActor
final class LocalFiles {
    static let shared = LocalFiles()
    struct Grant { let url: URL; let bookmark: Data? }
    private var grants: [String: Grant] = [:]

    /// Same file regardless of fragment or `.`/`..` segments.
    static func key(_ url: URL) -> String { url.standardizedFileURL.path }

    /// A file the system just opened in mica. Returns false for unsupported types or a file mica cannot read.
    @discardableResult func grant(_ url: URL) -> Bool {
        guard AddressParser.openableFile(url), Self.readable(url) else { return false }
        if grants[Self.key(url)] == nil {
            grants[Self.key(url)] = Grant(url: Self.plain(url), bookmark: Self.bookmark(url))
        }
        return true
    }

    /// The grant for a file, regaining it from a stored bookmark after a relaunch. Nil when the file is gone, moved,
    /// or mica has no permission for it.
    func grant(for url: URL, bookmark: Data?) -> Grant? {
        guard AddressParser.openableFile(url) else { return nil }
        if let grant = grants[Self.key(url)] {
            guard Self.readable(url) else { return nil }
            return grant
        }
        guard let bookmark else { return nil }
        var stale = false
        guard let resolved = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale),
              Self.key(resolved) == Self.key(url) else { return nil }
        guard resolved.startAccessingSecurityScopedResource() else { return nil }
        guard Self.readable(resolved) else { resolved.stopAccessingSecurityScopedResource(); return nil }
        let grant = Grant(url: Self.plain(url), bookmark: stale ? (Self.bookmark(resolved) ?? bookmark) : bookmark)
        grants[Self.key(url)] = grant
        return grant
    }

    func granted(_ url: URL) -> Grant? { AddressParser.openableFile(url) ? grants[Self.key(url)] : nil }

    private static func plain(_ url: URL) -> URL { URL(fileURLWithPath: key(url)) }
    private static func bookmark(_ url: URL) -> Data? {
        try? plain(url).bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
    }
    /// Opening the file is the real test: the sandbox decides, not a permission bit.
    private static func readable(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: plain(url)) else { return false }
        try? handle.close()
        return true
    }
}
