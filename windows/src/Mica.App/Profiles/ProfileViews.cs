using System.Numerics;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using Mica.Core;
using Mica.Design;
using Windows.UI;

namespace Mica.App;

public static class Hex
{
    public static Color ToColor(string hex) => HexColor.Parse(hex) is { } c
        ? Color.FromArgb(255, (byte)Math.Round(c.Red * 255), (byte)Math.Round(c.Green * 255), (byte)Math.Round(c.Blue * 255))
        : Palette.Track.Resolve();
    public static SolidColorBrush Brush(string hex) => new(ToColor(hex));
}

/// <summary>Profile icon on its background, rounded like site tiles; white glyph or ink, whichever the background allows
/// (macOS ProfileMark).</summary>
public sealed partial class ProfileMark : Grid
{
    public ProfileMark(Profile profile, double size = 20) : this(profile.Icon, profile.Background, size, profile.Glyph) { }
    public ProfileMark(string icon, string background, double size = 20, ProfileGlyph glyph = ProfileGlyph.Auto)
    {
        Width = size; Height = size; IsHitTestVisible = false;
        Children.Add(Ui.Rounded(size * 0.3, Hex.Brush(background)));
        var ink = Core.Profiles.LightGlyph(background, glyph) ? new SolidColorBrush(Microsoft.UI.Colors.White) : Palette.Fixed(0xFF121213);
        Children.Add(new Glyph(icon, size * 0.5, ink) { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center });
        AutomationProperties.SetAccessibilityView(this, Microsoft.UI.Xaml.Automation.Peers.AccessibilityView.Raw);
    }
}

/// <summary>Profiles from the shell: switch this window, create a profile, open profile settings (macOS ProfileMenu).</summary>
public static class ProfileMenu
{
    public static IEnumerable<MenuEntry> Entries(BrowserModel browser)
    {
        var store = browser.Store;
        foreach (var profile in store.Profiles.ToList())
        {
            var p = profile;
            yield return new MenuEntry(store.ProfileName(p), () => _ = Open(p.Id, browser), Checked: p.Id == browser.ProfileId, Leading: () => new ProfileMark(p, 16));
        }
        yield return MenuEntry.Separator;
        if (store.Profiles.Count < Core.Profiles.Limit)
            yield return MenuEntry.Item(browser.Text("новый профиль…", "Новый профиль…"), () => Edit(browser, store.AddProfile(browser.ProfileId).Id), "plus");
        yield return MenuEntry.Item(browser.Text("настроить профили…", "Настроить профили…"), () => Edit(browser, browser.ProfileId), "gearshape");
    }

    /// <summary>The "…" menu lists every profile, as the macOS menu bar and Dock do: a window of it comes forward or opens.</summary>
    public static IEnumerable<MenuEntry> OpenEntries(Store store) =>
        store.Profiles.ToList().Select(p => new MenuEntry(store.ProfileName(p), () => store.OpenProfile(p.Id),
            Checked: store.Windows.Any(w => w.Model.ProfileId == p.Id && !w.Model.PrivateMode), Leading: () => new ProfileMark(p, 16)));

    /// <summary>Opens a profile chosen in the menu as the user set it up: in this window, in a new one, or after asking in
    /// ProfileOpenPrompt.
    /// Switching this window swaps its pinned tabs for the profile's, so until an answer is remembered mica asks.</summary>
    public static Task Open(Guid id, BrowserModel browser)
    {
        var store = browser.Store;
        if (id == browser.ProfileId) return Task.CompletedTask;
        var choice = store.Preferences.ProfileOpening;
        if (choice == ProfileOpening.Ask) browser.ProfilePrompt = id;
        else if (choice == ProfileOpening.Here) browser.SwitchProfile(id);
        else store.OpenProfile(id);
        return Task.CompletedTask;
    }

    public static void Edit(BrowserModel browser, Guid profile)
    {
        browser.EditingProfile = profile;
        browser.SettingsSection = Settings.SettingsSection.Profiles;
        browser.ShowSettings = true;
    }
}

/// <summary>The window's profile mark in the toolbar; a click opens the profile menu under it.</summary>
public sealed partial class ProfileButton : MicaControl
{
    readonly BrowserModel browser;
    readonly Border fill;
    readonly Interaction interaction;
    public ProfileButton(BrowserModel browser, double size = 28)
    {
        this.browser = browser;
        Width = size; Height = size;
        fill = Ui.Rounded(Radius.Icon);
        Root.Children.Add(fill);
        interaction = new Interaction(this, () => fill.Background = interaction!.Hover ? Palette.Hover.Brush() : Palette.Clear, 0.9);
        interaction.Invoked += () => MicaMenu.ShowBelow(ProfileMenu.Entries(browser), this);
        this.Bind(h => browser.Store.ProfilesChanged += h, h => browser.Store.ProfilesChanged -= h, Render);
    }
    void Render()
    {
        var profile = browser.Profile;
        if (Root.Children.Count > 1) Root.Children.RemoveAt(1);
        var mark = new ProfileMark(profile, Width * 0.64) { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        Root.Children.Add(mark);
        Motion.Appear(mark);
        var label = browser.Text("профиль: ", "Профиль: ") + browser.Store.ProfileName(profile);
        this.Tip(label);
    }
}

/// <summary>Line at the top of settings a profile owns, so it is clear which profile they change.</summary>
public static class ProfileScope
{
    public static UIElement Make(BrowserModel browser)
    {
        var host = new Grid();
        void Render()
        {
            host.Children.Clear();
            var store = browser.Store;
            if (store.Profiles.Count < 2) return;
            var row = new Grid { ColumnSpacing = Space.Small, Padding = new Thickness(10, 0, 4, 0), Height = 36 };
            row.ColumnDefinitions.Add(Ui.Auto()); row.ColumnDefinitions.Add(Ui.Star()); row.ColumnDefinitions.Add(Ui.Auto());
            row.Column(new ProfileMark(browser.Profile, 18) { VerticalAlignment = VerticalAlignment.Center }, 0);
            var text = Ui.Text(store.Text("настройки профиля ", "Настройки профиля ") + store.Quoted(store.ProfileName(browser.Profile)), 12, Palette.Text2.Brush());
            text.VerticalAlignment = VerticalAlignment.Center;
            row.Column(text, 1);
            var open = new MButton(store.Text("профили", "Профили"), ButtonKind.Ghost, compact: true) { VerticalAlignment = VerticalAlignment.Center };
            open.Click += () => ProfileMenu.Edit(browser, browser.ProfileId);
            row.Column(open, 2);
            host.Children.Add(Ui.Rounded(Radius.Panel - 4, new SolidColorBrush(Palette.WithAlpha(Palette.Track.Resolve(), 0.6)), null, 0, row));
        }
        host.Bind(h => browser.Store.ProfilesChanged += h, h => browser.Store.ProfilesChanged -= h, Render);
        return host;
    }
}

/// <summary>Round colour choice for accents and profile backgrounds.</summary>
public sealed partial class ColorDot : Grid
{
    readonly Border ring;
    public ColorDot(string hex, bool selected, double size, Action pick)
    {
        Width = size; Height = size;
        var dot = new Ellipse { Width = size - 6, Height = size - 6, Fill = Hex.Brush(hex) };
        ring = Ui.Rounded(size / 2, Palette.Clear, selected ? Palette.Ink.Brush() : Palette.Clear, 1.5, dot);
        ring.Padding = new Thickness(3);
        Children.Add(ring);
        var interaction = new Interaction(this, () => { }, 0.88);
        interaction.Invoked += pick;
        this.Tip(hex);
        IsTabStop = true;
    }
}

/// <summary>Opens mica's colour panel under itself: presets, saturation and brightness, hue (macOS ColorWell).</summary>
public sealed partial class ColorWell : Grid
{
    public ColorWell(Func<string> current, IReadOnlyList<string> presets, string label, double size, Action<string> change)
    {
        Width = size; Height = size; IsTabStop = true;
        var stops = new GradientStopCollection();
        for (var i = 0; i <= 6; i++) stops.Add(new GradientStop { Color = Hsv.ToColor(i / 6.0, 0.85, 0.95), Offset = i / 6.0 });
        var ring = new Ellipse { Width = size - 6, Height = size - 6, StrokeThickness = 2.5, Stroke = new LinearGradientBrush(stops, 45) };
        var center = new Grid { Width = size - 6, Height = size - 6 };
        Children.Add(ring); Children.Add(center);
        void Render()
        {
            center.Children.Clear();
            var hex = current().ToUpperInvariant();
            if (presets.Contains(hex)) center.Children.Add(new Glyph("plus", size * 0.36, Palette.Text2.Brush()) { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center });
            else center.Children.Add(new Ellipse { Width = size - 16, Height = size - 16, Fill = Hex.Brush(hex) });
        }
        Render();
        var interaction = new Interaction(this, () => { }, 0.88);
        interaction.Invoked += () => MicaPopover.ShowBelow(new ColorPanel(current(), presets, label, hex => { change(hex); Render(); }), this);
        this.Tip(label);
    }
}

/// <summary>One mica popover at a time, opened under a control like the shell menus; light dismiss and Esc close it.</summary>
public static class MicaPopover
{
    static Popup? open;
    public static void Close() { if (open is { } popup) { open = null; popup.IsOpen = false; } }
    public static void ShowBelow(UIElement content, FrameworkElement anchor)
    {
        if (anchor.XamlRoot is null) return;
        Close();
        var at = anchor.TransformToVisual(anchor.XamlRoot.Content).TransformPoint(new Windows.Foundation.Point(0, anchor.ActualHeight + 6));
        var panel = Ui.Raised(content);
        panel.Shadow = Shadows.Soft; panel.Translation = new Vector3(0, 0, 12);
        var popup = new Popup { Child = panel, XamlRoot = anchor.XamlRoot, IsLightDismissEnabled = true, ShouldConstrainToRootBounds = false, HorizontalOffset = at.X, VerticalOffset = at.Y };
        popup.Closed += (_, _) => { if (open == popup) open = null; };
        panel.KeyDown += (_, e) => { if (e.Key == Windows.System.VirtualKey.Escape) { Close(); e.Handled = true; } };
        open = popup;
        popup.IsOpen = true;
        panel.Loaded += (_, _) =>
        {
            var root = anchor.XamlRoot.Size;
            if (at.X + panel.ActualWidth > root.Width - 4) popup.HorizontalOffset = Math.Max(4, at.X + anchor.ActualWidth - panel.ActualWidth);
            if (at.Y + panel.ActualHeight > root.Height - 4) popup.VerticalOffset = Math.Max(4, at.Y - anchor.ActualHeight - 12 - panel.ActualHeight);
            Motion.Appear(panel);
        };
    }
}

/// <summary>Hue, saturation and value in 0…1, the coordinates of the picker field.</summary>
public static class Hsv
{
    public static Color ToColor(double h, double s, double v)
    {
        var (r, g, b) = ToRgb(h, s, v);
        return Color.FromArgb(255, (byte)Math.Round(r * 255), (byte)Math.Round(g * 255), (byte)Math.Round(b * 255));
    }
    public static (double R, double G, double B) ToRgb(double h, double s, double v)
    {
        h = (h % 1 + 1) % 1 * 6;
        var i = (int)Math.Floor(h); var f = h - i;
        double p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f));
        return i switch { 0 => (v, t, p), 1 => (q, v, p), 2 => (p, v, t), 3 => (p, q, v), 4 => (t, p, v), _ => (v, p, q) };
    }
    public static (double H, double S, double V) FromHex(string hex)
    {
        var (r, g, b) = HexColor.Parse(hex) ?? (0.5, 0.5, 0.5);
        var max = Math.Max(r, Math.Max(g, b)); var min = Math.Min(r, Math.Min(g, b)); var d = max - min;
        double h = 0;
        if (d > 0) h = max == r ? ((g - b) / d % 6 + 6) % 6 : max == g ? (b - r) / d + 2 : (r - g) / d + 4;
        return (h / 6, max == 0 ? 0 : d / max, max);
    }
    public static string ToHex(double h, double s, double v) { var (r, g, b) = ToRgb(h, s, v); return HexColor.ToHex(r, g, b); }
}

/// <summary>Presets, a saturation and brightness field and a hue strip; every change applies live (macOS ColorPanel).
/// WinUI has no screen colour sampler for desktop apps, so there is no eyedropper here.</summary>
public sealed partial class ColorPanel : StackPanel
{
    double hue, saturation, value;
    string hex;
    readonly Action<string> change;
    readonly Rectangle field = new() { RadiusX = Radius.Icon, RadiusY = Radius.Icon };
    readonly Ellipse fieldKnob = new() { Width = 14, Height = 14, StrokeThickness = 2, Stroke = new SolidColorBrush(Microsoft.UI.Colors.White) };
    readonly Ellipse hueKnob = new() { Width = 16, Height = 16, StrokeThickness = 2, Stroke = new SolidColorBrush(Microsoft.UI.Colors.White) };
    readonly Border preview = Ui.Rounded(6, null, Palette.Hairline.Brush(), 1);
    readonly TextBlock code;
    readonly List<(string Hex, ColorDotSlot Slot)> dots = [];
    const double FieldWidth = 216, FieldHeight = 132;

    sealed partial class ColorDotSlot : Grid { }

    public ColorPanel(string start, IReadOnlyList<string> presets, string label, Action<string> change)
    {
        this.change = change;
        hex = HexColor.Parse(start) is null ? "#8D7B6A" : start.ToUpperInvariant();
        (hue, saturation, value) = Hsv.FromHex(hex);
        Spacing = Space.Normal; Padding = new Thickness(12);
        AutomationProperties.SetName(this, label);
        // Presets, eight per row.
        var rows = new StackPanel { Spacing = 6 };
        StackPanel? line = null;
        for (var i = 0; i < presets.Count; i++)
        {
            if (i % 8 == 0) { line = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6 }; rows.Children.Add(line); }
            var slot = new ColorDotSlot { Width = 22, Height = 22 };
            dots.Add((presets[i], slot));
            line!.Children.Add(slot);
        }
        Children.Add(rows);
        // Saturation left to right, brightness bottom to top.
        var area = new Grid { Width = FieldWidth, Height = FieldHeight, Background = Palette.Clear };
        area.Children.Add(field);
        area.Children.Add(new Rectangle { RadiusX = Radius.Icon, RadiusY = Radius.Icon, Fill = new LinearGradientBrush(new GradientStopCollection { new() { Color = Microsoft.UI.Colors.White, Offset = 0 }, new() { Color = Color.FromArgb(0, 255, 255, 255), Offset = 1 } }, 0) });
        area.Children.Add(new Rectangle { RadiusX = Radius.Icon, RadiusY = Radius.Icon, Fill = new LinearGradientBrush(new GradientStopCollection { new() { Color = Color.FromArgb(0, 0, 0, 0), Offset = 0 }, new() { Color = Microsoft.UI.Colors.Black, Offset = 1 } }, 90) });
        area.Children.Add(new Rectangle { RadiusX = Radius.Icon, RadiusY = Radius.Icon, Stroke = Palette.Hairline.Brush(), StrokeThickness = 1 });
        fieldKnob.HorizontalAlignment = HorizontalAlignment.Left; fieldKnob.VerticalAlignment = VerticalAlignment.Top;
        area.Children.Add(fieldKnob);
        Drag(area, p =>
        {
            saturation = Math.Clamp(p.X / FieldWidth, 0, 1);
            value = Math.Clamp(1 - p.Y / FieldHeight, 0, 1);
            Commit();
        });
        AutomationProperties.SetName(area, Store.Shared.Text("яркость", "Яркость"));
        Children.Add(area);
        // Hue strip.
        var stops = new GradientStopCollection();
        for (var i = 0; i <= 6; i++) stops.Add(new GradientStop { Color = Hsv.ToColor(i / 6.0, 1, 1), Offset = i / 6.0 });
        var strip = new Grid { Width = FieldWidth, Height = 16, Background = Palette.Clear };
        strip.Children.Add(new Rectangle { Height = 14, RadiusX = 7, RadiusY = 7, Fill = new LinearGradientBrush(stops, 0), Stroke = Palette.Hairline.Brush(), StrokeThickness = 1, VerticalAlignment = VerticalAlignment.Center });
        hueKnob.HorizontalAlignment = HorizontalAlignment.Left;
        strip.Children.Add(hueKnob);
        Drag(strip, p =>
        {
            hue = Math.Clamp((p.X - 8) / (FieldWidth - 16), 0, 0.999);
            if (saturation < 0.05) saturation = 0.6;
            if (value < 0.05) value = 0.7;
            Commit();
        });
        AutomationProperties.SetName(strip, Store.Shared.Text("оттенок", "Оттенок"));
        Children.Add(strip);
        preview.Width = 22; preview.Height = 22;
        code = Ui.Text(hex, 12, Palette.Text2.Brush());
        code.FontFamily = new FontFamily("Cascadia Mono, Consolas"); code.IsTextSelectionEnabled = true; code.VerticalAlignment = VerticalAlignment.Center;
        Children.Add(Ui.H(Space.Small, preview, code));
        Render();
    }

    static void Drag(Grid target, Action<Windows.Foundation.Point> move)
    {
        var dragging = false;
        target.PointerPressed += (_, e) => { dragging = true; target.CapturePointer(e.Pointer); move(e.GetCurrentPoint(target).Position); e.Handled = true; };
        target.PointerMoved += (_, e) => { if (dragging) move(e.GetCurrentPoint(target).Position); };
        target.PointerReleased += (_, e) => { dragging = false; target.ReleasePointerCapture(e.Pointer); };
        target.PointerCaptureLost += (_, _) => dragging = false;
    }

    void Pick(string preset)
    {
        hex = preset.ToUpperInvariant();
        (hue, saturation, value) = Hsv.FromHex(hex);
        change(hex);
        Render();
    }

    void Commit()
    {
        var next = Hsv.ToHex(hue, saturation, value);
        if (next != hex) { hex = next; change(hex); }
        Render();
    }

    void Render()
    {
        field.Fill = new SolidColorBrush(Hsv.ToColor(hue, 1, 1));
        fieldKnob.Fill = new SolidColorBrush(Hsv.ToColor(hue, saturation, value));
        fieldKnob.Margin = new Thickness(saturation * FieldWidth - 7, (1 - value) * FieldHeight - 7, 0, 0);
        hueKnob.Fill = new SolidColorBrush(Hsv.ToColor(hue, 1, 1));
        hueKnob.Margin = new Thickness(hue * (FieldWidth - 16), 0, 0, 0);
        preview.Background = Hex.Brush(hex);
        code.Text = hex;
        foreach (var (preset, slot) in dots)
        {
            slot.Children.Clear();
            var p = preset;
            slot.Children.Add(new ColorDot(preset, preset == hex, 22, () => Pick(p)));
        }
    }
}

/// <summary>Where to open a profile chosen in the profile menu (macOS ProfileOpenPrompt): the composition of a system
/// question, mark on top, title, text, buttons stacked full width and the remember switch, in mica's own card. The new
/// window is the default because it leaves this window as it is; Enter picks it, Esc or a click beside cancels.</summary>
public sealed partial class ProfileOpenPrompt : StackPanel
{
    public ProfileOpenPrompt(BrowserModel browser, Guid id)
    {
        var store = browser.Store;
        var profile = store.Profile(id);
        Padding = new Thickness(22, 24, 22, 18);
        var mark = new ProfileMark(profile, 56) { HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 0, 0, 14) };
        var title = Ui.Text(store.Text("открыть профиль ", "Открыть профиль ") + store.Quoted(store.ProfileName(profile)) + "?", 14, Palette.Ink.Brush(), Ui.Semibold, wrap: true);
        title.TextAlignment = TextAlignment.Center; title.HorizontalAlignment = HorizontalAlignment.Center; title.Margin = new Thickness(0, 0, 0, 6);
        var detail = Ui.Text(store.Text("в этом окне закреплённые вкладки сменятся закреплёнными вкладками профиля, остальные вкладки останутся. в новом окне это окно не изменится.", "В этом окне закреплённые вкладки сменятся закреплёнными вкладками профиля, остальные вкладки останутся. В новом окне это окно не изменится."), 12, Palette.Text2.Brush(), wrap: true);
        detail.TextAlignment = TextAlignment.Center; detail.Margin = new Thickness(0, 0, 0, 18);
        var remember = new ToggleRow(store.Text("запомнить выбор", "Запомнить выбор"), false, _ => { }, divider: false) { HorizontalAlignment = HorizontalAlignment.Center };
        void Choose(ProfileOpening choice)
        {
            if (remember.Switch.IsOn) store.Change(p => p.ProfileOpening = choice);
            browser.ProfilePrompt = null;
            if (choice == ProfileOpening.Here) browser.SwitchProfile(id); else store.OpenProfile(id);
        }
        var newWindow = new MButton(store.Text("в новом окне", "В новом окне"), ButtonKind.Primary, stretch: true);
        newWindow.Click += () => Choose(ProfileOpening.NewWindow);
        var here = new MButton(store.Text("в этом окне", "В этом окне"), ButtonKind.Secondary, stretch: true);
        here.Click += () => Choose(ProfileOpening.Here);
        var cancel = new MButton(store.Text("отмена", "Отмена"), ButtonKind.Ghost, stretch: true);
        cancel.Click += () => browser.ProfilePrompt = null;
        var buttons = Ui.V(Space.Small, newWindow, here, cancel); buttons.Margin = new Thickness(0, 0, 0, 14);
        Children.Add(mark); Children.Add(title); Children.Add(detail); Children.Add(buttons); Children.Add(remember);
        KeyDown += (_, e) => { if (e.Key == Windows.System.VirtualKey.Enter) { Choose(ProfileOpening.NewWindow); e.Handled = true; } };
        Loaded += (_, _) => newWindow.Focus(FocusState.Programmatic);
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(this, title.Text);
    }
}
