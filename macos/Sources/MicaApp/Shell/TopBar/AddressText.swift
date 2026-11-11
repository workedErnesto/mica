import SwiftUI
import MicaCore

/// A page address drawn the way the address field shows it: the site's own domain in ink, the parts the user chose to
/// quiet in text2, a step softer than ink that still reads. Colour changes cross-fade; with Reduce Motion they switch at once.
struct AddressText: View {
    let address: String
    let style: AddressStyle
    var body: some View {
        AddressDisplay.parts(address, style: style)
            .reduce(Text(verbatim: "")) { $0 + Text(verbatim: $1.text).foregroundColor($1.dim ? Palette.text2 : Palette.ink) }
            .contentTransition(.interpolate)
            .animation(Motion.quick, value: style)
    }
}
