import AppKit
import SwiftUI
import AVFoundation
import MicaCore

struct NavItem: View {
    let title: String
    let symbol: String
    let selected: Bool
    let namespace: Namespace.ID
    var compact = false
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 12, weight: .medium)).frame(width: 18)
                if !compact {
                    Text(title).font(.system(size: 13, weight: selected ? .medium : .regular)).lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
            .foregroundStyle(selected || hover ? Palette.ink : Palette.text2)
            .padding(.horizontal, 10).frame(height: 32)
            .background {
                if selected { RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(Palette.selected).shadow(color: Palette.shadow, radius: 2, y: 1).matchedGeometryEffect(id: "nav", in: namespace) }
                else if hover { RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(Palette.hover) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.98))
        .onHover { hover = $0 }.animation(Motion.hover, value: hover)
        .help(title).accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
