import Foundation

/// Chrome, Arc, Brave, Edge, Opera, Vivaldi and Yandex keep the same file layout.
public enum ChromiumReader {
    /// Microseconds between 1601-01-01 and 1970-01-01, the Chromium time origin.
    static let epochOffset: Int64 = 11_644_473_600 * 1_000_000

    public static func date(_ chromium: Int64) -> Date? {
        guard chromium > epochOffset else { return nil }
        return Date(timeIntervalSince1970: Double(chromium - epochOffset) / 1_000_000)
    }

    public static func profiles(browser: ImportBrowser, root: URL) -> [ImportProfile] {
        let fm = FileManager.default
        var names: [String: String] = [:]
        if let data = try? Data(contentsOf: root.appendingPathComponent("Local State")),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let cache = (json["profile"] as? [String: Any])?["info_cache"] as? [String: Any] {
            for (folder, info) in cache { if let name = (info as? [String: Any])?["name"] as? String { names[folder] = name } }
        }
        let folders = ((try? fm.contentsOfDirectory(atPath: root.path)) ?? [])
            .filter { $0 == "Default" || $0.hasPrefix("Profile ") }
            .sorted { a, b in a == "Default" ? true : b == "Default" ? false : a.localizedStandardCompare(b) == .orderedAscending }
        var result = folders.compactMap { folder -> ImportProfile? in
            let path = root.appendingPathComponent(folder, isDirectory: true)
            guard fm.fileExists(atPath: path.appendingPathComponent("History").path) || fm.fileExists(atPath: path.appendingPathComponent("Bookmarks").path) else { return nil }
            return ImportProfile(browser: browser, name: names[folder] ?? folder, path: path)
        }
        // Opera keeps its only profile in the data folder itself.
        if result.isEmpty, fm.fileExists(atPath: root.appendingPathComponent("History").path) { result.append(ImportProfile(browser: browser, name: "", path: root)) }
        return result
    }

    public static func history(_ profile: URL, limit: Int = 3000) throws -> [Visit] {
        let db = try SQLiteSnapshot(profile.appendingPathComponent("History"))
        return try db.rows("SELECT url, title, last_visit_time FROM urls WHERE hidden = 0 ORDER BY last_visit_time DESC LIMIT ?", [Int64(limit)]).compactMap { row in
            guard let url = row[0].text, let time = row[2].int, let date = date(time) else { return nil }
            return ImportMerge.visit(url, title: row[1].text, date: date)
        }
    }

    /// Bookmark bar first, then other and mobile bookmarks, folders flattened in order.
    public static func bookmarks(_ profile: URL) throws -> [Visit] {
        let file = profile.appendingPathComponent("Bookmarks")
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        guard let data = try? Data(contentsOf: file) else { throw ImportError.noAccess(file.path) }
        return try bookmarks(json: data)
    }

    public static func bookmarks(json data: Data) throws -> [Visit] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let roots = json["roots"] as? [String: Any] else { throw ImportError.unreadable("Bookmarks") }
        var result: [Visit] = []
        func walk(_ node: [String: Any]) {
            if node["type"] as? String == "url", let url = node["url"] as? String {
                let added = (node["date_added"] as? String).flatMap(Int64.init).flatMap(date) ?? Date()
                if let visit = ImportMerge.visit(url, title: node["name"] as? String, date: added) { result.append(visit) }
            }
            for child in node["children"] as? [[String: Any]] ?? [] { walk(child) }
        }
        for key in ["bookmark_bar", "other", "synced"] { if let root = roots[key] as? [String: Any] { walk(root) } }
        return result
    }
}
