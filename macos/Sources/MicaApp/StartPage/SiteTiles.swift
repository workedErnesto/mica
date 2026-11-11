import AppKit
import SwiftUI
import WebKit
import MicaCore
import UniformTypeIdentifiers

/// Custom sites reorder by dragging one tile onto another.
struct ShortcutDrag: ViewModifier {
    let site: StartSite
    @ObservedObject var store: Store
    @ObservedObject var browser: BrowserModel
    func body(content: Content) -> some View {
        if let id = site.shortcut {
            content
                .onDrag { NSItemProvider(object: ("mica-shortcut:" + id.uuidString) as NSString) }
                .onDrop(of: [.text], isTargeted: nil) { providers in
                    guard let provider = providers.first else { return false }
                    _ = provider.loadObject(ofClass: String.self) { string, _ in
                        guard let string, string.hasPrefix("mica-shortcut:"), let source = UUID(uuidString: String(string.dropFirst("mica-shortcut:".count))) else { return }
                        Task { @MainActor in withMotion(Motion.quick) { browser.prefs.start.moveShortcut(source, before: id) } }
                    }
                    return true
                }
        } else { content }
    }
}

struct SiteTile: View {
    let title: String
    let host: String
    let url: URL
    @ObservedObject var favicons: Favicons
    let action: () -> Void
    @State private var hover = false
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        let aura = MotionTokens.aura
        Button(action: action) {
            VStack(spacing: Space.small) {
                ZStack {
                    // The glow exists only while it shows, so a grid of resting tiles carries no blur layers.
                    if hover {
                        SiteIcon(url: url, favicons: favicons, size: aura.icon, plain: true)
                            .saturation(aura.saturation)
                            .blur(radius: aura.blur)
                            .transition(reduced ? .opacity : .modifier(active: AuraGlow(shown: false), identity: AuraGlow(shown: true)))
                            .accessibilityHidden(true)
                    }
                    SiteIcon(url: url, favicons: favicons, size: aura.icon, plain: true)
                        .scaleEffect(hover && !reduced ? aura.iconScale : 1)
                        .offset(y: hover && !reduced ? -aura.iconRise : 0)
                        .animation(reduced ? Motion.hover : Motion.bouncySpring, value: hover)
                }
                .modifier(TileBox(hover: hover))
                Text(label).font(.system(size: 11.5)).foregroundStyle(hover ? Palette.ink : Palette.text2).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.95))
        .onHover { hover = $0 }
        .animation(reduced ? Motion.hover : Motion.snappySpring, value: hover)
        .help(host)
        .accessibilityLabel(label)
    }
    private var label: String { title.isEmpty ? (host.hasPrefix("www.") ? String(host.dropFirst(4)) : host) : title }
}

/// The site's own colour lighting its tile from inside: the blurred icon grows from the middle of the plate
/// and fades in to the theme's opacity (MotionTokens.aura).
private struct AuraGlow: ViewModifier {
    let shown: Bool
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        let aura = MotionTokens.aura
        content
            .scaleEffect(shown ? aura.scale : aura.restScale)
            .opacity(shown ? (scheme == .dark ? aura.darkOpacity : aura.lightOpacity) : 0)
    }
}

/// 60 pt tile shared by site tiles and the add tile, so both line up in the grid. A site tile sits on a tonal
/// plate without a shadow, so a frosted start page shows through it; the plate clips the hover glow.
struct TileBox: ViewModifier {
    let hover: Bool
    var dashed = false
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
        content
            .frame(width: 60, height: 60)
            .background(shape.fill(dashed ? (hover ? Palette.hover : .clear) : hover ? Palette.toneHover : Palette.tone))
            .clipShape(shape)
            .overlay { if dashed { shape.strokeBorder(Palette.hairlineStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3])) } }
    }
}

struct AddShortcutTile: View {
    @ObservedObject var store: Store
    @ObservedObject var browser: BrowserModel
    @State private var hover = false
    @State private var adding = false
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        Button { adding = true } label: {
            VStack(spacing: Space.small) {
                Image(systemName: "plus").font(.system(size: 16, weight: .regular)).foregroundStyle(hover ? Palette.ink : Palette.text2)
                    .modifier(TileBox(hover: hover, dashed: true))
                Text(browser.text("добавить", "Добавить")).font(.system(size: 11.5)).foregroundStyle(hover ? Palette.ink : Palette.text3).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.95))
        .onHover { hover = $0 }
        .animation(reduced ? Motion.hover : Motion.snappySpring, value: hover)
        .stickyPopover(isPresented: $adding) { ShortcutEditor(store: store, browser: browser, editing: nil) { adding = false } }
        .accessibilityLabel(browser.text("добавить сайт на начальную страницу", "Добавить сайт на начальную страницу"))
    }
}
