import AppKit
import SwiftUI

enum Motion {
    static var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    /// Color and opacity feedback. Not movement, so it stays on with Reduce Motion.
    static let hover = Animation.easeOut(duration: MotionTokens.hoverDuration)
    static let pressSpring = Animation.spring(response: MotionTokens.press.response, dampingFraction: MotionTokens.press.damping)
    static let snappySpring = Animation.spring(response: MotionTokens.snappy.response, dampingFraction: MotionTokens.snappy.damping)
    static let panelSpring = Animation.spring(response: MotionTokens.panel.response, dampingFraction: MotionTokens.panel.damping)
    /// Spatial animations; nil means an immediate change when the system asks for less motion.
    static var quick: Animation? { reduced ? nil : snappySpring }
    static var panel: Animation? { reduced ? nil : panelSpring }
    static var press: Animation? { reduced ? nil : pressSpring }
    static func slide(_ edge: Edge) -> AnyTransition { reduced ? .opacity : .move(edge: edge).combined(with: .opacity) }
    static var pop: AnyTransition { reduced ? .opacity : .scale(scale: MotionTokens.popScale).combined(with: .opacity) }
}

func withMotion(_ animation: Animation?, _ change: () -> Void) { if let animation { withAnimation(animation, change) } else { change() } }
