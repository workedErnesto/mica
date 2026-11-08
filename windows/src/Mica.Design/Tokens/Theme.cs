using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media;
using Windows.UI;

namespace Mica.Design;

/// <summary>Light, dark and high-contrast variants of one palette colour as 0xAARRGGBB.</summary>
public readonly record struct Swatch(uint Light, uint Dark, uint ContrastLight, uint ContrastDark);

/// <summary>SwiftUI spring terms: response is the period of one undamped oscillation, damping the damping fraction.</summary>
public readonly record struct Spring(double Response, double Damping);

/// <summary>Resolves the palette for the current appearance. Every swatch has one shared brush; switching light, dark
/// or contrast rewrites the brush colours in place, so all controls follow without observers of their own, the way
/// dynamic NSColor works on macOS.</summary>
public static partial class Palette
{
    static readonly Dictionary<Swatch, SolidColorBrush> Brushes = [];
    public static bool Dark { get; private set; }
    public static bool Contrast { get; private set; }
    public static event Action? Changed;

    public static Color ColorOf(uint argb) => Color.FromArgb((byte)(argb >> 24), (byte)(argb >> 16), (byte)(argb >> 8), (byte)argb);

    public static Color Resolve(this Swatch s) => ColorOf(Dark ? (Contrast ? s.ContrastDark : s.Dark) : (Contrast ? s.ContrastLight : s.Light));

    public static SolidColorBrush Brush(this Swatch s)
    {
        if (!Brushes.TryGetValue(s, out var brush)) Brushes[s] = brush = new SolidColorBrush(s.Resolve());
        return brush;
    }

    public static void Apply(bool dark, bool contrast)
    {
        if (dark == Dark && contrast == Contrast && Brushes.Count > 0) return;
        Dark = dark; Contrast = contrast;
        foreach (var (swatch, brush) in Brushes) brush.Color = swatch.Resolve();
        Changed?.Invoke();
    }

    public static ElementTheme ElementTheme => Dark ? ElementTheme.Dark : ElementTheme.Light;
    public static readonly SolidColorBrush Clear = new(Colors.Transparent);
    public static SolidColorBrush Fixed(uint argb) => new(ColorOf(argb));

    public static Color Mix(Color a, Color b, double t) => Color.FromArgb(
        (byte)(a.A + (b.A - a.A) * t), (byte)(a.R + (b.R - a.R) * t), (byte)(a.G + (b.G - a.G) * t), (byte)(a.B + (b.B - a.B) * t));

    public static Color WithAlpha(Color c, double alpha) => Color.FromArgb((byte)Math.Round(Math.Clamp(alpha, 0, 1) * 255), c.R, c.G, c.B);
}

/// <summary>Appearance the static palette cannot know: the custom accent and the tinted shell (macOS Look).</summary>
public static class Look
{
    public static Color? Accent { get; private set; }
    public static readonly SolidColorBrush Primary = new();
    public static readonly SolidColorBrush PrimaryHover = new();
    public static readonly SolidColorBrush PrimaryPressed = new();
    public static readonly SolidColorBrush OnPrimary = new();
    public static readonly SolidColorBrush Shell = new();
    public static readonly SolidColorBrush Focus = new();
    public static readonly SolidColorBrush Progress = new();
    public static event Action? Changed;
    static string? accentHex; static double tint; static bool custom;

    public static void Apply(bool customTheme, string accent, double customTint)
    {
        custom = customTheme; accentHex = accent; tint = customTint;
        Refresh();
    }

    /// <summary>Recomputes after the palette switched light or dark.</summary>
    public static void Refresh()
    {
        Accent = custom && Core.HexColor.Parse(accentHex) is { } c ? Color.FromArgb(255, (byte)Math.Round(c.Red * 255), (byte)Math.Round(c.Green * 255), (byte)Math.Round(c.Blue * 255)) : null;
        if (Accent is { } a)
        {
            var luminance = Core.HexColor.Luminance(accentHex!) ?? 0;
            var onWhite = 1.05 / (luminance + 0.05); var onInk = (luminance + 0.05) / 0.0618;
            Primary.Color = a;
            PrimaryHover.Color = Palette.WithAlpha(a, 0.88);
            PrimaryPressed.Color = Palette.Mix(a, Colors.Black, 0.18);
            OnPrimary.Color = onWhite >= onInk ? Colors.White : Color.FromArgb(255, 28, 25, 23);
            Shell.Color = Palette.Mix(Palette.Shell.Resolve(), a, tint);
            Focus.Color = a; Progress.Color = Palette.WithAlpha(a, 0.6);
        }
        else
        {
            Primary.Color = Palette.Primary.Resolve();
            PrimaryHover.Color = Palette.WithAlpha(Palette.Primary.Resolve(), 0.86);
            PrimaryPressed.Color = Palette.PrimaryPressed.Resolve();
            OnPrimary.Color = Palette.OnPrimary.Resolve();
            Shell.Color = Palette.Shell.Resolve();
            Focus.Color = Palette.FocusRing.Resolve(); Progress.Color = Palette.WithAlpha(Palette.Ink.Resolve(), 0.6);
        }
        Changed?.Invoke();
    }
}

/// <summary>Type: Segoe UI Variable on Windows 11, Segoe UI on Windows 10; SF Pro on macOS. Never a serif.</summary>
public static class Fonts
{
    public static readonly FontFamily Text = new("Segoe UI Variable Text, Segoe UI");
    public static readonly FontFamily Display = new("Segoe UI Variable Display, Segoe UI");
    public static readonly FontFamily Icons = new("Segoe Fluent Icons, Segoe MDL2 Assets");
}
