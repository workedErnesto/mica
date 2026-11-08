import Foundation

public struct SavedTab: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var url: URL?
    public var title: String
    public var pinned: Bool
    public init(id: UUID = UUID(), url: URL? = nil, title: String = "", pinned: Bool = false) { self.id = id; self.url = url; self.title = title; self.pinned = pinned }
}

public struct SavedWindow: Codable, Equatable, Sendable {
    public var tabs: [SavedTab]
    public var selected: UUID?
    public init(tabs: [SavedTab], selected: UUID?) { self.tabs = tabs; self.selected = selected }
}

public struct Session: Codable, Sendable {
    public var version = 1
    public var windows: [SavedWindow]
    public init(windows: [SavedWindow]) { self.windows = windows }
    public func validated() -> Session {
        guard version == 1 else { return Session(windows: []) }
        var ids = Set<UUID>()
        return Session(windows: windows.prefix(20).map { window in
            let tabs = window.tabs.prefix(300).filter { tab in
                (tab.url == nil || (["http", "https"].contains(tab.url!.scheme?.lowercased() ?? "") && AddressParser.navigable(tab.url!))) && ids.insert(tab.id).inserted
            }.sorted { $0.pinned && !$1.pinned }
            return SavedWindow(tabs: tabs, selected: tabs.contains(where: { $0.id == window.selected }) ? window.selected : tabs.first?.id)
        })
    }
}
