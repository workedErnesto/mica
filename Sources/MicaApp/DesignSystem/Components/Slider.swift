import AppKit
import SwiftUI

struct MSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let label: String
    @State private var dragging = false
    @State private var hover = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.look) private var look
    private let knob: CGFloat = 16
    var body: some View {
        GeometryReader { geo in
            let span = range.upperBound - range.lowerBound
            let fraction = CGFloat((min(range.upperBound, max(range.lowerBound, value)) - range.lowerBound) / span)
            let travel = max(1, geo.size.width - knob)
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.track).frame(height: 4)
                Capsule().fill(look.primary).frame(width: knob / 2 + fraction * travel, height: 4)
                Circle().fill(Palette.thumbSolid)
                    .overlay(Circle().strokeBorder(Palette.hairlineStrong, lineWidth: 0.5))
                    .shadow(color: Palette.shadowStrong, radius: 2, y: 1)
                    .frame(width: knob, height: knob)
                    .scaleEffect(reduced ? 1 : dragging ? 1.18 : hover ? 1.08 : 1)
                    .offset(x: fraction * travel)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { gesture in
                guard enabled else { return }
                dragging = true
                let position = min(1, max(0, (gesture.location.x - knob / 2) / travel))
                value = range.lowerBound + Double(position) * span
            }.onEnded { _ in dragging = false })
        }
        .frame(height: 22)
        .onHover { hover = $0 && enabled }
        .opacity(enabled ? 1 : 0.45)
        .animation(reduced ? nil : Motion.pressSpring, value: dragging)
        .animation(Motion.hover, value: hover)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(String(Int(((value - range.lowerBound) / (range.upperBound - range.lowerBound) * 100).rounded())) + "%")
        .accessibilityAdjustableAction { direction in
            let step = (range.upperBound - range.lowerBound) / 20
            value = min(range.upperBound, max(range.lowerBound, value + (direction == .increment ? step : -step)))
        }
    }
}
