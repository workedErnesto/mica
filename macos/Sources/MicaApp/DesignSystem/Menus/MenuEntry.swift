import AppKit
import SwiftUI
import MicaCore

// mica draws its own menus: context menus of the shell and of web pages, and the "more" buttons in panels. A menu is
// a small borderless panel above the window, so it can extend past the window edge and over the web page.

struct MenuEntry: Identifiable {
    enum Kind { case action, divider }
    let id = UUID()
    var kind: Kind = .action
    var title = ""
    var symbol: String?
    var enabled = true
    var checked = false
    var destructive = false
    /// Profile mark drawn in place of the symbol.
    var profile: Profile?
    var action: () -> Void = {}
    /// Entries shown on a right click of this row, in place of the menu; they win over the row's own action.
    var secondary: [MenuEntry] = []
    /// Entries that open beside this row when the pointer rests on it, as a system submenu does.
    var submenu: [MenuEntry] = []
    static func item(_ title: String, symbol: String? = nil, enabled: Bool = true, checked: Bool = false, destructive: Bool = false, action: @escaping () -> Void) -> MenuEntry {
        MenuEntry(title: title, symbol: symbol, enabled: enabled, checked: checked, destructive: destructive, action: action)
    }
    static func profile(_ title: String, profile: Profile, checked: Bool = false, secondary: [MenuEntry] = [], action: @escaping () -> Void) -> MenuEntry {
        MenuEntry(title: title, checked: checked, profile: profile, action: action, secondary: secondary)
    }
    static func submenu(_ title: String, _ entries: [MenuEntry]) -> MenuEntry { MenuEntry(title: title, submenu: entries) }
    static var divider: MenuEntry { MenuEntry(kind: .divider) }
    func with(enabled: Bool) -> MenuEntry { var copy = self; copy.enabled = self.enabled && enabled; return copy }
}

@resultBuilder
enum MenuBuilder {
    static func buildBlock(_ parts: [MenuEntry]...) -> [MenuEntry] { parts.flatMap { $0 } }
    static func buildExpression(_ entry: MenuEntry) -> [MenuEntry] { [entry] }
    static func buildExpression(_ entries: [MenuEntry]) -> [MenuEntry] { entries }
    static func buildOptional(_ entries: [MenuEntry]?) -> [MenuEntry] { entries ?? [] }
    static func buildEither(first entries: [MenuEntry]) -> [MenuEntry] { entries }
    static func buildEither(second entries: [MenuEntry]) -> [MenuEntry] { entries }
    static func buildArray(_ parts: [[MenuEntry]]) -> [MenuEntry] { parts.flatMap { $0 } }
}

extension Array where Element == MenuEntry {
    /// No leading, trailing or doubled dividers, whatever the conditional parts produced.
    var tidy: [MenuEntry] {
        var result: [MenuEntry] = []
        for entry in self where !(entry.kind == .divider && (result.isEmpty || result.last?.kind == .divider)) { result.append(entry) }
        while result.last?.kind == .divider { result.removeLast() }
        return result
    }
}
