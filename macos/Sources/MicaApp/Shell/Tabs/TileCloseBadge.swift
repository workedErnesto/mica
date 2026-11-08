import AppKit
import SwiftUI
import MicaCore

/// Close badge of an icon-only tab tile (rail, pinned grid, pinned tile in the strip). The tiles have no room for an
/// × of their own, so after the pointer rests on a tile for a second a small raised round button pops in on its
/// top-right corner: its centre sits on the rounded outline, half over the tile and half outside.
struct TileCloseBadge: ViewModifier {
    /// Visible badge diameter; the hit area is a little larger.
    static let size: CGFloat = 16
    static let hitSize: CGFloat = 20
    /// Distance from the tile's bounding corner to the badge centre: with Radius.row 10 this is where the arc passes.
    static let inset: CGFloat = 3
    /// Room the badge and its shadow need outside the tile; scroll views that hold tiles keep this much unclipped.
    static let overhang: CGFloat = size / 2 - inset + 3
    /// Hover time before the badge appears, so passing over the rail does not light up crosses.
    static let delay: Duration = .seconds(1)

    @ObservedObject var tab: Tab
    @ObservedObject var browser: BrowserModel
    /// Pointer over the tile or its badge; the tile draws its hover fill from it.
    @Binding var hover: Bool
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var overTile = false
    @State private var overBadge = false
    @State private var shown = false
    @State private var pending: Task<Void, Never>?
    @State private var leaving: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onHover { overTile = $0; track() }
            .overlay(alignment: .topTrailing) {
                if shown {
                    CloseBadgeButton(label: browser.text("закрыть: ", "Закрыть: ") + title) { close() }
                        .onHover { overBadge = $0; track() }
                        // From the top-trailing corner to a centre at (width - inset, inset) of the tile; the offset
                        // moves the hit area and hover region with the drawing.
                        .offset(x: Self.hitSize / 2 - Self.inset, y: Self.inset - Self.hitSize / 2)
                        .transition(reduced ? .opacity : .asymmetric(
                            insertion: .scale(scale: 0.6).combined(with: .opacity),
                            removal: .scale(scale: 0.8).combined(with: .opacity)))
                }
            }
            .contentShape(Rectangle().inset(by: shown ? -Self.overhang : 0))
            // The part that sticks out must draw above neighbouring tiles.
            .zIndex(shown ? 1 : 0)
            .accessibilityAction(named: Text(browser.text("закрыть", "Закрыть"))) { close() }
            .onDisappear { pending?.cancel(); leaving?.cancel() }
    }

    private var title: String { tab.title.isEmpty ? (tab.url?.host ?? browser.text("новая вкладка", "Новая вкладка")) : tab.title }

    private func close() { withMotion(Motion.quick) { browser.close(tab) } }

    /// Tile and badge report hover separately; crossing from one to the other can report the exit first, so the exit
    /// waits a moment before the badge goes.
    private func track() {
        if overTile || overBadge {
            leaving?.cancel(); leaving = nil
            hover = true
            guard !shown, pending == nil else { return }
            pending = Task { @MainActor in
                try? await Task.sleep(for: Self.delay)
                guard !Task.isCancelled else { return }
                pending = nil
                withAnimation(reduced ? Motion.hover : Motion.pressSpring) { shown = true }
            }
        } else {
            pending?.cancel(); pending = nil
            leaving?.cancel()
            leaving = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled else { return }
                leaving = nil
                hover = false
                if shown { withAnimation(Motion.hover) { shown = false } }
            }
        }
    }
}

/// The badge itself: raised round face with a hairline and a soft shadow, the cross brightens on hover and the face
/// darkens while pressed.
struct CloseBadgeButton: View {
    let label: String
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark").font(.system(size: 7.5, weight: .semibold))
        }
        .buttonStyle(CloseBadgeStyle(hover: hover))
        .onHover { hover = $0 }
        .animation(Motion.hover, value: hover)
        .help(label)
        .accessibilityLabel(label)
    }
}

private struct CloseBadgeStyle: ButtonStyle {
    let hover: Bool
    func makeBody(configuration: Configuration) -> some View { Face(configuration: configuration, hover: hover) }

    private struct Face: View {
        let configuration: ButtonStyleConfiguration
        let hover: Bool
        @Environment(\.accessibilityReduceMotion) private var reduced
        var body: some View {
            configuration.label
                .foregroundStyle(hover || configuration.isPressed ? Palette.ink : Palette.text2)
                .frame(width: TileCloseBadge.size, height: TileCloseBadge.size)
                .background {
                    Circle().fill(Palette.raised)
                        .overlay(Circle().fill(configuration.isPressed ? Palette.pressed : hover ? Palette.hover : .clear))
                        .shadow(color: Palette.shadowStrong, radius: 2, y: 1)
                }
                .overlay(Circle().strokeBorder(Palette.hairlineStrong, lineWidth: 1))
                // Colour is not movement: it fades even with Reduce Motion, the press scale does not.
                .animation(Motion.hover, value: configuration.isPressed)
                .frame(width: TileCloseBadge.hitSize, height: TileCloseBadge.hitSize)
                .contentShape(Circle())
                .scaleEffect(configuration.isPressed && !reduced ? 0.88 : 1)
                .animation(reduced ? nil : Motion.pressSpring, value: configuration.isPressed)
        }
    }
}
