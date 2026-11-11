import AppKit
import SwiftUI
import MicaCore

/// Preset accents plus mica's colour panel for anything else; every change applies immediately to this window's profile.
struct AccentPicker: View {
    @ObservedObject var store: Store
    @ObservedObject var browser: BrowserModel
    static let presets = ["#6E56CF", "#3E7BFA", "#1F9D8B", "#3FA34D", "#E8A33D", "#E5484D", "#D6409F", "#8D7B6A"]
    var body: some View {
        let accent = browser.prefs.accent.uppercased()
        HStack(alignment: .center, spacing: 6) {
            ForEach(Self.presets, id: \.self) { hex in
                ColorDot(hex: hex, selected: accent == hex, size: 26) { withMotion(Motion.quick) { browser.prefs.accent = hex } }
            }
            ColorWell(hex: accent, presets: Self.presets, label: browser.text("другой цвет", "Другой цвет")) { browser.prefs.accent = $0 }
            Text(accent).font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.text3).textSelection(.enabled)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(browser.text("акцентный цвет", "Акцентный цвет"))
    }
}
