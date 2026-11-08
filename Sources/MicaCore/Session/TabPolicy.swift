import Foundation

public enum TabPhase: String, Sendable { case fresh, restored, live, terminated }

public enum TabPolicy {
    public static func shouldLoadOnRestore(_ tab: SavedTab, selected: UUID?, preferences: Preferences) -> Bool {
        tab.id == selected || !preferences.lazyRestore || preferences.eagerHosts.contains(tab.url?.host?.lowercased() ?? "")
    }
    public static func moving(_ tabs: [SavedTab], id: UUID, before: UUID) -> [SavedTab] {
        guard let source = tabs.first(where: { $0.id == id }), let destination = tabs.first(where: { $0.id == before }), source.id != destination.id, source.pinned == destination.pinned else { return tabs }
        var result = tabs.filter { $0.id != id }
        if let index = result.firstIndex(where: { $0.id == before }) { result.insert(source, at: index) }
        return result
    }
}
