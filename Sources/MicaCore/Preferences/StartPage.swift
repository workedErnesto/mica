import Foundation

public struct StartShortcut: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var url: URL
    public init(id: UUID = UUID(), title: String, url: URL) { self.id = id; self.title = title; self.url = url }
}

public enum StartSection: String, Codable, CaseIterable, Sendable { case custom, frequent, bookmarks }

/// What the start page shows and in which order. `sections` holds only the visible sections.
public struct StartPage: Codable, Equatable, Sendable {
    public var wordmark = true
    public var sections: [StartSection] = [.custom, .frequent]
    public var frequentCount = 8
    public var shortcuts: [StartShortcut] = []
    public var hiddenHosts: [String] = []
    public static let frequentChoices = [4, 8, 12, 16]
    public init() {}
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = StartPage()
        wordmark = (try? c.decodeIfPresent(Bool.self, forKey: .wordmark)) ?? d.wordmark
        let raw = (try? c.decodeIfPresent([String].self, forKey: .sections))?.compactMap(StartSection.init(rawValue:)) ?? d.sections
        var seen = Set<StartSection>(); sections = raw.filter { seen.insert($0).inserted }
        frequentCount = min(16, max(4, (try? c.decodeIfPresent(Int.self, forKey: .frequentCount)) ?? d.frequentCount))
        shortcuts = ((try? c.decodeIfPresent([StartShortcut].self, forKey: .shortcuts)) ?? d.shortcuts).filter { AddressParser.navigable($0.url) && $0.url.scheme?.hasPrefix("http") == true }
        hiddenHosts = (try? c.decodeIfPresent([String].self, forKey: .hiddenHosts)) ?? d.hiddenHosts
    }
    public mutating func setVisible(_ section: StartSection, _ visible: Bool) {
        if visible { if !sections.contains(section) { sections.append(section) } }
        else { sections.removeAll { $0 == section } }
    }
    public mutating func shift(_ section: StartSection, by offset: Int) {
        guard let index = sections.firstIndex(of: section) else { return }
        let target = min(sections.count - 1, max(0, index + offset))
        guard target != index else { return }
        sections.remove(at: index); sections.insert(section, at: target)
    }
    public mutating func moveShortcut(_ id: UUID, before target: UUID) {
        guard id != target, let source = shortcuts.first(where: { $0.id == id }), shortcuts.contains(where: { $0.id == target }) else { return }
        shortcuts.removeAll { $0.id == id }
        shortcuts.insert(source, at: shortcuts.firstIndex { $0.id == target }!)
    }
    public mutating func shiftShortcut(_ id: UUID, by offset: Int) {
        guard let index = shortcuts.firstIndex(where: { $0.id == id }) else { return }
        let target = min(shortcuts.count - 1, max(0, index + offset))
        guard target != index else { return }
        let item = shortcuts.remove(at: index); shortcuts.insert(item, at: target)
    }
    /// A shortcut needs a web address; plain words would silently turn into a search, so they are rejected.
    public static func shortcutURL(_ input: String, engine: SearchEngine) -> URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard case .web(let url) = AddressParser.resolve(text, engine: engine), !engine.isSearch(url, for: text) else { return nil }
        return url
    }
    /// Sites by visit count, one tile per host, skipping hidden hosts, existing shortcuts and reserved test domains.
    public static func frequent(_ history: [Visit], excluding: Set<String>, limit: Int) -> [Visit] {
        var counts: [String: (count: Int, visit: Visit)] = [:]
        for visit in history.prefix(600) {
            guard let host = visit.url.host?.lowercased(), !excluding.contains(host), !host.hasSuffix(".invalid"), !host.hasSuffix(".test"), host != "localhost" else { continue }
            counts[host] = ((counts[host]?.count ?? 0) + 1, counts[host]?.visit ?? visit)
        }
        return counts.sorted { $0.value.count != $1.value.count ? $0.value.count > $1.value.count : $0.key < $1.key }.prefix(limit).map { entry in
            let url = entry.value.visit.url
            var root = Visit(url: URL(string: (url.scheme ?? "https") + "://" + (url.host ?? "")) ?? url, title: "")
            root.id = entry.value.visit.id
            return root
        }
    }
}
