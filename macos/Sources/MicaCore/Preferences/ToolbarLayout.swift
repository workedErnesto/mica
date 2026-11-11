import Foundation

/// Controls the user can place in the top bar or at the bottom of the sidebar.
public enum ToolbarControl: String, Codable, CaseIterable, Sendable {
    case sidebar, back, forward, reload, newTab, bookmarks, history, downloads, extensions, incognito, settings, profile, save
    /// Controls that existed before layouts recorded which items the user has already seen.
    static let legacy: Set<ToolbarControl> = [.sidebar, .back, .forward, .reload, .newTab, .bookmarks, .history, .downloads, .extensions, .settings]
}

/// Zones of the top bar run from the window edge to the address field: `leading` and `trailing` sit at the edges,
/// `leadingInner` and `trailingInner` right next to the field.
public enum ToolbarZone: String, Codable, CaseIterable, Sendable { case leading, leadingInner, trailingInner, trailing, sidebar, hidden }

/// Top bar arrangement. The address field is always centred in the window; only its width is configurable.
public struct ToolbarLayout: Codable, Equatable, Sendable {
    public var leading: [ToolbarControl] = [.sidebar, .back, .forward, .reload]
    public var leadingInner: [ToolbarControl] = []
    /// Saving acts on the page shown, so by default it sits right after the address of that page.
    public var trailingInner: [ToolbarControl] = [.save]
    public var trailing: [ToolbarControl] = []
    public var sidebar: [ToolbarControl] = [.profile, .bookmarks, .history, .downloads, .extensions, .incognito, .settings]
    public var addressWidth = 560.0
    /// Controls this layout already accounts for. A control added in a later version is not in the list,
    /// so it appears in its default place once instead of silently counting as hidden.
    public var known: [ToolbarControl] = ToolbarControl.allCases
    public static let addressRange = 320.0...820.0
    public init() {}
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ToolbarLayout()
        leading = (try? c.decodeIfPresent([String].self, forKey: .leading))?.compactMap(ToolbarControl.init(rawValue:)) ?? d.leading
        leadingInner = (try? c.decodeIfPresent([String].self, forKey: .leadingInner))?.compactMap(ToolbarControl.init(rawValue:)) ?? d.leadingInner
        trailingInner = (try? c.decodeIfPresent([String].self, forKey: .trailingInner))?.compactMap(ToolbarControl.init(rawValue:)) ?? d.trailingInner
        trailing = (try? c.decodeIfPresent([String].self, forKey: .trailing))?.compactMap(ToolbarControl.init(rawValue:)) ?? d.trailing
        sidebar = (try? c.decodeIfPresent([String].self, forKey: .sidebar))?.compactMap(ToolbarControl.init(rawValue:)) ?? d.sidebar
        addressWidth = (try? c.decodeIfPresent(Double.self, forKey: .addressWidth)) ?? d.addressWidth
        let seen = (try? c.decodeIfPresent([String].self, forKey: .known))?.compactMap(ToolbarControl.init(rawValue:)) ?? Array(ToolbarControl.legacy)
        for item in ToolbarControl.allCases where !seen.contains(item) && zone(of: item) == .hidden {
            let target = d.zone(of: item)
            guard target != .hidden else { continue }
            let list = d.items(in: target)
            // Keep the default neighbour order: insert before the first default follower that is already in place.
            let follower = list.drop { $0 != item }.dropFirst().first { zone(of: $0) == target }
            insert(item, in: target, before: follower)
        }
        known = ToolbarControl.allCases
        self = sanitized()
    }
    public func items(in zone: ToolbarZone) -> [ToolbarControl] {
        switch zone {
        case .leading: return leading
        case .leadingInner: return leadingInner
        case .trailingInner: return trailingInner
        case .trailing: return trailing
        case .sidebar: return sidebar
        case .hidden: return ToolbarControl.allCases.filter { self.zone(of: $0) == .hidden }
        }
    }
    public func zone(of item: ToolbarControl) -> ToolbarZone {
        if leading.contains(item) { return .leading }
        if leadingInner.contains(item) { return .leadingInner }
        if trailingInner.contains(item) { return .trailingInner }
        if trailing.contains(item) { return .trailing }
        if sidebar.contains(item) { return .sidebar }
        return .hidden
    }
    /// Moves an item to the end of another zone.
    public mutating func place(_ item: ToolbarControl, in zone: ToolbarZone) {
        guard self.zone(of: item) != zone else { return }
        insert(item, in: zone)
    }
    private mutating func edit(_ zone: ToolbarZone, _ change: (inout [ToolbarControl]) -> Void) {
        switch zone {
        case .leading: change(&leading)
        case .leadingInner: change(&leadingInner)
        case .trailingInner: change(&trailingInner)
        case .trailing: change(&trailing)
        case .sidebar: change(&sidebar)
        case .hidden: break
        }
    }
    /// Drag and drop: puts an item in a zone before another item of that zone, or at its end.
    /// Dropping on the hidden zone removes the item from the bar and the sidebar.
    public mutating func insert(_ item: ToolbarControl, in zone: ToolbarZone, before target: ToolbarControl? = nil) {
        guard item != target else { return }
        for list in [ToolbarZone.leading, .leadingInner, .trailingInner, .trailing, .sidebar] { edit(list) { $0.removeAll { $0 == item } } }
        edit(zone) { list in
            if let target, let index = list.firstIndex(of: target) { list.insert(item, at: index) } else { list.append(item) }
        }
    }
    /// Moves an item earlier (negative) or later within its own zone. Hidden items have no order.
    public mutating func shift(_ item: ToolbarControl, by offset: Int) {
        edit(zone(of: item)) { list in
            guard let index = list.firstIndex(of: item) else { return }
            let target = min(list.count - 1, max(0, index + offset))
            guard target != index else { return }
            list.remove(at: index); list.insert(item, at: target)
        }
    }
    /// Each item lives in one zone at most; the width stays within the supported range.
    public func sanitized() -> ToolbarLayout {
        var seen = Set<ToolbarControl>()
        var result = self
        result.leading = leading.filter { seen.insert($0).inserted }
        result.leadingInner = leadingInner.filter { seen.insert($0).inserted }
        result.trailingInner = trailingInner.filter { seen.insert($0).inserted }
        result.trailing = trailing.filter { seen.insert($0).inserted }
        result.sidebar = sidebar.filter { seen.insert($0).inserted }
        result.addressWidth = min(Self.addressRange.upperBound, max(Self.addressRange.lowerBound, addressWidth))
        return result
    }
    /// What each area shows for the current layout. Without a sidebar its items move to the right side of the bar,
    /// and the sidebar toggle has nothing to act on.
    public func resolved(sidebarAvailable: Bool) -> Resolved {
        if sidebarAvailable { return Resolved(leading: leading, leadingInner: leadingInner, trailingInner: trailingInner, trailing: trailing, sidebar: sidebar) }
        let drop: ([ToolbarControl]) -> [ToolbarControl] = { $0.filter { $0 != .sidebar } }
        return Resolved(leading: drop(leading), leadingInner: drop(leadingInner), trailingInner: drop(trailingInner), trailing: drop(trailing + sidebar), sidebar: [])
    }
    public struct Resolved: Equatable, Sendable {
        public var leading, leadingInner, trailingInner, trailing, sidebar: [ToolbarControl]
        public func items(in zone: ToolbarZone) -> [ToolbarControl] {
            switch zone {
            case .leading: return leading
            case .leadingInner: return leadingInner
            case .trailingInner: return trailingInner
            case .trailing: return trailing
            case .sidebar: return sidebar
            case .hidden: return []
            }
        }
    }
}
