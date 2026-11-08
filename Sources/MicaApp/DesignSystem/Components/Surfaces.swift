import AppKit
import SwiftUI
import MicaCore

struct Hairline: View { var body: some View { Rectangle().fill(Palette.hairline).frame(height: 1) } }

/// Raised floating surface: shell-adjacent panels, find bar, popovers drawn by mica.
struct RaisedSurface: ViewModifier {
    var radius: CGFloat = Radius.panel
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Palette.raised))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
            .shadow(color: Palette.shadowStrong, radius: 18, y: 8)
    }
}

struct EmptyState: View {
    let symbol: String
    let text: String
    var body: some View {
        VStack(spacing: Space.normal) {
            Image(systemName: symbol).font(.system(size: 16, weight: .medium)).foregroundStyle(Palette.text3)
                .frame(width: 40, height: 40).background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Palette.track))
            Text(text).font(.system(size: 12.5)).foregroundStyle(Palette.text3).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A quiet full-width row that navigates somewhere, used instead of a standalone button.
struct LinkRow: View {
    let title: String
    let symbol: String
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.small) {
                Text(title).font(.system(size: 12.5)).foregroundStyle(hover ? Palette.ink : Palette.text2)
                Spacer(minLength: 0)
                Image(systemName: symbol).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Palette.text3)
            }
            .padding(.horizontal, 10).frame(height: 32)
            .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(hover ? Palette.hover : Palette.track.opacity(0.6)))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.98))
        .onHover { hover = $0 }
        .animation(Motion.hover, value: hover)
    }
}
