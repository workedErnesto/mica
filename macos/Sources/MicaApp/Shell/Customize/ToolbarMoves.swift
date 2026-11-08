import AppKit
import SwiftUI
import MicaCore

// Toolbar customization happens on the real window: the top bar and the bottom of the sidebar turn into drop zones,
// and a palette of every control slides over the page. Drag a control into a zone, onto another control to put it
// before that one, or back onto the palette to remove it. The context menu of each control offers the same moves.

enum ToolbarDrag {
    static let prefix = "mica-toolbar:"
    static func payload(_ item: ToolbarControl) -> String { prefix + item.rawValue }
    static func item(_ payload: String) -> ToolbarControl? {
        guard payload.hasPrefix(prefix) else { return nil }
        return ToolbarControl(rawValue: String(payload.dropFirst(prefix.count)))
    }
}

extension ToolbarZone {
    @MainActor func title(_ store: Store) -> String {
        switch self {
        case .leading: return store.text("у левого края", "У левого края")
        case .leadingInner: return store.text("слева от адреса", "Слева от адреса")
        case .trailingInner: return store.text("справа от адреса", "Справа от адреса")
        case .trailing: return store.text("у правого края", "У правого края")
        case .sidebar: return store.text("в боковой панели", "В боковой панели")
        case .hidden: return store.text("не показывается", "Не показывается")
        }
    }
}

/// Moves shared by drag and drop, the context menu and VoiceOver actions.
@MainActor
struct ToolbarMoves {
    let store: Store
    func move(_ item: ToolbarControl, to zone: ToolbarZone, before target: ToolbarControl? = nil) {
        withMotion(Motion.quick) { store.preferences.toolbar.insert(item, in: zone, before: target) }
    }
    /// Appending in the top layout: sidebar items are shown after the right-hand ones, so an item dropped
    /// at the end of the right zone joins them to appear last.
    func append(_ item: ToolbarControl, to zone: ToolbarZone, layout: TabLayout) {
        if zone == .trailing, layout.horizontal, !store.preferences.toolbar.sidebar.filter({ $0 != item }).isEmpty { move(item, to: .sidebar) }
        else { move(item, to: zone) }
    }
    static let placements: [ToolbarZone] = [.leading, .leadingInner, .trailingInner, .trailing, .sidebar]
    func menu(_ item: ToolbarControl, layout: TabLayout) -> [MenuEntry] {
        let current = store.preferences.toolbar.zone(of: item)
        return Self.placements.map { zone in
            MenuEntry.item(zone.title(store), checked: current == zone) { move(item, to: zone) }
                .with(enabled: current != zone && !(zone == .sidebar && layout.horizontal))
        } + [.divider, .item(store.text("убрать", "Убрать"), destructive: true) { move(item, to: .hidden) }.with(enabled: current != .hidden)]
    }
}
