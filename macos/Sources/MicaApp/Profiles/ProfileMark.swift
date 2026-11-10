import AppKit
import SwiftUI
import MicaCore

extension Color {
    /// Six-digit hex from user data; an unreadable value draws as the track colour instead of failing.
    init(hex: String) {
        if let c = HexColor.parse(hex) { self.init(.sRGB, red: c.red, green: c.green, blue: c.blue) } else { self = Palette.track }
    }
}

/// Profile icon on its background, a tile with the same concentric rounding as site tiles.
/// The glyph is white or ink as the profile chooses; automatic picks by contrast.
struct ProfileMark: View {
    let icon: String
    let background: String
    var glyph: ProfileGlyph = .auto
    var size: CGFloat = 20
    init(profile: Profile, size: CGFloat = 20) { icon = profile.icon; background = profile.background; glyph = profile.glyph; self.size = size }
    init(icon: String, background: String, glyph: ProfileGlyph = .auto, size: CGFloat = 20) { self.icon = icon; self.background = background; self.glyph = glyph; self.size = size }
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).fill(Color(hex: background))
            Glyph(name: icon, size: size * 0.5, weight: .semibold)
                .foregroundStyle(Profiles.lightGlyph(on: background, glyph: glyph) ? Color.white : Color(red: 0.07, green: 0.07, blue: 0.075))
        }
        .frame(width: size, height: size)
        .animation(Motion.hover, value: background)
        .animation(Motion.hover, value: glyph)
        .accessibilityHidden(true)
    }
}

/// Line at the top of settings that a profile owns, so it is clear which profile they change.
struct ProfileScope: View {
    @ObservedObject var store: Store
    @ObservedObject var browser: BrowserModel
    var body: some View {
        if store.profiles.count > 1 {
            HStack(spacing: Space.small) {
                ProfileMark(profile: browser.profile, size: 18)
                Text(store.text("настройки профиля ", "Настройки профиля ") + store.quoted(store.profileName(browser.profile))).font(.system(size: 12)).foregroundStyle(Palette.text2).lineLimit(1)
                Spacer(minLength: Space.small)
                Button(store.text("профили", "Профили")) { withMotion(Motion.quick) { browser.editingProfile = browser.profileID; browser.settingsSection = .profiles } }
                    .buttonStyle(MButtonStyle(kind: .ghost, compact: true))
            }
            .padding(.leading, 10).padding(.trailing, 4).frame(height: 36)
            .background(RoundedRectangle(cornerRadius: Radius.panel - 4, style: .continuous).fill(Palette.track.opacity(0.6)))
        }
    }
}
