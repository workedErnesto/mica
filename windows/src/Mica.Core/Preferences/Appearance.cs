namespace Mica.Core;

public enum TabLayout { Left, Right, Top }

/// <summary>Custom uses CustomBase for light or dark and tints the shell with Accent.</summary>
public enum Theme { System, Light, Dark, Custom }

/// <summary>Six-digit hex colours for the custom accent.</summary>
public static class HexColor
{
    public static (double Red, double Green, double Blue)? Parse(string? text)
    {
        if (text is null) return null;
        var hex = text.Trim();
        if (hex.StartsWith('#')) hex = hex[1..];
        if (hex.Length != 6 || !uint.TryParse(hex, System.Globalization.NumberStyles.HexNumber, null, out var value)) return null;
        return (((value >> 16) & 0xff) / 255.0, ((value >> 8) & 0xff) / 255.0, (value & 0xff) / 255.0);
    }

    public static string ToHex(double red, double green, double blue)
    {
        static int Byte(double v) => (int)Math.Round(Math.Clamp(v, 0, 1) * 255, MidpointRounding.AwayFromZero);
        return $"#{Byte(red):X2}{Byte(green):X2}{Byte(blue):X2}";
    }

    /// <summary>Relative luminance (WCAG); decides whether text on the accent is light or dark.</summary>
    public static double? Luminance(string text)
    {
        if (Parse(text) is not { } c) return null;
        static double Linear(double v) => v <= 0.03928 ? v / 12.92 : Math.Pow((v + 0.055) / 1.055, 2.4);
        return 0.2126 * Linear(c.Red) + 0.7152 * Linear(c.Green) + 0.0722 * Linear(c.Blue);
    }
}
