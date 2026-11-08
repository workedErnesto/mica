import Foundation

/// Where the tabs live. `top` puts the address bar above the tab strip; `tabsAbove` puts the strip in the title bar band
/// next to the window buttons and the address bar under it.
public enum TabLayout: String, Codable, CaseIterable, Sendable {
    case left, right, top, tabsAbove
    /// Windows narrower than this show the tabs across the top without changing the saved layout.
    public static let narrowWidth = 760.0
    /// Tabs run across the window and there is no sidebar.
    public var horizontal: Bool { self == .top || self == .tabsAbove }
    /// Side of the sidebar, nil when the tabs run across the top.
    public var sidebarEdge: TabLayout? { horizontal ? nil : self }
    /// Layout of a window this wide: a narrow window keeps a top layout as chosen and moves the sidebar ones to `top`.
    public func fitting(width: Double) -> TabLayout { width < Self.narrowWidth && !horizontal ? .top : self }
}

/// `custom` uses `customBase` for light or dark and tints the shell with `accent`.
public enum Theme: String, Codable, CaseIterable, Sendable { case system, light, dark, custom }

/// Six-digit hex colours for the custom accent.
public enum HexColor {
    public static func parse(_ text: String) -> (red: Double, green: Double, blue: Double)? {
        var hex = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        return (Double((value >> 16) & 0xff) / 255, Double((value >> 8) & 0xff) / 255, Double(value & 0xff) / 255)
    }
    public static func string(red: Double, green: Double, blue: Double) -> String {
        func byte(_ v: Double) -> Int { Int((min(1, max(0, v)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }
    /// Relative luminance (WCAG); decides whether text on the accent is light or dark.
    public static func luminance(_ text: String) -> Double? {
        guard let c = parse(text) else { return nil }
        func linear(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(c.red) + 0.7152 * linear(c.green) + 0.0722 * linear(c.blue)
    }
}
