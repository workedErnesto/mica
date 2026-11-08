import Foundation

/// Orion's documented local profile files. Read only after the user grants folder access.
public enum OrionReader {
    public static func profiles(browser: ImportBrowser, root: URL) -> [ImportProfile] {
        let fm = FileManager.default
        var names: [String: String] = [:]
        if let data = try? Data(contentsOf: root.appendingPathComponent("profiles")),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let profiles = plist["profiles"] as? [[String: Any]] {
            for profile in profiles {
                if let id = profile["identifier"] as? String, let name = profile["name"] as? String { names[id] = name }
            }
        }
        return (((try? fm.contentsOfDirectory(atPath: root.path)) ?? []).filter { $0 == "Defaults" || UUID(uuidString: $0) != nil }).sorted().compactMap { name in
            let path = root.appendingPathComponent(name, isDirectory: true)
            guard fm.fileExists(atPath: path.appendingPathComponent("favourites.plist").path) || fm.fileExists(atPath: path.appendingPathComponent("history").path) else { return nil }
            return ImportProfile(browser: browser, name: names[name] ?? name, path: path)
        }
    }

    public static func history(_ profile: URL, limit: Int = 3000) throws -> [Visit] {
        let db = try SQLiteSnapshot(profile.appendingPathComponent("history"))
        return try db.rows("SELECT URL, TITLE, CAST(strftime('%s', LAST_VISIT_TIME) AS INTEGER) FROM history_items ORDER BY LAST_VISIT_TIME DESC LIMIT ?", [Int64(limit)]).compactMap { row in
            guard let url = row[0].text, let time = row[2].int else { return nil }
            return ImportMerge.visit(url, title: row[1].text, date: Date(timeIntervalSince1970: Double(time)))
        }
    }

    public static func bookmarks(_ profile: URL) throws -> [Visit] {
        let file = profile.appendingPathComponent("favourites.plist")
        guard let data = try? Data(contentsOf: file) else { throw ImportError.noAccess(file.path) }
        guard let nodes = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: [String: Any]] else { throw ImportError.unreadable(file.path) }
        let ordered = nodes.values.sorted { ($0["index"] as? Int ?? 0) < ($1["index"] as? Int ?? 0) }
        return ordered.compactMap { node in
            guard let url = node["url"] as? String else { return nil }
            let date = (node["dateAdded"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) } ?? Date()
            return ImportMerge.visit(url, title: node["title"] as? String, date: date)
        }
    }
}
