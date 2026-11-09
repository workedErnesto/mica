using System.Numerics;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;

namespace Mica.Design;

/// <summary>One row of a mica menu, or a divider.</summary>
public sealed record MenuEntry(string Title, Action Action, string? Symbol = null, bool Enabled = true, bool Checked = false, bool Destructive = false, bool Divider = false, string? Shortcut = null)
{
    public static readonly MenuEntry Separator = new("", () => { }, Divider: true);
    public static MenuEntry Item(string title, Action action, string? symbol = null, bool enabled = true, bool @checked = false, bool destructive = false, string? shortcut = null) =>
        new(title, action, symbol, enabled, @checked, destructive, false, shortcut);
}

public static class MenuEntries
{
    /// <summary>No leading, trailing or doubled dividers, whatever the conditional parts produced.</summary>
    public static List<MenuEntry> Tidy(this IEnumerable<MenuEntry> entries)
    {
        var result = new List<MenuEntry>();
        foreach (var e in entries) if (!(e.Divider && (result.Count == 0 || result[^1].Divider))) result.Add(e);
        while (result.Count > 0 && result[^1].Divider) result.RemoveAt(result.Count - 1);
        return result;
    }
}

/// <summary>mica draws its own shell menus (macOS MicaMenu): a windowed popup that may extend past the window and
/// over the page, opened at the pointer or under a control, closed by a click elsewhere, Esc or a choice.
/// Web page context menus stay WebView2's own.</summary>
public static partial class MicaMenu
{
    static Popup? open;

    public static bool IsOpen => open?.IsOpen == true;

    public static void Close() { if (open is { } popup) { open = null; popup.IsOpen = false; } }

    /// <summary>Opens at a point in the coordinates of <paramref name="relativeTo"/>.</summary>
    public static void ShowAt(IEnumerable<MenuEntry> source, UIElement relativeTo, Windows.Foundation.Point point)
    {
        var entries = source.Tidy();
        if (entries.Count == 0 || relativeTo.XamlRoot is null) return;
        Close();
        var transform = relativeTo.TransformToVisual(relativeTo.XamlRoot.Content);
        var at = transform.TransformPoint(point);
        var panel = Build(entries, out var rows);
        var popup = new Popup { Child = panel, XamlRoot = relativeTo.XamlRoot, IsLightDismissEnabled = true, ShouldConstrainToRootBounds = false, HorizontalOffset = at.X, VerticalOffset = at.Y };
        popup.Closed += (_, _) => { if (open == popup) open = null; };
        open = popup;
        popup.IsOpen = true;
        panel.Loaded += (_, _) =>
        {
            // Keep the menu on the window when it would run off the right or bottom edge.
            var root = relativeTo.XamlRoot.Size;
            if (at.X + panel.ActualWidth > root.Width - 4) popup.HorizontalOffset = Math.Max(4, at.X - panel.ActualWidth);
            if (at.Y + panel.ActualHeight > root.Height - 4) popup.VerticalOffset = Math.Max(4, at.Y - panel.ActualHeight);
            Motion.Appear(panel);
            rows.FirstOrDefault()?.Focus(FocusState.Programmatic);
        };
    }

    /// <summary>Opens under a control, or above it when there is no room below.</summary>
    public static void ShowBelow(IEnumerable<MenuEntry> entries, FrameworkElement anchor) =>
        ShowAt(entries, anchor, new Windows.Foundation.Point(0, anchor.ActualHeight + 4));

    static Border Build(List<MenuEntry> entries, out List<Control> rows)
    {
        var checks = entries.Any(e => e.Checked);
        var symbols = entries.Any(e => e.Symbol is not null);
        var stack = new StackPanel { Padding = new Thickness(5), MinWidth = 196 };
        rows = [];
        foreach (var entry in entries)
        {
            if (entry.Divider) { stack.Children.Add(Ui.Hairline().Margin(8, 4, 8, 4)); continue; }
            var row = new MenuRow(entry, checks, symbols, () => { Close(); entry.Action(); });
            rows.Add(row);
            stack.Children.Add(row);
        }
        var focusable = rows;
        stack.KeyDown += (_, e) =>
        {
            var index = focusable.FindIndex(r => r.FocusState != FocusState.Unfocused);
            if (e.Key == Windows.System.VirtualKey.Down) { Step(1); e.Handled = true; }
            else if (e.Key == Windows.System.VirtualKey.Up) { Step(-1); e.Handled = true; }
            else if (e.Key == Windows.System.VirtualKey.Escape) { Close(); e.Handled = true; }
            void Step(int step)
            {
                var enabled = focusable.Where(r => r.IsEnabled).ToList();
                if (enabled.Count == 0) return;
                var position = index < 0 ? (step > 0 ? -1 : 0) : enabled.IndexOf(focusable[index]);
                enabled[(position + step + enabled.Count) % enabled.Count].Focus(FocusState.Keyboard);
            }
        };
        // A low elevation keeps the system shadow soft and close, as the macOS menu's MenuShadow does.
        var border = Ui.Rounded(12, Palette.Raised.Brush(), Palette.Hairline.Brush(), 1, stack);
        border.Shadow = Shadows.Soft;
        border.Translation = new Vector3(0, 0, 12);
        border.Margin = new Thickness(0);
        AutomationProperties.SetAccessibilityView(border, Microsoft.UI.Xaml.Automation.Peers.AccessibilityView.Content);
        return border;
    }

    /// <summary>mica's context menu: a right click, the menu key or Shift+F10 on this element opens it.</summary>
    public static void ContextMenu(this UIElement element, Func<IEnumerable<MenuEntry>> entries, Func<bool>? suppressed = null)
    {
        element.ContextRequested += (s, e) =>
        {
            if (suppressed?.Invoke() == true) return;
            var list = entries().Tidy();
            if (list.Count == 0) return;
            var point = e.TryGetPosition(element, out var p) ? p : new Windows.Foundation.Point(12, 12);
            ShowAt(list, element, point);
            e.Handled = true;
        };
    }

    sealed partial class MenuRow : ContentControl
    {
        public MenuRow(MenuEntry entry, bool checks, bool symbols, Action choose)
        {
            IsEnabled = entry.Enabled; IsTabStop = true; UseSystemFocusVisuals = false;
            HorizontalContentAlignment = HorizontalAlignment.Stretch; HorizontalAlignment = HorizontalAlignment.Stretch;
            var plate = Ui.Rounded(7);
            var brush = !entry.Enabled ? new SolidColorBrush(Palette.WithAlpha(Palette.Text3.Resolve(), 0.7)) : entry.Destructive ? Palette.Danger.Brush() : Palette.Ink.Brush();
            var line = new Grid { Height = 26, Padding = new Thickness(8, 0, 8, 0), ColumnSpacing = 8 };
            line.ColumnDefinitions.Add(Ui.Auto()); line.ColumnDefinitions.Add(Ui.Auto()); line.ColumnDefinitions.Add(Ui.Star()); line.ColumnDefinitions.Add(Ui.Auto());
            if (checks) line.Column(new Glyph("checkmark", 10, brush) { Width = 12, Opacity = entry.Checked ? 1 : 0, VerticalAlignment = VerticalAlignment.Center }, 0);
            if (symbols) line.Column(entry.Symbol is null ? new Grid { Width = 16 } : new Glyph(entry.Symbol, 12, brush) { Width = 16, VerticalAlignment = VerticalAlignment.Center }, 1);
            line.Column(Ui.Text(entry.Title, 13, brush), 2);
            if (entry.Shortcut is not null) line.Column(Ui.Text(entry.Shortcut, 12, Palette.Text3.Brush()).Margin(16, 0, 0, 0), 3);
            var root = new Grid { Background = Palette.Clear };
            root.Children.Add(plate); root.Children.Add(line);
            Content = root;
            void Highlight(bool on) => plate.Background = on && entry.Enabled ? Palette.Pressed.Brush() : Palette.Clear;
            PointerEntered += (_, _) => Highlight(true);
            PointerExited += (_, _) => Highlight(FocusState == FocusState.Keyboard);
            GotFocus += (_, _) => Highlight(true);
            LostFocus += (_, _) => Highlight(false);
            Tapped += (_, e) => { if (entry.Enabled) { e.Handled = true; choose(); } };
            KeyDown += (_, e) => { if (entry.Enabled && e.Key is Windows.System.VirtualKey.Enter or Windows.System.VirtualKey.Space) { e.Handled = true; choose(); } };
            AutomationProperties.SetName(this, entry.Title);
        }
    }
}

/// <summary>Icon button that opens a mica menu under itself (macOS MenuButton).</summary>
public sealed partial class MenuButton : Grid
{
    public MenuButton(string label, Func<IEnumerable<MenuEntry>> entries, string symbol = "ellipsis", double size = 24)
    {
        var button = new IconButton(symbol, label, size);
        button.Click += () => MicaMenu.ShowBelow(entries(), button);
        Children.Add(button);
    }
}

/// <summary>Window-level card over a dimmed shell and page: settings, onboarding and clearing data (macOS ModalCard).
/// A click on the scrim or Esc dismisses it when allowed.</summary>
public sealed partial class ModalCard : Grid
{
    readonly Border card;
    public ModalCard(UIElement content, double width, double? height = null, bool dismissible = true, Action? dismiss = null)
    {
        var scrim = new Grid { Background = Palette.Scrim.Brush() };
        scrim.Tapped += (_, _) => { if (dismissible) dismiss?.Invoke(); };
        card = Ui.Rounded(Radius.Modal, Palette.Canvas.Brush(), Palette.Hairline.Brush(), 1, content);
        card.MaxWidth = width; card.Width = width;
        if (height is { } h) card.Height = h;
        card.HorizontalAlignment = HorizontalAlignment.Center; card.VerticalAlignment = VerticalAlignment.Center;
        card.Shadow = Shadows.Strong; card.Translation = new Vector3(0, 0, 48);
        card.Margin = new Thickness(24);
        Children.Add(scrim); Children.Add(card);
        SizeChanged += (_, e) =>
        {
            card.Width = Math.Min(width, Math.Max(0, e.NewSize.Width - 48));
            if (height is { } fixedHeight) card.Height = Math.Min(fixedHeight, Math.Max(0, e.NewSize.Height - 48));
        };
        KeyDown += (_, e) => { if (e.Key == Windows.System.VirtualKey.Escape && dismissible) { dismiss?.Invoke(); e.Handled = true; } };
        Loaded += (_, _) => { Motion.Appear(card); scrim.Opacity = 0; Motion.Fade(scrim, 1, TimeSpan.FromSeconds(0.16)); };
        AutomationProperties.SetName(this, "mica");
    }
}
