import AppKit
import SwiftUI

struct Segmented<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: String)]
    var symbols: [String] = []
    var compact = false
    /// Least width of the whole control. Segments share it equally and grow past it rather than cut a word.
    var width: CGFloat = 0
    var fillsWidth = false
    var label = ""
    @Namespace private var space
    @State private var hovered: Value?
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        EqualSegments(spacing: 2, minWidth: max(0, width - 4), fillsWidth: fillsWidth) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                let chosen = option.value == selection
                Button { withMotion(reduced ? nil : Motion.snappySpring) { selection = option.value } } label: {
                    HStack(spacing: 6) {
                        if index < symbols.count { Image(systemName: symbols[index]).font(.system(size: compact ? 10 : 11, weight: .medium)) }
                        Text(option.title).lineLimit(1).fixedSize()
                    }
                    .font(.system(size: compact ? 11.5 : 12.5, weight: chosen ? .medium : .regular))
                    .foregroundStyle(chosen ? Palette.ink : hovered == option.value ? Palette.ink : Palette.text2)
                    .padding(.horizontal, compact ? 8 : 10)
                    .frame(maxWidth: .infinity)
                    .frame(height: compact ? 22 : 26)
                    .background {
                        if chosen {
                            RoundedRectangle(cornerRadius: Radius.thumb, style: .continuous).fill(Palette.thumb)
                                .shadow(color: Palette.shadow, radius: 2, y: 1)
                                .matchedGeometryEffect(id: "thumb", in: space)
                        } else if hovered == option.value {
                            RoundedRectangle(cornerRadius: Radius.thumb, style: .continuous).fill(Palette.hover)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle(scale: 0.96))
                .onHover { inside in if inside { hovered = option.value } else if hovered == option.value { hovered = nil } }
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: Radius.track, style: .continuous).fill(Palette.track))
        .opacity(enabled ? 1 : 0.45)
        .animation(reduced ? nil : Motion.snappySpring, value: selection)
        .animation(Motion.hover, value: hovered)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

/// Equal segments as wide as the longest one needs, or wider to fill `minWidth`.
struct EqualSegments: Layout {
    var spacing: CGFloat
    var minWidth: CGFloat
    var fillsWidth = false
    private func widest(_ subviews: Subviews) -> CGFloat { subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0 }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let gaps = spacing * CGFloat(subviews.count - 1)
        let intrinsic = widest(subviews) * CGFloat(subviews.count) + gaps
        let proposed = fillsWidth && proposal.width?.isFinite == true ? proposal.width! : 0
        let width = max(minWidth, intrinsic, proposed)
        let height = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        return CGSize(width: width, height: height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let each = (bounds.width - spacing * CGFloat(subviews.count - 1)) / CGFloat(subviews.count)
        var x = bounds.minX
        for subview in subviews {
            subview.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(width: each, height: bounds.height))
            x += each + spacing
        }
    }
}
