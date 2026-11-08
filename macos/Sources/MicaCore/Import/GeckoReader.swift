import Foundation

/// Firefox and browsers built on it (Zen).
public enum GeckoReader {
    public static func date(_ microseconds: Int64) -> Date? { microseconds > 0 ? Date(timeIntervalSince1970: Double(microseconds) / 1_000_000) : nil }

    public static func profiles(browser: ImportBrowser, root: URL) -> [ImportProfile] {
        guard let text = try? String(contentsOf: root.appendingPathComponent("profiles.ini"), encoding: .utf8) else { return [] }
        return parseProfiles(text).compactMap { entry in
            let path = entry.relative ? root.appendingPathComponent(entry.path, isDirectory: true) : URL(fileURLWithPath: entry.path, isDirectory: true)
            guard FileManager.default.fileExists(atPath: path.appendingPathComponent("places.sqlite").path) else { return nil }
            return ImportProfile(browser: browser, name: entry.name, path: path)
        }
    }

    /// Profile sections of profiles.ini, the default profile first.
    public static func parseProfiles(_ text: String) -> [(name: String, path: String, relative: Bool)] {
        var sections: [[String: String]] = []
        var current: [String: String]?
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                if let current { sections.append(current) }
                current = line.hasPrefix("[Profile") ? [:] : nil
            } else if let eq = line.firstIndex(of: "="), current != nil {
                current?[String(line[..<eq])] = String(line[line.index(after: eq)...])
            }
        }
        if let current { sections.append(current) }
        let found = sections.filter { $0["Path"] != nil }
        let ordered = found.filter { $0["Default"] == "1" } + found.filter { $0["Default"] != "1" }
        return ordered.map { s in
            let path = s["Path"] ?? ""
            return (name: s["Name"] ?? path, path: path, relative: s["IsRelative"] != "0")
        }
    }

    public static func history(_ profile: URL, limit: Int = 3000) throws -> [Visit] {
        let db = try SQLiteSnapshot(profile.appendingPathComponent("places.sqlite"))
        return try db.rows("SELECT url, title, last_visit_date FROM moz_places WHERE last_visit_date IS NOT NULL AND hidden = 0 ORDER BY last_visit_date DESC LIMIT ?", [Int64(limit)]).compactMap { row in
            guard let url = row[0].text, let time = row[2].int, let date = date(time) else { return nil }
            return ImportMerge.visit(url, title: row[1].text, date: date)
        }
    }

    public static func bookmarks(_ profile: URL) throws -> [Visit] {
        let db = try SQLiteSnapshot(profile.appendingPathComponent("places.sqlite"))
        return try db.rows("SELECT p.url, b.title, b.dateAdded FROM moz_bookmarks b JOIN moz_places p ON p.id = b.fk WHERE b.type = 1 ORDER BY b.parent, b.position").compactMap { row in
            guard let url = row[0].text else { return nil }
            return ImportMerge.visit(url, title: row[1].text, date: row[2].int.flatMap(date) ?? Date())
        }
    }
}
