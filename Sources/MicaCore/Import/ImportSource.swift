import Foundation

/// Browser engine family: decides where profiles live and how their files are read.
public enum BrowserFamily: String, Codable, Sendable { case chromium, gecko, safari, orion }

/// A browser mica can read from. Paths are relative to the real home folder, not the sandbox container.
public struct ImportBrowser: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let family: BrowserFamily
    /// Data folder relative to home, ending without a slash.
    public let folder: String
    public let bundleID: String

    public static let all: [ImportBrowser] = [
        ImportBrowser(id: "orion", name: "Orion", family: .orion, folder: "Library/Application Support/Orion", bundleID: "com.kagi.kagimacOS"),
        ImportBrowser(id: "safari", name: "Safari", family: .safari, folder: "Library/Safari", bundleID: "com.apple.Safari"),
        ImportBrowser(id: "chrome", name: "Google Chrome", family: .chromium, folder: "Library/Application Support/Google/Chrome", bundleID: "com.google.Chrome"),
        ImportBrowser(id: "arc", name: "Arc", family: .chromium, folder: "Library/Application Support/Arc/User Data", bundleID: "company.thebrowser.Browser"),
        ImportBrowser(id: "yandex", name: "Яндекс Браузер", family: .chromium, folder: "Library/Application Support/Yandex/YandexBrowser", bundleID: "ru.yandex.desktop.yandex-browser"),
        ImportBrowser(id: "brave", name: "Brave", family: .chromium, folder: "Library/Application Support/BraveSoftware/Brave-Browser", bundleID: "com.brave.Browser"),
        ImportBrowser(id: "edge", name: "Microsoft Edge", family: .chromium, folder: "Library/Application Support/Microsoft Edge", bundleID: "com.microsoft.edgemac"),
        ImportBrowser(id: "opera", name: "Opera", family: .chromium, folder: "Library/Application Support/com.operasoftware.Opera", bundleID: "com.operasoftware.Opera"),
        ImportBrowser(id: "vivaldi", name: "Vivaldi", family: .chromium, folder: "Library/Application Support/Vivaldi", bundleID: "com.vivaldi.Vivaldi"),
        ImportBrowser(id: "chromium", name: "Chromium", family: .chromium, folder: "Library/Application Support/Chromium", bundleID: "org.chromium.Chromium"),
        ImportBrowser(id: "firefox", name: "Firefox", family: .gecko, folder: "Library/Application Support/Firefox", bundleID: "org.mozilla.firefox"),
        ImportBrowser(id: "zen", name: "Zen", family: .gecko, folder: "Library/Application Support/zen", bundleID: "app.zen-browser.zen"),
    ]

    /// Brand names stay as written; only the Yandex one has an established English form.
    public func displayName(_ language: Language) -> String { id == "yandex" && language == .en ? "Yandex Browser" : name }

    /// What mica brings over. Site sign-ins and passwords stay in the source browser.
    public var kinds: [ImportKind] { ImportKind.allCases }
}

/// One profile of a browser, with the folder its files sit in.
public struct ImportProfile: Identifiable, Hashable, Sendable {
    public var id: String { browser.id + ":" + path.path }
    public let browser: ImportBrowser
    public let name: String
    public let path: URL
    public init(browser: ImportBrowser, name: String, path: URL) { self.browser = browser; self.name = name; self.path = path }
}

public enum ImportKind: String, CaseIterable, Codable, Sendable { case history, bookmarks }

/// What one import produced before it is merged into mica.
public struct ImportBundle: Sendable {
    public var history: [Visit] = []
    public var bookmarks: [Visit] = []
    public init() {}
}

public enum ImportError: Error, Equatable, Sendable {
    /// The file exists but the system denies reading it (Safari without Full Disk Access).
    case noAccess(String)
    case unreadable(String)
}

/// Real home folder. Inside the sandbox `NSHomeDirectory()` points into the container.
public func realHome() -> URL {
    if let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir { return URL(fileURLWithPath: String(cString: dir), isDirectory: true) }
    return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
}

public enum ImportDiscovery {
    /// Discover profiles within a folder the user selected in the system file picker.
    public static func profiles(authorizedFolder folder: URL, home: URL = realHome()) -> [ImportProfile] {
        let fm = FileManager.default
        let path = folder.standardizedFileURL.path
        let known = ImportBrowser.all.compactMap { browser -> (ImportBrowser, String)? in
            let root = home.appendingPathComponent(browser.folder).standardizedFileURL.path
            return path == root || path.hasPrefix(root + "/") ? (browser, root) : nil
        }.max { $0.1.count < $1.1.count }?.0
        func has(_ name: String) -> Bool { fm.fileExists(atPath: folder.appendingPathComponent(name).path) }
        let family: BrowserFamily
        if let known { family = known.family }
        else if has("places.sqlite") || has("profiles.ini") { family = .gecko }
        else if has("Bookmarks.plist") || has("History.db") { family = .safari }
        else { family = .chromium }
        let fallbackID = family == .chromium ? "chromium" : family == .gecko ? "firefox" : "safari"
        let browser = known ?? ImportBrowser.all.first { $0.id == fallbackID }!
        if family == .orion && !has("favourites.plist") && !has("history") { return OrionReader.profiles(browser: browser, root: folder) }
        if family == .gecko && !has("places.sqlite") { return GeckoReader.profiles(browser: browser, root: folder) }
        if family == .chromium && !has("History") && !has("Bookmarks") { return ChromiumReader.profiles(browser: browser, root: folder) }
        if family == .safari && !has("History.db") && !has("Bookmarks.plist") { return [] }
        return [ImportProfile(browser: browser, name: folder.lastPathComponent, path: folder)]
    }

    /// Profiles with readable data, in the order of `ImportBrowser.all`. Safari is listed when its folder exists,
    /// even without access, so the interface can explain how to grant it.
    public static func profiles(home: URL = realHome(), browsers: [ImportBrowser] = ImportBrowser.all) -> [ImportProfile] {
        var result: [ImportProfile] = []
        let fm = FileManager.default
        for browser in browsers {
            let root = home.appendingPathComponent(browser.folder, isDirectory: true)
            guard fm.fileExists(atPath: root.path) else { continue }
            switch browser.family {
            case .safari: result.append(ImportProfile(browser: browser, name: "", path: root))
            case .chromium: result += ChromiumReader.profiles(browser: browser, root: root)
            case .gecko: result += GeckoReader.profiles(browser: browser, root: root)
            case .orion: result += OrionReader.profiles(browser: browser, root: root)
            }
        }
        return result
    }
}

public enum ImportMerge {
    /// Newest visit per address, newest first, capped like mica's own history.
    public static func history(_ existing: [Visit], adding imported: [Visit], limit: Int = 3000) -> (merged: [Visit], added: Int) {
        var seen = Set(existing.map { $0.url.absoluteString })
        var fresh: [Visit] = []
        for visit in imported.sorted(by: { $0.date > $1.date }) where seen.insert(visit.url.absoluteString).inserted { fresh.append(visit) }
        let merged = Array((existing + fresh).sorted { $0.date > $1.date }.prefix(limit))
        let kept = Set(merged.map(\.id))
        return (merged, fresh.filter { kept.contains($0.id) }.count)
    }
    /// Imported bookmarks go after mica's own, skipping addresses already saved.
    public static func bookmarks(_ existing: [Visit], adding imported: [Visit]) -> (merged: [Visit], added: Int) {
        var seen = Set(existing.map { $0.url.absoluteString })
        let fresh = imported.filter { seen.insert($0.url.absoluteString).inserted }
        return (existing + fresh, fresh.count)
    }
    /// Only web addresses become history and bookmarks.
    public static func webURL(_ string: String) -> URL? {
        guard let url = URL(string: string), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http", url.host?.isEmpty == false else { return nil }
        return url
    }
    public static func visit(_ string: String, title: String?, date: Date) -> Visit? {
        guard let url = webURL(string) else { return nil }
        var visit = Visit(url: url, title: (title?.isEmpty == false ? title! : url.host ?? string))
        visit.date = date
        return visit
    }
}
