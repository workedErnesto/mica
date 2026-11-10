import SwiftUI

/// Window and start page entrance (MotionTokens.entrance). A part fades in and settles into place with the panel spring
/// `delay` seconds after the entrance begins. It only moves pixels: the field takes typing and clicks from the first
/// frame. With Reduce Motion it is a short fade without movement.
struct EntranceModifier: ViewModifier {
    let shown: Bool
    var delay: Double = 0
    var rise: CGFloat = MotionTokens.entrance.rise
    var dx: CGFloat = 0
    var scale: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduced
    func body(content: Content) -> some View {
        let moving = !shown && !reduced
        content
            .opacity(shown ? 1 : 0)
            .scaleEffect(moving ? scale : 1)
            .offset(x: moving ? dx : 0, y: moving ? rise : 0)
            .animation(reduced ? .easeOut(duration: MotionTokens.entrance.reducedFade) : Motion.panelSpring.delay(delay), value: shown)
    }
}

enum Entrance {
    /// Delay of the step-th part of a cascade.
    static func step(_ index: Int) -> Double { Double(index) * MotionTokens.entrance.stagger }
}

extension View {
    func entrance(_ shown: Bool, delay: Double = 0, rise: CGFloat = MotionTokens.entrance.rise, dx: CGFloat = 0, scale: CGFloat = 1) -> some View {
        modifier(EntranceModifier(shown: shown, delay: delay, rise: rise, dx: dx, scale: scale))
    }
}

/// Draws text glyph by glyph (MotionTokens.wordmark): each glyph rises, comes into focus and closes in from a wider
/// spacing, one after another from the first. `time` is seconds since the entrance began; the renderer is Animatable,
/// so a linear animation of `time` plays the whole wave on the render thread without relayout.
struct AssembleRenderer: TextRenderer, Animatable {
    var time: Double
    var animatableData: Double { get { time } set { time = newValue } }
    static let spring = Spring(response: MotionTokens.wordmark.letterDuration, dampingRatio: 0.78)

    static func step(glyphs: Int) -> Double {
        glyphs > 1 ? min(MotionTokens.wordmark.letterStagger, MotionTokens.wordmark.staggerCap / Double(glyphs - 1)) : 0
    }
    /// Time when the last glyph is at rest.
    static func total(glyphs: Int) -> Double { Double(max(glyphs - 1, 0)) * step(glyphs: glyphs) + spring.settlingDuration }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        let glyphs = layout.flatMap { line in line.flatMap { run in Array(run) } }
        let token = MotionTokens.wordmark
        let step = Self.step(glyphs: glyphs.count)
        let middle = Double(glyphs.count - 1) / 2
        let fade = token.letterDuration * 0.6
        for (index, glyph) in glyphs.enumerated() {
            let local = time - Double(index) * step
            guard local > 0 else { continue }
            let travel = Self.spring.value(target: 1.0, time: local)
            let rest = 1 - travel
            var copy = context
            copy.opacity = min(1, local / fade)
            copy.translateBy(x: (Double(index) - middle) * token.spread * rest, y: token.rise * rest)
            let blur = token.blur * max(0, 1 - local / fade)
            if blur > 0.05 { copy.addFilter(.blur(radius: blur)) }
            copy.draw(glyph)
        }
    }
}

/// The start page wordmark or greeting with its entrance. Shown at rest when the tab already played it.
struct AssemblingText: View {
    let text: Text
    /// Characters in the string, close enough to the glyph count to time the wave.
    let length: Int
    let shown: Bool
    var delay: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        if reduced {
            text.entrance(shown, delay: delay)
        } else {
            let total = AssembleRenderer.total(glyphs: length)
            text.textRenderer(AssembleRenderer(time: shown ? total : 0))
                .animation(.linear(duration: total).delay(delay), value: shown)
        }
    }
}
