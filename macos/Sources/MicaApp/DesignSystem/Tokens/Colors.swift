import AppKit
import SwiftUI

func rgb(_ value: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((value >> 16) & 0xff) / 255, green: CGFloat((value >> 8) & 0xff) / 255, blue: CGFloat(value & 0xff) / 255, alpha: alpha)
}

extension Color {
    /// Resolves per appearance, including Increase Contrast, without any observers of our own.
    static func dynamic(_ light: NSColor, _ dark: NSColor, contrastLight: NSColor? = nil, contrastDark: NSColor? = nil) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua]) {
            case .darkAqua?: return dark
            case .accessibilityHighContrastDarkAqua?: return contrastDark ?? dark
            case .accessibilityHighContrastAqua?: return contrastLight ?? light
            default: return light
            }
        })
    }
}

