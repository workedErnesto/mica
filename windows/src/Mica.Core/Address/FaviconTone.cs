namespace Mica.Core;

/// <summary>Decides when a site icon is redrawn in the shell's ink (macOS FaviconTone). Many sites (GitHub, X, Apple,
/// Vercel) ship a one-colour black or white glyph on transparency and pick the variant by the page's own colour scheme,
/// which need not match mica's. Such a glyph only carries its shape, so it may take the ink colour when its own colour
/// would vanish on the background. Coloured, multi-tone and opaque icons are never touched: their colours belong to the
/// brand. Shared vectors <c>faviconTone</c> keep both platforms equal.</summary>
public static class FaviconTone
{
    /// <summary>Luminance (WCAG) of a neutral one-colour glyph, or null for any other icon. <c>rgba</c> holds 8-bit RGBA
    /// pixels with straight (not premultiplied) alpha, row by row.</summary>
    public static double? Glyph(ReadOnlySpan<byte> rgba)
    {
        var count = rgba.Length / 4;
        if (count == 0) return null;
        int clear = 0, colourful = 0;
        var solid = new List<double>();
        for (var i = 0; i < count; i++)
        {
            byte r = rgba[i * 4], g = rgba[i * 4 + 1], b = rgba[i * 4 + 2], a = rgba[i * 4 + 3];
            if (a < 26) { clear++; continue; }
            // Half-transparent edge pixels only smooth the outline; the glyph's colour is read from the solid ones.
            if (a < 128) continue;
            if (Math.Max(r, Math.Max(g, b)) - Math.Min(r, Math.Min(g, b)) > 40) colourful++;
            solid.Add(Luminance(r, g, b));
        }
        // A glyph shows the background through: at least 15 % clear. A filled square brings its own backdrop.
        if (clear * 100 < count * 15 || solid.Count * 50 < count || solid.Count == 0) return null;
        var allowed = solid.Count / 20;
        if (colourful > allowed) return null;
        solid.Sort();
        var middle = solid[solid.Count / 2];
        var off = solid.Count(l => Contrast(l, middle) > 1.5);
        return off <= allowed ? middle : null;
    }

    /// <summary>True when a glyph of this luminance falls under the 3:1 contrast WCAG asks of non-text elements on the
    /// background and should be drawn in the shell's ink instead.</summary>
    public static bool NeedsInk(double glyph, double background) => Contrast(glyph, background) < 3;

    public static double Contrast(double a, double b) => (Math.Max(a, b) + 0.05) / (Math.Min(a, b) + 0.05);

    public static double Luminance(byte r, byte g, byte b)
    {
        static double Linear(byte v) { var c = v / 255.0; return c <= 0.03928 ? c / 12.92 : Math.Pow((c + 0.055) / 1.055, 2.4); }
        return 0.2126 * Linear(r) + 0.7152 * Linear(g) + 0.0722 * Linear(b);
    }
}
