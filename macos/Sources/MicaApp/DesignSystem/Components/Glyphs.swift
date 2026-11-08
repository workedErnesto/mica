import AppKit
import SwiftUI

/// Site letter shown until a favicon is known (see SiteIcon). `plain` drops the track plate for tiles that draw their own.
struct Monogram: View {
    let host: String?
    var size: CGFloat = 16
    var plain = false
    var tint: Color = Palette.text2
    var body: some View {
        let letter = (Favicons.key(host) ?? "").first.map { String($0).uppercased() } ?? ""
        let scale: CGFloat = plain ? 0.68 : 0.58
        ZStack {
            if !plain { RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).fill(Palette.track) }
            if letter.isEmpty { Image(systemName: "globe").font(.system(size: size * (plain ? 0.66 : 0.6), weight: plain ? .medium : .regular)).foregroundStyle(tint) }
            else { Text(letter).font(.system(size: size * scale, weight: .semibold)).foregroundStyle(tint) }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Progress ring driven by WebKit progress events, not a perpetual animation.
struct ProgressRing: View {
    let progress: Double
    var size: CGFloat = 16
    @Environment(\.look) private var look
    var body: some View {
        ZStack {
            Circle().stroke(Palette.track, lineWidth: 2)
            Circle().trim(from: 0, to: max(0.06, progress)).stroke(look.accent ?? Palette.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round)).rotationEffect(.degrees(-90))
        }
        .frame(width: size - 2, height: size - 2)
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.2), value: progress)
        .accessibilityHidden(true)
    }
}

struct KeyHint: View {
    let keys: String
    var body: some View {
        Text(keys).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.text3)
            .padding(.horizontal, 6).frame(height: 18)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Palette.hairlineStrong, lineWidth: 1))
    }
}

/// Icon by name: an SF Symbol, or one of mica's own drawn glyphs for things SF Symbols has no sign for.
/// Use it wherever a control takes a symbol name, so custom glyphs work in buttons, menus and the toolbar palette.
struct Glyph: View {
    let name: String
    var size: CGFloat
    var weight: Font.Weight = .medium
    static let incognito = "mica.incognito"
    var body: some View {
        if name == Self.incognito { IncognitoMark(weight: weight).frame(width: size * 1.25, height: size * 1.25) }
        else { Image(systemName: name).font(.system(size: size, weight: weight)) }
    }
}

/// Incognito: a hat with a brim over round glasses. Drawn on a 20 pt grid, stroke matched to SF Symbols weights.
struct IncognitoMark: View {
    var weight: Font.Weight = .medium
    var body: some View {
        GeometryReader { geo in
            let unit = min(geo.size.width, geo.size.height) / 20
            let line = unit * (weight == .semibold || weight == .bold ? 1.8 : weight == .regular ? 1.35 : 1.55)
            ZStack {
                IncognitoHat().fill(style: FillStyle())
                IncognitoGlasses().stroke(style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round))
            }
            .frame(width: unit * 20, height: unit * 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityHidden(true)
    }
}

private struct IncognitoHat: Shape {
    func path(in rect: CGRect) -> Path {
        let u = min(rect.width, rect.height) / 20
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * u, y: rect.minY + y * u) }
        var path = Path()
        // Crown: narrow top with a soft dip in the middle, widening down to the band.
        path.move(to: p(5.2, 8.6))
        path.addLine(to: p(6.6, 3.6))
        path.addQuadCurve(to: p(8.1, 2.7), control: p(7.0, 2.4))
        path.addQuadCurve(to: p(11.9, 2.7), control: p(10.0, 3.6))
        path.addQuadCurve(to: p(13.4, 3.6), control: p(13.0, 2.4))
        path.addLine(to: p(14.8, 8.6))
        path.closeSubpath()
        // Brim.
        path.addRoundedRect(in: CGRect(origin: p(1.6, 8.9), size: CGSize(width: 16.8 * u, height: 1.9 * u)), cornerSize: CGSize(width: 0.95 * u, height: 0.95 * u), style: .continuous)
        return path
    }
}

private struct IncognitoGlasses: Shape {
    func path(in rect: CGRect) -> Path {
        let u = min(rect.width, rect.height) / 20
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * u, y: rect.minY + y * u) }
        var path = Path()
        path.addEllipse(in: CGRect(origin: p(2.6, 12.6), size: CGSize(width: 5.4 * u, height: 4.8 * u)))
        path.addEllipse(in: CGRect(origin: p(12.0, 12.6), size: CGSize(width: 5.4 * u, height: 4.8 * u)))
        path.move(to: p(8.0, 14.6))
        path.addQuadCurve(to: p(12.0, 14.6), control: p(10.0, 13.4))
        return path
    }
}
