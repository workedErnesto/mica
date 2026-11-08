using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using Windows.UI.Text;

namespace Mica.Design;

/// <summary>Small builders so views read like their SwiftUI counterparts: text, glyphs, stacks, rounded fills.</summary>
public static class Ui
{
    public static FontWeight Weight(int value) => new() { Weight = (ushort)value };
    public static readonly FontWeight Regular = Weight(400), Medium = Weight(500), Semibold = Weight(600);

    public static TextBlock Text(string text, double size = 13, Brush? brush = null, FontWeight? weight = null, bool wrap = false, bool trim = true)
    {
        var block = new TextBlock
        {
            Text = text, FontSize = size, FontFamily = size >= 20 ? Fonts.Display : Fonts.Text,
            Foreground = brush ?? Palette.Ink.Brush(), FontWeight = weight ?? Regular,
            TextWrapping = wrap ? TextWrapping.WrapWholeWords : TextWrapping.NoWrap,
            TextTrimming = trim && !wrap ? TextTrimming.CharacterEllipsis : TextTrimming.None,
            IsTextScaleFactorEnabled = true, VerticalAlignment = VerticalAlignment.Center,
        };
        return block;
    }

    public static StackPanel H(double spacing = 0, params UIElement[] children)
    {
        var panel = new StackPanel { Orientation = Orientation.Horizontal, Spacing = spacing };
        foreach (var child in children) panel.Children.Add(child);
        return panel;
    }

    public static StackPanel V(double spacing = 0, params UIElement[] children)
    {
        var panel = new StackPanel { Orientation = Orientation.Vertical, Spacing = spacing };
        foreach (var child in children) panel.Children.Add(child);
        return panel;
    }

    public static Border Rounded(double radius, Brush? fill = null, Brush? stroke = null, double strokeWidth = 1, UIElement? child = null) => new()
    {
        CornerRadius = new CornerRadius(radius), Background = fill ?? Palette.Clear,
        BorderBrush = stroke, BorderThickness = stroke is null ? new Thickness(0) : new Thickness(strokeWidth), Child = child,
        BackgroundTransition = new BrushTransition { Duration = Motion.Hover },
    };

    public static Rectangle Hairline(bool vertical = false) => vertical
        ? new Rectangle { Width = 1, Fill = Palette.Hairline.Brush(), VerticalAlignment = VerticalAlignment.Stretch }
        : new Rectangle { Height = 1, Fill = Palette.Hairline.Brush(), HorizontalAlignment = HorizontalAlignment.Stretch };

    /// <summary>Raised floating surface: panels, find bar, popovers drawn by mica.</summary>
    public static Border Raised(UIElement child, double radius = Radius.Panel)
    {
        var border = Rounded(radius, Palette.Raised.Brush(), Palette.Hairline.Brush(), 1, child);
        border.Shadow = Shadows.Strong;
        border.Translation = new System.Numerics.Vector3(0, 0, 32);
        return border;
    }

    public static Grid Grid(params UIElement[] children)
    {
        var grid = new Grid();
        foreach (var c in children) grid.Children.Add(c);
        return grid;
    }

    public static T Margin<T>(this T element, double left, double top, double right, double bottom) where T : FrameworkElement { element.Margin = new Thickness(left, top, right, bottom); return element; }
    public static T Margin<T>(this T element, double all) where T : FrameworkElement { element.Margin = new Thickness(all); return element; }
    public static T Align<T>(this T element, HorizontalAlignment h, VerticalAlignment v = VerticalAlignment.Stretch) where T : FrameworkElement { element.HorizontalAlignment = h; element.VerticalAlignment = v; return element; }
    public static T Size<T>(this T element, double width = double.NaN, double height = double.NaN) where T : FrameworkElement { element.Width = width; element.Height = height; return element; }
    public static T Tip<T>(this T element, string text) where T : FrameworkElement
    {
        ToolTipService.SetToolTip(element, text);
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(element, text);
        return element;
    }

    public static void Column(this Grid grid, UIElement child, int column) { Microsoft.UI.Xaml.Controls.Grid.SetColumn((FrameworkElement)child, column); if (!grid.Children.Contains(child)) grid.Children.Add(child); }
    public static void Row(this Grid grid, UIElement child, int row) { Microsoft.UI.Xaml.Controls.Grid.SetRow((FrameworkElement)child, row); if (!grid.Children.Contains(child)) grid.Children.Add(child); }
    public static ColumnDefinition Star(double value = 1) => new() { Width = new GridLength(value, GridUnitType.Star) };
    public static ColumnDefinition Auto() => new() { Width = GridLength.Auto };
    public static ColumnDefinition Fixed(double value) => new() { Width = new GridLength(value) };
    public static RowDefinition RowStar(double value = 1) => new() { Height = new GridLength(value, GridUnitType.Star) };
    public static RowDefinition RowAuto() => new() { Height = GridLength.Auto };
    public static RowDefinition RowFixed(double value) => new() { Height = new GridLength(value) };

    public static ScrollViewer Scroll(UIElement content, bool horizontal = false) => new()
    {
        Content = content,
        HorizontalScrollBarVisibility = horizontal ? ScrollBarVisibility.Auto : ScrollBarVisibility.Disabled,
        HorizontalScrollMode = horizontal ? ScrollMode.Enabled : ScrollMode.Disabled,
        VerticalScrollBarVisibility = horizontal ? ScrollBarVisibility.Disabled : ScrollBarVisibility.Auto,
        VerticalScrollMode = horizontal ? ScrollMode.Disabled : ScrollMode.Enabled,
    };
}

/// <summary>Shared shadow objects; ThemeShadow draws on elements raised with a Z translation.</summary>
public static class Shadows
{
    public static readonly ThemeShadow Soft = new();
    public static readonly ThemeShadow Strong = new();
}

/// <summary>Hover and press tracking with the hand-off to visual state, like SwiftUI onHover and isPressed.</summary>
public sealed class Interaction
{
    public bool Hover { get; private set; }
    public bool Pressed { get; private set; }
    public bool Enabled { get; set; } = true;
    readonly Action update;
    public event Action? Invoked;

    public Interaction(UIElement target, Action update, double pressScale = 0, UIElement? scaled = null)
    {
        this.update = update;
        var visual = scaled ?? target;
        target.PointerEntered += (_, _) => { Hover = Enabled; update(); };
        target.PointerExited += (_, _) => { Hover = false; if (Pressed) Release(false); update(); };
        target.PointerCanceled += (_, _) => { Hover = false; Release(false); };
        target.PointerCaptureLost += (_, _) => Release(false);
        target.PointerPressed += (s, e) =>
        {
            if (!Enabled || !e.GetCurrentPoint((UIElement)s).Properties.IsLeftButtonPressed) return;
            Pressed = true; ((UIElement)s).CapturePointer(e.Pointer);
            if (pressScale > 0) Motion.Scale(visual, pressScale, Motion.Press);
            update(); e.Handled = true;
        };
        target.PointerReleased += (s, e) =>
        {
            if (!Pressed) return;
            ((UIElement)s).ReleasePointerCapture(e.Pointer);
            Release(Hover);
            e.Handled = true;
        };
        target.KeyDown += (_, e) =>
        {
            if (!Enabled || (e.Key != Windows.System.VirtualKey.Enter && e.Key != Windows.System.VirtualKey.Space)) return;
            Invoked?.Invoke(); e.Handled = true;
        };
        void Release(bool fire)
        {
            if (!Pressed) return;
            Pressed = false;
            if (pressScale > 0) Motion.Scale(visual, 1, Motion.Press);
            update();
            if (fire && Enabled) Invoked?.Invoke();
        }
    }
}
