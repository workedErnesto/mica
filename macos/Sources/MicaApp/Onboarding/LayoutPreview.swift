import AppKit
import SwiftUI
import AVFoundation
import MicaCore

/// Miniature of the real shell: same tokens and geometry, reacting to layout, collapsed rail, theme, accent and material.
struct LayoutPreview: View {
    @ObservedObject var store: Store
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let mode = store.appearanceMode
        let dark = mode == .dark || (mode == .system && scheme == .dark)
        let look = store.look
        let layout = store.preferences.layout
        let collapsed = store.preferences.sidebarCollapsed && !layout.horizontal
        ZStack {
            look.shell
            VStack(spacing: 6) {
                if layout == .tabsAbove {
                    // Tabs beside the window buttons, the address row under them.
                    HStack(spacing: 4) { lights.padding(.trailing, 4); tabs; Spacer() }
                        .frame(height: 14)
                        .transition(.opacity)
                    address.frame(height: 12)
                } else {
                    ZStack {
                        HStack(spacing: 4) { lights; Spacer() }
                        address
                    }
                    .frame(height: 14)
                    if layout == .top { HStack(spacing: 4) { tabs; Spacer() }.transition(.opacity) }
                }
                HStack(spacing: 6) {
                    if layout == .left { rail(collapsed).transition(Motion.slide(.leading)) }
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Palette.canvas)
                        .overlay {
                            VStack(spacing: 6) {
                                Text("mica").font(.system(size: 18, weight: .light)).tracking(-0.6).foregroundStyle(Palette.text3)
                                Capsule().fill(look.primary).frame(width: 46, height: 12)
                            }
                        }
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
                        .shadow(color: Palette.shadow, radius: 3, y: 1)
                    if layout == .right { rail(collapsed).transition(Motion.slide(.trailing)) }
                }
            }
            .padding(8)
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.panel - 4, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.panel - 4, style: .continuous).strokeBorder(Palette.hairlineStrong, lineWidth: 1))
        .environment(\.colorScheme, dark ? .dark : .light)
        .animation(Motion.panel, value: layout)
        .animation(Motion.panel, value: collapsed)
        .animation(Motion.hover, value: dark)
        .animation(Motion.hover, value: store.preferences.accent)
        .accessibilityElement().accessibilityLabel(store.text("предпросмотр оформления и раскладки", "Предпросмотр оформления и раскладки"))
    }
    private var address: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Palette.track).frame(width: 130, height: 11)
    }
    private var tabs: some View {
        ForEach(0..<4, id: \.self) { index in RoundedRectangle(cornerRadius: 4, style: .continuous).fill(index == 0 ? Palette.selected : Palette.track).frame(width: 52, height: 12) }
    }
    private var lights: some View {
        HStack(spacing: 3) { ForEach(0..<3, id: \.self) { _ in Circle().fill(Palette.switchOff).frame(width: 6, height: 6) } }
    }
    private func rail(_ collapsed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(0..<5, id: \.self) { index in
                if collapsed {
                    RoundedRectangle(cornerRadius: 3, style: .continuous).fill(index == 0 ? Palette.selected : Palette.track).frame(width: 12, height: 12)
                } else {
                    RoundedRectangle(cornerRadius: 4, style: .continuous).fill(index == 0 ? Palette.selected : Color.clear)
                        .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 2).fill(Palette.switchOff).frame(width: index == 0 ? 60 : 44 + CGFloat(index * 7), height: 4).padding(.leading, 6) }
                        .frame(height: 13)
                }
            }
            Spacer()
        }
        .frame(width: collapsed ? 16 : 100)
    }
}
