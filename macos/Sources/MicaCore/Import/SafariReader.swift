import Foundation

/// Safari files need Full Disk Access; its export ("File, Export Browsing Data") works without it.
public enum SafariReader {
    public static func history(_ folder: URL, limit: Int = 3000) throws -> [Visit] {
        let db = try SQLiteSnapshot(folder.appendingPathComponent("History.db"))
        let sql = """
        SELECT i.url, v.title, MAX(v.visit_time) AS t FROM history_items i JOIN history_visits v ON v.history_item = i.id
        GROUP BY i.id ORDER BY t DESC LIMIT ?
        """
        return try db.rows(sql, [Int64(limit)]).compactMap { row in
            guard let url = row[0].text, case .double(let time) = row[2] else { return nil }
            return ImportMerge.visit(url, title: row[1].text, date: Date(timeIntervalSinceReferenceDate: time))
        }
    }

    public static func bookmarks(_ folder: URL) throws -> [Visit] {
        let file = folder.appendingPathComponent("Bookmarks.plist")
        guard FileManager.default.isReadableFile(atPath: file.path), let data = try? Data(contentsOf: file) else { throw ImportError.noAccess(file.path) }
        return try bookmarks(plist: data)
    }

    /// Bookmarks bar and menu in order. The reading list is left out.
    public static func bookmarks(plist data: Data) throws -> [Visit] {
        guard let root = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { throw ImportError.unreadable("Bookmarks.plist") }
        var result: [Visit] = []
        func walk(_ node: [String: Any]) {
            if node["Title"] as? String == "com.apple.ReadingList" { return }
            if node["WebBookmarkType"] as? String == "WebBookmarkTypeLeaf", let url = node["URLString"] as? String {
                let title = (node["URIDictionary"] as? [String: Any])?["title"] as? String
                if let visit = ImportMerge.visit(url, title: title, date: Date()) { result.append(visit) }
            }
            for child in node["Children"] as? [[String: Any]] ?? [] { walk(child) }
        }
        walk(root)
        return result
    }

    /// History.json from a Safari export.
    public static func history(exportJSON data: Data) throws -> [Visit] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let items = json["history"] as? [[String: Any]] else { throw ImportError.unreadable("History.json") }
        return items.compactMap { item in
            guard let url = item["url"] as? String else { return nil }
            let usec = (item["time_usec"] as? NSNumber)?.int64Value ?? 0
            return ImportMerge.visit(url, title: item["title"] as? String, date: usec > 0 ? Date(timeIntervalSince1970: Double(usec) / 1_000_000) : Date())
        }
    }

    /// Netscape bookmark file: Safari and Firefox exports and the export of almost any other browser.
    public static func bookmarks(html: String) -> [Visit] {
        guard let anchor = try? NSRegularExpression(pattern: "<A\\s+([^>]*)>(.*?)</A>", options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let href = try? NSRegularExpression(pattern: "HREF=\"([^\"]*)\"", options: .caseInsensitive),
              let added = try? NSRegularExpression(pattern: "ADD_DATE=\"(\\d+)\"", options: .caseInsensitive) else { return [] }
        let ns = html as NSString
        return anchor.matches(in: html, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            let attributes = ns.substring(with: match.range(at: 1))
            let a = attributes as NSString
            guard let link = href.firstMatch(in: attributes, range: NSRange(location: 0, length: a.length)) else { return nil }
            let url = unescape(a.substring(with: link.range(at: 1)))
            let date = added.firstMatch(in: attributes, range: NSRange(location: 0, length: a.length)).flatMap { TimeInterval(a.substring(with: $0.range(at: 1))) }.map { Date(timeIntervalSince1970: $0) } ?? Date()
            return ImportMerge.visit(url, title: unescape(ns.substring(with: match.range(at: 2))), date: date)
        }
    }

    static func unescape(_ text: String) -> String {
        var result = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (entity, plain) in [("&quot;", "\""), ("&#39;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&")] { result = result.replacingOccurrences(of: entity, with: plain) }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Reads an unpacked export folder or a single exported file.
    public static func export(at url: URL) throws -> ImportBundle {
        var bundle = ImportBundle()
        var isFolder: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder)
        let files = isFolder.boolValue ? ((try? FileManager.default.subpathsOfDirectory(atPath: url.path)) ?? []).map { url.appendingPathComponent($0) } : [url]
        for file in files {
            let name = file.lastPathComponent.lowercased()
            if name.hasSuffix(".html") || name.hasSuffix(".htm"), let text = try? String(contentsOf: file, encoding: .utf8), text.localizedCaseInsensitiveContains("NETSCAPE-Bookmark-file") {
                bundle.bookmarks += bookmarks(html: text)
            } else if name.hasSuffix(".json"), name.contains("history"), let data = try? Data(contentsOf: file) {
                bundle.history += (try? history(exportJSON: data)) ?? []
            }
        }
        if bundle.bookmarks.isEmpty && bundle.history.isEmpty { throw ImportError.unreadable(url.lastPathComponent) }
        return bundle
    }
}
