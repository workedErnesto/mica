import AppKit
import SwiftUI

enum Motion {
    static var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    /// Color and opacity feedback. Not movement, so it stays on with Reduce Motion.
    static let hover = Animation.easeOut(duration: 0.12)
    static let pressSpring = Animation.spring(response: 0.22, dampingFraction: 0.72)
    static let snappySpring = Animation.spring(response: 0.3, dampingFraction: 0.86)
    static let panelSpring = Animation.spring(response: 0.36, dampingFraction: 0.9)
    /// Spatial animations; nil means an immediate change when the system asks for less motion.
    static var quick: Animation? { reduced ? nil : snappySpring }
    static var panel: Animation? { reduced ? nil : panelSpring }
    static var press: Animation? { reduced ? nil : pressSpring }
    static func slide(_ edge: Edge) -> AnyTransition { reduced ? .opacity : .move(edge: edge).combined(with: .opacity) }
    static var pop: AnyTransition { reduced ? .opacity : .scale(scale: 0.96).combined(with: .opacity) }
}

func withMotion(_ animation: Animation?, _ change: () -> Void) { if let animation { withAnimation(animation, change) } else { change() } }
