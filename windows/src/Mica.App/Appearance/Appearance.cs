using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Mica.Core;
using Mica.Design;

namespace Mica.App.Appearance;

/// <summary>App icons from the Orbit pack, converted from macOS HEIC to ICO and PNG in shared/icons/app. On Windows a
/// chosen icon shows on the taskbar and in Alt+Tab for open windows; shortcuts keep the standard icon (macOS: Finder
/// and Launchpad keep it too).</summary>
public static class AppIcons
{
    public sealed record Icon(string Id, string Low, string Regular);
    public sealed record IconSet(string Id, string Low, string Regular, Icon[] Icons);
    public const string Standard = "base-original";
    public static readonly IconSet[] Sets =
    [
        new("base", "стандартные", "Стандартные", [new("base-original", "исходная", "Исходная"), new("base-light", "светлая", "Светлая"), new("base-dark", "тёмная", "Тёмная"), new("base-cream", "кремовая", "Кремовая"), new("base-purple", "фиолетовая", "Фиолетовая"), new("base-blue", "голубая", "Голубая"), new("base-pink", "розовая", "Розовая"), new("base-red-neon", "красный неон", "Красный неон")]),
        new("sonic", "sonic", "Sonic", new[] { "Sonic", "Tails", "Knuckles", "Amy", "Shadow" }.Select(n => new Icon("sonic-" + n.ToLowerInvariant(), n, n)).ToArray()),
        new("kitty", "hello kitty", "Hello Kitty", new[] { "Hello Kitty", "Kuromi", "My Melody", "Cinnamoroll", "Pompompurin" }.Select(n => new Icon("kitty-" + n.ToLowerInvariant().Replace(' ', '-'), n, n)).ToArray()),
        new("pony", "my little pony", "My Little Pony", new[] { "Twilight Sparkle", "Rainbow Dash", "Pinkie Pie", "Rarity", "Applejack", "Fluttershy" }.Select(n => new Icon("pony-" + n.ToLowerInvariant().Replace(' ', '-'), n, n)).ToArray()),
    ];

    static string Folder => Path.Combine(AppContext.BaseDirectory, "Assets", "AppIcons");
    public static string? Ico(string? id) { var path = Path.Combine(Folder, (id ?? Standard) + ".ico"); return File.Exists(path) ? path : null; }
    public static string? Png(string? id) { var path = Path.Combine(Folder, (id ?? Standard) + ".png"); return File.Exists(path) ? path : null; }
    public static bool Available => Png(Standard) is not null;

    public static void Apply(Store store)
    {
        var path = Ico(store.Preferences.AppIcon) ?? Path.Combine(AppContext.BaseDirectory, "Assets", "mica.ico");
        foreach (var window in store.Windows) window.AppWindow.SetIcon(path);
    }
}

public sealed partial class IconPicker : StackPanel
{
    public IconPicker(Store store)
    {
        Spacing = Space.Normal;
        if (!AppIcons.Available) { Children.Add(Ui.Text(store.Text("в этой сборке нет набора иконок", "В этой сборке нет набора иконок"), 12, Palette.Text3.Brush())); return; }
        var choices = new List<(string? Id, Border Ring)>();
        void Render() { foreach (var (id, ring) in choices) ring.BorderBrush = (store.Preferences.AppIcon ?? AppIcons.Standard) == id ? Look.Focus : Palette.Clear; }
        foreach (var set in AppIcons.Sets)
        {
            var grid = new VariableSizedWrapGrid { Orientation = Orientation.Horizontal, ItemWidth = 52, ItemHeight = 52 };
            foreach (var icon in set.Icons)
            {
                var image = new Image { Width = 40, Height = 40, Source = AppIcons.Png(icon.Id) is { } png ? new BitmapImage(new Uri(png)) { DecodePixelWidth = 80 } : null };
                var ring = Ui.Rounded(12, Palette.Clear, Palette.Clear, 2, image); ring.Padding = new Thickness(3); ring.Margin = new Thickness(3);
                var id = icon.Id;
                var tile = new Grid { Background = Palette.Clear, IsTabStop = true };
                tile.Children.Add(ring);
                var interaction = new Interaction(tile, () => { }, 0.92);
                interaction.Invoked += () => { store.Change(p => p.AppIcon = id == AppIcons.Standard ? null : id); Render(); };
                tile.PointerEntered += (_, _) => Motion.Scale(ring, 1.04, Motion.Snappy);
                tile.PointerExited += (_, _) => Motion.Scale(ring, 1, Motion.Snappy);
                tile.Tip(store.Text(icon.Low, icon.Regular));
                choices.Add((id, ring));
                grid.Children.Add(tile);
            }
            Children.Add(Ui.V(6, Ui.Text(store.Text(set.Low, set.Regular), 11.5, Palette.Text3.Brush(), Ui.Medium), grid));
        }
        Render();
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(this, store.Text("иконка приложения", "Иконка приложения"));
    }
}

/// <summary>Preset accents plus the system colour picker for anything else; every change applies immediately.</summary>
public sealed partial class AccentPicker : StackPanel
{
    public static readonly string[] Presets = ["#6E56CF", "#3E7BFA", "#1F9D8B", "#3FA34D", "#E8A33D", "#E5484D", "#D6409F", "#8D7B6A"];
    public AccentPicker(Store store)
    {
        Orientation = Orientation.Horizontal; Spacing = 6; VerticalAlignment = VerticalAlignment.Center;
        var rings = new List<(string Hex, Border Ring)>();
        var label = Ui.Text(store.Preferences.Accent, 11, Palette.Text3.Brush()); label.FontFamily = new FontFamily("Cascadia Mono, Consolas"); label.IsTextSelectionEnabled = true;
        void Render() { foreach (var (hex, ring) in rings) ring.BorderBrush = store.Preferences.Accent.Equals(hex, StringComparison.OrdinalIgnoreCase) ? Palette.Ink.Brush() : Palette.Clear; label.Text = store.Preferences.Accent; }
        foreach (var hex in Presets)
        {
            var c = HexColor.Parse(hex)!.Value;
            var dot = new Microsoft.UI.Xaml.Shapes.Ellipse { Width = 20, Height = 20, Fill = new SolidColorBrush(Windows.UI.Color.FromArgb(255, (byte)Math.Round(c.Red * 255), (byte)Math.Round(c.Green * 255), (byte)Math.Round(c.Blue * 255))) };
            var ring = Ui.Rounded(13, Palette.Clear, Palette.Clear, 1.5, dot); ring.Padding = new Thickness(3);
            var h = hex;
            var interaction = new Interaction(ring, () => { }, 0.88);
            interaction.Invoked += () => { store.Change(p => p.Accent = h); Render(); };
            ring.Tip(hex);
            rings.Add((hex, ring));
            Children.Add(ring);
        }
        var more = new IconButton("paintbrush", store.Text("другой цвет", "Другой цвет"), 26);
        more.Click += () =>
        {
            var current = HexColor.Parse(store.Preferences.Accent) ?? (0.43, 0.34, 0.81);
            var picker = new ColorPicker { IsAlphaEnabled = false, Color = Windows.UI.Color.FromArgb(255, (byte)(current.Red * 255), (byte)(current.Green * 255), (byte)(current.Blue * 255)) };
            picker.ColorChanged += (_, e) => { store.Change(p => p.Accent = HexColor.ToHex(e.NewColor.R / 255.0, e.NewColor.G / 255.0, e.NewColor.B / 255.0)); Render(); };
            new Flyout { Content = picker }.ShowAt(more);
        };
        Children.Add(more); Children.Add(label);
        Render();
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(this, store.Text("акцентный цвет", "Акцентный цвет"));
    }
}

/// <summary>Miniature of the real shell (macOS LayoutPreview): layout, collapsed rail, theme, accent, material.
/// The Windows version draws caption buttons on the right instead of the macOS window buttons.</summary>
public sealed partial class LayoutPreview : Grid
{
    readonly Store store;
    public LayoutPreview(Store store)
    {
        this.store = store;
        CornerRadius = new CornerRadius(Radius.Panel - 4);
        BorderBrush = Palette.HairlineStrong.Brush(); BorderThickness = new Thickness(1);
        this.Bind(h => store.PreferencesUpdated += h, h => store.PreferencesUpdated -= h, Render);
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(this, store.Text("предпросмотр оформления и раскладки", "Предпросмотр оформления и раскладки"));
    }

    void Render()
    {
        Children.Clear();
        Background = Look.Shell;
        var layout = store.Preferences.Layout;
        var collapsed = store.Preferences.SidebarCollapsed && !layout.IsHorizontal();
        var root = new Grid { Padding = new Thickness(8), RowSpacing = 6 };
        root.RowDefinitions.Add(Ui.RowFixed(14)); root.RowDefinitions.Add(Ui.RowAuto()); root.RowDefinitions.Add(Ui.RowStar());
        var bar = new Grid();
        var field = Ui.Rounded(4, Palette.Track.Brush()); field.Width = 130; field.Height = 11; field.HorizontalAlignment = HorizontalAlignment.Center;
        if (layout != TabLayout.TabsAbove) bar.Children.Add(field);
        var captions = Ui.H(6); captions.HorizontalAlignment = HorizontalAlignment.Right;
        foreach (var _ in Enumerable.Range(0, 3)) { var c = Ui.Rounded(1, Palette.SwitchOff.Brush()); c.Width = 8; c.Height = 2; captions.Children.Add(c); }
        captions.VerticalAlignment = VerticalAlignment.Center;
        bar.Children.Add(captions);
        root.Row(bar, 0);
        if (layout.IsHorizontal())
        {
            var tabs = Ui.H(4);
            for (var i = 0; i < 4; i++) { var t = Ui.Rounded(4, i == 0 ? Palette.Selected.Brush() : Palette.Track.Brush()); t.Width = 52; t.Height = 12; tabs.Children.Add(t); }
            if (layout == TabLayout.Top) root.Row(tabs, 1);
            else
            {
                // Tabs in the caption band beside the caption buttons, the address row under them.
                tabs.VerticalAlignment = VerticalAlignment.Center;
                bar.Children.Add(tabs);
                root.Row(field, 1);
            }
        }
        var body = new Grid { ColumnSpacing = 6 };
        body.ColumnDefinitions.Add(Ui.Auto()); body.ColumnDefinitions.Add(Ui.Star()); body.ColumnDefinitions.Add(Ui.Auto());
        var page = Ui.Rounded(6, Palette.Canvas.Brush(), Palette.Hairline.Brush(), 1);
        var mark = Ui.Text("mica", 18, Palette.Text3.Brush(), Ui.Weight(300)); mark.HorizontalAlignment = HorizontalAlignment.Center;
        var pill = Ui.Rounded(6, Look.Primary); pill.Width = 46; pill.Height = 12; pill.HorizontalAlignment = HorizontalAlignment.Center;
        var center = Ui.V(6, mark, pill); center.VerticalAlignment = VerticalAlignment.Center;
        page.Child = center;
        body.Column(page, 1);
        if (layout.SidebarEdge() is { } side) body.Column(Rail(collapsed), side == TabLayout.Left ? 0 : 2);
        root.Row(body, 2);
        Children.Add(root);
    }

    static StackPanel Rail(bool collapsed)
    {
        var rail = Ui.V(5);
        for (var i = 0; i < 5; i++)
        {
            if (collapsed) { var dot = Ui.Rounded(3, i == 0 ? Palette.Selected.Brush() : Palette.Track.Brush()); dot.Width = 12; dot.Height = 12; rail.Children.Add(dot); }
            else
            {
                var row = Ui.Rounded(4, i == 0 ? Palette.Selected.Brush() : Palette.Clear); row.Height = 13; row.Width = 76;
                var line = Ui.Rounded(2, Palette.SwitchOff.Brush()); line.Width = i == 0 ? 60 : 44 + i * 7; line.Height = 4; line.HorizontalAlignment = HorizontalAlignment.Left; line.Margin = new Thickness(6, 0, 0, 0);
                row.Child = line; rail.Children.Add(row);
            }
        }
        return rail;
    }
}

/// <summary>What the start page will show above the search field.</summary>
public sealed partial class GreetingPreview : Grid
{
    public GreetingPreview(Store store)
    {
        Height = 150; CornerRadius = new CornerRadius(Radius.Panel - 4);
        BorderBrush = Palette.HairlineStrong.Brush(); BorderThickness = new Thickness(1);
        Background = Look.Shell;
        var card = Ui.Rounded(6, Palette.Canvas.Brush(), Palette.Hairline.Brush(), 1); card.Margin = new Thickness(8);
        var text = Ui.Text("", 24, null, Ui.Weight(300)); text.HorizontalAlignment = HorizontalAlignment.Center;
        var field = Ui.Rounded(Radius.Row, Palette.Surface.Brush(), Palette.Hairline.Brush(), 1, Ui.H(Space.Small, new Glyph("magnifyingglass", 11, Palette.Text3.Brush()), Ui.Text(store.Text("поиск или адрес", "Поиск или адрес"), 12, Palette.Text3.Brush())).Margin(Space.Normal, 0, Space.Normal, 0));
        field.Width = 300; field.Height = 34; field.HorizontalAlignment = HorizontalAlignment.Center;
        var stack = Ui.V(Space.Small, text, field); stack.VerticalAlignment = VerticalAlignment.Center;
        card.Child = stack;
        Children.Add(card);
        void Render()
        {
            var greeting = Greeting.Text(store.Preferences, DateTime.Now.Hour, 1);
            text.Text = greeting ?? "mica"; text.FontSize = greeting is null ? 30 : 24; text.CharacterSpacing = greeting is null ? -36 : -28;
            Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(this, store.Text("начальная страница: ", "Начальная страница: ") + text.Text);
        }
        this.Bind(h => store.PreferencesUpdated += h, h => store.PreferencesUpdated -= h, Render);
    }
}
