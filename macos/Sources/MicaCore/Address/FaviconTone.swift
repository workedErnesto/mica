import Foundation

/// Decides when a site icon is redrawn in the shell's ink. Many sites (GitHub, X, Apple, Vercel) ship a one-colour
/// black or white glyph on transparency and pick the variant by the page's own colour scheme, which need not match
/// mica's. Such a glyph only carries its shape, so it may take the ink colour when its own colour would vanish on the
/// background. Coloured, multi-tone and opaque icons are never touched: their colours belong to the brand.
/// Shared vectors `faviconTone` keep macOS and Windows equal.
public enum FaviconTone {
    /// Luminance (WCAG) of a neutral one-colour glyph, or nil for any other icon. `rgba` holds 8-bit RGBA pixels with
    /// straight (not premultiplied) alpha, row by row.
    public static func glyph(rgba: [UInt8]) -> Double? {
        let count = rgba.count / 4
        guard count > 0 else { return nil }
        var clear = 0
        var solid: [Double] = []
        var colourful = 0
        for index in 0..<count {
            let r = rgba[index * 4], g = rgba[index * 4 + 1], b = rgba[index * 4 + 2], a = rgba[index * 4 + 3]
            if a < 26 { clear += 1; continue }
            // Half-transparent edge pixels only smooth the outline; the glyph's colour is read from the solid ones.
            guard a >= 128 else { continue }
            if Int(max(r, g, b)) - Int(min(r, g, b)) > 40 { colourful += 1 }
            solid.append(luminance(r, g, b))
        }
        // A glyph shows the background through: at least 15 % clear. A filled square brings its own backdrop.
        guard clear * 100 >= count * 15, solid.count * 50 >= count, !solid.isEmpty else { return nil }
        let allowed = solid.count / 20
        guard colourful <= allowed else { return nil }
        let middle = solid.sorted()[solid.count / 2]
        let off = solid.filter { contrast($0, middle) > 1.5 }.count
        return off <= allowed ? middle : nil
    }

    /// True when a glyph of this luminance falls under the 3:1 contrast WCAG asks of non-text elements on the
    /// background and should be drawn in the shell's ink instead.
    public static func needsInk(glyph: Double, background: Double) -> Bool { contrast(glyph, background) < 3 }

    public static func contrast(_ a: Double, _ b: Double) -> Double { (max(a, b) + 0.05) / (min(a, b) + 0.05) }

    static func luminance(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> Double {
        func linear(_ v: UInt8) -> Double { let c = Double(v) / 255; return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }
}
