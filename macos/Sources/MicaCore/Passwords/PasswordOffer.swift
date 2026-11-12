import Foundation
import CoreGraphics

/// What mica offers beside a focused sign-in field of the page: saved accounts of exactly this origin, or a strong
/// password for a field that asks for a new one. The offer is a small panel anchored to the field, not a dialog.
public enum PasswordOffer: Equatable, Sendable {
    /// Saved accounts of the origin, most recently used first.
    case fill([SavedLogin])
    case generate

    /// Rows the panel shows before it scrolls.
    public static let visibleRows = 4

    /// `isNew`: the field has `autocomplete="new-password"`. `maxLength`: the field's `maxLength`, -1 without one.
    public static func decide(vault: Vault, origin: String, isNew: Bool, maxLength: Int, offerPasswords: Bool, fillPasswords: Bool) -> PasswordOffer? {
        if isNew {
            // A generated password on a site excluded from saving would never be offered for saving and would be lost.
            guard offerPasswords, !vault.never.contains(origin), maxLength < 0 || maxLength >= 8 else { return nil }
            return .generate
        }
        guard fillPasswords else { return nil }
        let matches = vault.matches(for: origin)
        return matches.isEmpty ? nil : .fill(matches)
    }
}

/// Whether the offer beside a field is showing. Each focus of a sign-in field gets a new number from the page script.
/// "Not now" (Esc, a click elsewhere) and typing hide the offer only for that focus: it comes back when the field is
/// focused again, clicked again, or the page changes. Nothing of this is stored. The one lasting choice is
/// "never for this site" (`Vault.never`), which stops offers to save and to generate passwords there.
public struct PasswordOfferSession: Equatable, Sendable {
    public enum Event: Equatable, Sendable {
        case focus(Int)
        /// A click into the field that already has focus, as in Safari and Chrome: the offer returns.
        case click(Int)
        /// The person types into the field.
        case input(Int)
        case blur(Int)
        /// Esc or "not now".
        case dismiss
        /// An account or the generated password was filled in.
        case accept
        /// Another document, another tab, or the page went under a window overlay.
        case leave
    }
    public private(set) var field: Int?
    public private(set) var dismissed = false
    public init() {}
    public var visible: Bool { field != nil && !dismissed }

    public mutating func apply(_ event: Event) {
        switch event {
        case .focus(let id): if field != id { field = id; dismissed = false }
        case .click(let id): field = id; dismissed = false
        case .input(let id): if field == id { dismissed = true }
        case .blur(let id): if field == id { field = nil; dismissed = false }
        case .dismiss, .accept: dismissed = true
        case .leave: field = nil; dismissed = false
        }
    }
}

/// Where the offer goes over the page. Rectangles have a top-left origin in the web view's points.
public struct PasswordOfferPlacement: Equatable, Sendable {
    public enum Edge: String, Sendable { case above, below }
    public var frame: CGRect
    public var edge: Edge
    public init(frame: CGRect, edge: Edge) { self.frame = frame; self.edge = edge }

    /// A rectangle the page script measured in CSS pixels of the visual viewport, in the view's points. `innerWidth`
    /// is the page's `window.innerWidth`, so page zoom and pinch magnification are both accounted for.
    public static func viewRect(css: CGRect, innerWidth: CGFloat, viewWidth: CGFloat) -> CGRect {
        guard innerWidth > 0, viewWidth > 0 else { return css }
        let k = viewWidth / innerWidth
        return CGRect(x: css.minX * k, y: css.minY * k, width: css.width * k, height: css.height * k)
    }

    /// Above the field when it fits, otherwise below, otherwise on the side with more room, clamped into the page with
    /// `margin`. The leading edges line up with the field's. Nil when the field is scrolled out of the visible page.
    public static func place(field: CGRect, bounds: CGSize, panel: CGSize, gap: CGFloat, margin: CGFloat) -> PasswordOfferPlacement? {
        guard field.maxY > 0, field.minY < bounds.height, field.maxX > 0, field.minX < bounds.width else { return nil }
        let width = min(panel.width, bounds.width - 2 * margin)
        guard width > 0, panel.height > 0 else { return nil }
        let x = max(margin, min(field.minX, bounds.width - margin - width))
        let above = field.minY - gap - panel.height
        let below = field.maxY + gap
        if above >= margin { return .init(frame: CGRect(x: x, y: above, width: width, height: panel.height), edge: .above) }
        if below + panel.height <= bounds.height - margin { return .init(frame: CGRect(x: x, y: below, width: width, height: panel.height), edge: .below) }
        let roomAbove = field.minY - gap - margin
        let roomBelow = bounds.height - margin - below
        let edge: Edge = roomAbove > roomBelow ? .above : .below
        let lowest = max(margin, bounds.height - margin - panel.height)
        let y = max(margin, min(edge == .above ? above : below, lowest))
        return .init(frame: CGRect(x: x, y: y, width: width, height: panel.height), edge: edge)
    }
}
