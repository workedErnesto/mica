import AppKit
import SwiftUI
import ImageIO
import MicaCore

extension Look {
    /// Standard themes keep the neutral stone palette; the custom theme tints the shell and the controls.
    init(_ preferences: Preferences) {
        guard preferences.theme == .custom, let c = HexColor.parse(preferences.accent) else { self = .standard; return }
        let accent = Color(.sRGB, red: c.red, green: c.green, blue: c.blue)
        // Text on the accent takes whichever of white or ink gives more contrast.
        let luminance = HexColor.luminance(preferences.accent) ?? 0
        let onWhite = 1.05 / (luminance + 0.05), onInk = (luminance + 0.05) / 0.0618
        self.init(accent: accent, onAccent: onWhite >= onInk ? .white : Color(red: 0.11, green: 0.098, blue: 0.09), shell: Palette.shell.mix(with: accent, by: preferences.customTint))
    }
}

/// Appearance chosen by the user that the static palette cannot know: the custom accent and the tinted shell.
/// Passed through the environment so every control redraws when it changes.
struct Look: Equatable {
    var accent: Color?
    var onAccent: Color = .white
    var shell: Color = Palette.shell
    static let standard = Look()
    /// Fill of primary buttons, switches, sliders and progress.
    var primary: Color { accent ?? Palette.primary }
    var onPrimary: Color { accent == nil ? Palette.onPrimary : onAccent }
    var focus: Color { accent ?? Palette.focusRing }
}

extension EnvironmentValues { @Entry var look = Look.standard }
