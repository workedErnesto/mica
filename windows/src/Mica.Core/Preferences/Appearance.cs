namespace Mica.Core;

/// <summary>Where the tabs live. Top puts the address bar above the tab strip; TabsAbove puts the strip in the title bar
/// band beside the caption buttons and the address bar under it.</summary>
public enum TabLayout { Left, Right, Top, TabsAbove }

public static class TabLayouts
{
    /// <summary>Windows narrower than this show the tabs across the top without changing the saved layout.</summary>
    public const double NarrowWidth = 760;
    /// <summary>Tabs run across the window and there is no sidebar.</summary>
    public static bool IsHorizontal(this TabLayout layout) => layout is TabLayout.Top or TabLayout.TabsAbove;
    /// <summary>Side of the sidebar, null when the tabs run across the top.</summary>
    public static TabLayout? SidebarEdge(this TabLayout layout) => layout.IsHorizontal() ? null : layout;
    /// <summary>Layout of a window this wide: a narrow window keeps a top layout as chosen and moves the sidebar ones to Top.</summary>
    public static TabLayout Fitting(this TabLayout layout, double width) => width < NarrowWidth && !layout.IsHorizontal() ? TabLayout.Top : layout;
    public static string RawValue(this TabLayout layout) => layout switch { TabLayout.Right => "right", TabLayout.Top => "top", TabLayout.TabsAbove => "tabsAbove", _ => "left" };
    public static TabLayout? Parse(string? raw) => raw switch { "left" => TabLayout.Left, "right" => TabLayout.Right, "top" => TabLayout.Top, "tabsAbove" => TabLayout.TabsAbove, _ => null };
}

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
