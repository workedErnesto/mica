import AppKit
import SwiftUI

// mica design system: paper-white light and warm stone dark themes, ink primary, soft concentric geometry.
// Every reusable control here owns only its own shape; parents own spacing.

/// Window chrome geometry. The standard window buttons are moved to the vertical center of `bar`.
enum Chrome {
    /// Top bar. The address field is `field` tall, leaving 8 pt above and below it.
    static let bar: CGFloat = 44
    static let field: CGFloat = 28
    /// Collapsed sidebar: a rail of site icons.
    static let rail: CGFloat = 52
    /// Width taken by one toolbar button and the gap after it.
    static let item: CGFloat = 30
    static let lightsX: CGFloat = 14
    static let lightsStep: CGFloat = 20
    /// Width reserved for the window buttons, measured from the window edge.
    static let lightsInset: CGFloat = 84
}

enum Space { static let micro: CGFloat = 4; static let small: CGFloat = 8; static let normal: CGFloat = 12; static let section: CGFloat = 20; static let large: CGFloat = 32 }

/// Concentric radii: an inner shape uses the outer radius minus the padding between them.
enum Radius {
    /// Inset between the window edge and the floating surfaces (content card, floating sidebar).
    static let gutter: CGFloat = 8
    /// Content card. Matches the macOS 15 window corner so the card reads as a window inside the window.
    static let card: CGFloat = 10
    /// Floating sidebar, popovers, settings groups.
    static let panel: CGFloat = 16
    /// Padding inside a panel; rows inside it use panel - panelPadding.
    static let panelPadding: CGFloat = 6
    static let row: CGFloat = panel - panelPadding
    /// Segmented track and its thumb (track - 2 pt padding).
    static let track: CGFloat = 10
    static let thumb: CGFloat = track - 2
    static let icon: CGFloat = 8
    /// Window-level cards: settings, onboarding, clearing data.
    static let modal: CGFloat = panel + 2
}
