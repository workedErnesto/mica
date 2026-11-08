import SwiftUI

/// Window-level card over a dimmed shell and page: settings, onboarding and clearing data share this geometry.
/// A click on the scrim or Esc calls `onDismiss` when the card is dismissible.
struct ModalCard<Content: View>: View {
    var width: CGFloat
    var height: CGFloat?
    var dismissible = true
    var onDismiss: () -> Void = {}
    @ViewBuilder var content: Content
    @State private var shown = false
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Palette.scrim.ignoresSafeArea().contentShape(Rectangle()).onTapGesture { if dismissible { onDismiss() } }
                content
                    .frame(width: min(width, geo.size.width - 48))
                    .frame(height: height.map { min($0, geo.size.height - 48) })
                    .background(Palette.canvas)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.modal, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.modal, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
                    .shadow(color: Palette.shadowStrong, radius: 30, y: 14)
                    .scaleEffect(shown || Motion.reduced ? 1 : 0.97)
                    .opacity(shown ? 1 : 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { withMotion(Motion.quick ?? Motion.hover) { shown = true } }
        .onExitCommand { if dismissible { onDismiss() } }
    }
}
