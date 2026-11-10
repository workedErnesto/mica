using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Mica.Core;
using Mica.Design;
using Windows.ApplicationModel.DataTransfer;

namespace Mica.App;

/// <summary>Tab status glyph: error, load progress, otherwise the site icon or its monogram (dimmed until a restored
/// tab loads). <c>plain</c> and <c>tint</c> serve rail tiles: a monogram without its own plate.</summary>
public sealed partial class TabIcon : Grid
{
    readonly Tab tab; readonly double size; readonly bool plain;
    Brush? tint;
    UIElement? shown; string state = ""; ImageSource? image;
    public TabIcon(Tab tab, double size = 16, bool plain = false)
    {
        this.tab = tab; this.size = size; this.plain = plain; Width = size; Height = size;
        this.Bind(tab, Render);
        if (tab.Owner?.Favicons is { } favicons) this.Bind(h => favicons.Changed += h, h => favicons.Changed -= h, Render);
    }
    /// <summary>Monogram colour for rail tiles, which brighten it on hover and selection like the plus glyph.</summary>
    public void SetTint(Brush value) { if (ReferenceEquals(tint, value)) return; tint = value; state = ""; Render(); }
    void Render()
    {
        var favicon = tab.Phase == TabPhase.Terminated || tab.Loading ? null : tab.Favicon;
        var host = AddressParser.Host(tab.Url);
        var next = tab.Phase == TabPhase.Terminated ? "error" : tab.Loading ? "loading" : (favicon is null ? "mono:" : "icon:") + host + tab.Phase;
        if (next == state && ReferenceEquals(favicon, image)) { if (shown is Mica.Design.ProgressRing ring) ring.SetProgress(tab.Progress); return; }
        var arrived = favicon is not null && state.StartsWith("mono:", StringComparison.Ordinal);
        state = next; image = favicon;
        Children.Clear();
        var dim = tab.Phase == TabPhase.Restored ? 0.55 : 1;
        shown = next switch
        {
            "error" => new Glyph("exclamationmark.triangle", size * 0.7, Palette.Text2.Brush()) { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center },
            "loading" => new Mica.Design.ProgressRing(size),
            _ when favicon is not null => new Border { Width = size, Height = size, CornerRadius = new CornerRadius(size * 0.2), Background = new ImageBrush { ImageSource = favicon, Stretch = Stretch.Uniform }, Opacity = dim, IsHitTestVisible = false },
            _ => new Monogram(host, size, plain, tint) { Opacity = dim },
        };
        if (shown is Mica.Design.ProgressRing r) r.SetProgress(tab.Progress);
        Children.Add(shown);
        // The icon fades in over the monogram it replaces; opacity only, so Reduce Motion keeps it.
        if (arrived) { Microsoft.UI.Xaml.Hosting.ElementCompositionPreview.GetElementVisual(shown).Opacity = 0; Motion.Fade(shown, 1); }
    }
}

/// <summary>Drag to reorder and the tab context menu, shared by rows, pinned tiles and rail tiles.</summary>
public static class TabInteractions
{
    public static void Attach(FrameworkElement element, Tab tab, BrowserModel browser)
    {
        element.CanDrag = true;
        element.DragStarting += (_, e) => { e.Data.SetText("mica-tab:" + tab.Id); e.Data.RequestedOperation = DataPackageOperation.Move; };
        element.AllowDrop = true;
        element.DragOver += (_, e) => { e.AcceptedOperation = DataPackageOperation.Move; e.Handled = true; };
        element.Drop += async (_, e) =>
        {
            e.Handled = true;
            if (!e.DataView.Contains(StandardDataFormats.Text)) return;
            var text = await e.DataView.GetTextAsync();
            if (text.StartsWith("mica-tab:", StringComparison.Ordinal) && Guid.TryParse(text[9..], out var id)) browser.Move(id, tab.Id);
        };
        element.ContextMenu(() =>
        [
            MenuEntry.Item(browser.Text("дублировать", "Дублировать"), () => browser.Add(new SavedTab { Url = tab.Url, Title = tab.Title }), "plus.square.on.square"),
            MenuEntry.Item(tab.Pinned ? browser.Text("открепить", "Открепить") : browser.Text("закрепить", "Закрепить"), () => browser.Pin(tab), tab.Pinned ? "pin.slash" : "pin"),
            MenuEntry.Item(browser.Text("перезагрузить", "Перезагрузить"), tab.Reload, "arrow.clockwise", enabled: tab.Url is not null),
            MenuEntry.Item(browser.Text("копировать адрес", "Копировать адрес"), () => { var data = new DataPackage(); data.SetText(tab.Url!); Clipboard.SetContent(data); }, "link", enabled: tab.Url is not null),
            MenuEntry.Item(browser.Text("открыть в новом окне", "Открыть в новом окне"), () => { var window = browser.Store.NewWindow(browser.PrivateMode); if (tab.Url is { } url) window.Selected?.Load(url); }, "macwindow"),
            MenuEntry.Separator,
            MenuEntry.Item(browser.Text("закрыть остальные", "Закрыть остальные"), () => { foreach (var other in browser.Tabs.Where(o => o.Id != tab.Id && !o.Pinned).ToList()) browser.Close(other); }, "square.on.square.dashed"),
            MenuEntry.Item(browser.Text("закрыть все", "Закрыть все"), browser.CloseAll, "rectangle.on.rectangle.slash"),
            MenuEntry.Item(browser.Text("закрыть вкладку", "Закрыть вкладку"), () => browser.Close(tab), "xmark", shortcut: Keymap.Label("close")),
        ]);
        // Middle click closes, as in other Windows browsers.
        element.PointerReleased += (_, e) => { if (e.GetCurrentPoint(element).Properties.PointerUpdateKind == Microsoft.UI.Input.PointerUpdateKind.MiddleButtonReleased) { browser.Close(tab); e.Handled = true; } };
    }
}

/// <summary>A tab in the sidebar or the top strip (macOS TabRow).</summary>
public sealed partial class TabRow : Grid
{
    readonly Tab tab; readonly BrowserModel browser; readonly bool horizontal;
    readonly Border plate; readonly TextBlock title; readonly IconButton close; readonly Glyph pin;
    readonly Interaction interaction;
    public Guid TabId => tab.Id;
    public TabRow(Tab tab, BrowserModel browser, bool horizontal)
    {
        this.tab = tab; this.browser = browser; this.horizontal = horizontal;
        MinHeight = horizontal ? 30 : 34; Background = Palette.Clear; IsTabStop = true;
        plate = Ui.Rounded(Radius.Row);
        title = Ui.Text("", 12.5);
        var row = new Grid { Margin = new Thickness(8, 0, 30, 0), ColumnSpacing = 9 };
        row.ColumnDefinitions.Add(Ui.Auto()); row.ColumnDefinitions.Add(Ui.Star());
        row.Column(new TabIcon(tab) { VerticalAlignment = VerticalAlignment.Center }, 0); row.Column(title, 1);
        close = new IconButton("xmark", "", 22) { HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 5, 0), Opacity = 0 };
        close.Click += () => browser.Close(tab);
        pin = new Glyph("pin", 10, Palette.Text2.Brush()) { Width = 22, Height = 22, HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 5, 0), IsHitTestVisible = false, Opacity = 0 };
        Children.Add(plate); Children.Add(row); Children.Add(pin); Children.Add(close);
        interaction = new Interaction(this, Render, 0.98, plate);
        interaction.Invoked += () => browser.Select(tab);
        TabInteractions.Attach(this, tab, browser);
        this.Bind(tab, Render);
        this.Bind(browser, Render);
        Motion.AnimateLayoutMoves(this, Motion.Snappy);
    }
    void Render()
    {
        var selected = browser.SelectedId == tab.Id;
        var hover = interaction.Hover;
        title.Text = tab.DisplayTitle(browser.Store);
        title.FontWeight = selected ? Ui.Medium : Ui.Regular;
        title.Foreground = selected ? Palette.Ink.Brush() : tab.Phase == TabPhase.Restored ? Palette.Text3.Brush() : Palette.Text2.Brush();
        plate.Background = selected ? Palette.Selected.Brush() : hover ? (horizontal ? Palette.Pressed.Brush() : Palette.Hover.Brush()) : (horizontal ? Palette.Hover.Brush() : Palette.Clear);
        plate.Shadow = selected ? Shadows.Soft : null;
        plate.Translation = new System.Numerics.Vector3(0, 0, selected ? 2 : 0);
        var showClose = hover || (selected && !horizontal);
        Motion.Fade(pin, horizontal && tab.Pinned && !hover ? 1 : 0);
        Motion.Fade(close, showClose ? 1 : 0);
        close.IsHitTestVisible = showClose;
        close.SetLabel(browser.Text("закрыть: ", "Закрыть: ") + tab.Title);
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(this, (tab.Pinned ? browser.Text("закреплена: ", "Закреплена: ") : "") + tab.DisplayTitle(browser.Store) + (selected ? ", " + browser.Text("выбрана", "Выбрана") : tab.Phase == TabPhase.Restored ? ", " + browser.Text("ещё не загружена", "Ещё не загружена") : ""));
    }
}

/// <summary>Close badge of an icon-only tab tile (macOS TileCloseBadge). The tiles have no room for an × of their
/// own, so after the pointer rests on a tile for half a second a small raised round button pops in on its top-right
/// corner: its centre sits on the rounded outline, half over the tile and half outside. Pressing it closes the tab and
/// marks the press handled, so the tile underneath is not selected.</summary>
public sealed partial class TileCloseBadge : Grid
{
    /// <summary>Visible diameter, hit area, and distance from the tile's bounding corner to the badge centre
    /// (where the Radius.Row arc passes).</summary>
    public const double Face = 16, Box = 20, Inset = 3;
    /// <summary>Room the badge and its shadow need outside the tile; scroll viewers holding tiles keep it unclipped.</summary>
    public const double Overhang = Face / 2 - Inset + 3;
    static readonly TimeSpan Delay = TimeSpan.FromSeconds(MotionTokens.HoverIntent);
    readonly Grid tile;
    readonly Border face, tint;
    readonly Glyph glyph;
    readonly Interaction interaction;
    readonly Microsoft.UI.Dispatching.DispatcherQueueTimer delay;
    bool shown;

    public TileCloseBadge(Grid tile, Tab tab, BrowserModel browser)
    {
        this.tile = tile;
        Width = Box; Height = Box; Background = Palette.Clear; IsTabStop = false;
        HorizontalAlignment = HorizontalAlignment.Right; VerticalAlignment = VerticalAlignment.Top;
        // Negative margins put the centre at (width - Inset, Inset) of the tile; the tile's Grid does not clip.
        Margin = new Thickness(0, Inset - Box / 2, Inset - Box / 2, 0);
        // Hidden through the composition visual, which Motion.Fade animates, not XAML Opacity.
        Microsoft.UI.Xaml.Hosting.ElementCompositionPreview.GetElementVisual(this).Opacity = 0;
        IsHitTestVisible = false;
        tint = Ui.Rounded(Face / 2);
        glyph = new Glyph("xmark", 8, Palette.Text2.Brush()) { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        face = Ui.Rounded(Face / 2, Palette.Raised.Brush(), Palette.HairlineStrong.Brush(), 1, Ui.Grid(tint, glyph));
        face.Width = Face; face.Height = Face;
        face.HorizontalAlignment = HorizontalAlignment.Center; face.VerticalAlignment = VerticalAlignment.Center;
        face.Shadow = Shadows.Soft; face.Translation = new System.Numerics.Vector3(0, 0, 8);
        Children.Add(face);
        interaction = new Interaction(this, Render, 0.88, face);
        interaction.Invoked += () => browser.Close(tab);
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetAccessibilityView(this, Microsoft.UI.Xaml.Automation.Peers.AccessibilityView.Raw);
        delay = tile.DispatcherQueue.CreateTimer();
        delay.Interval = Delay; delay.IsRepeating = false;
        delay.Tick += (_, _) => Show();
        // The badge is the tile's child, so moving onto its outer half does not count as leaving the tile.
        tile.PointerEntered += (_, _) => { if (!shown) { delay.Stop(); delay.Start(); } };
        tile.PointerExited += (_, _) => { delay.Stop(); Hide(); };
        tile.PointerCanceled += (_, _) => { delay.Stop(); Hide(); };
        tile.Unloaded += (_, _) => delay.Stop();
        tile.Children.Add(this);
        SetLabel(browser.Text("закрыть: ", "Закрыть: ") + tab.DisplayTitle(browser.Store));
    }

    public void SetLabel(string label) => this.Tip(label);

    void Render()
    {
        glyph.Foreground = interaction.Hover || interaction.Pressed ? Palette.Ink.Brush() : Palette.Text2.Brush();
        tint.Background = interaction.Pressed ? Palette.Pressed.Brush() : interaction.Hover ? Palette.Hover.Brush() : Palette.Clear;
    }

    void Show()
    {
        delay.Stop();
        if (shown) return;
        shown = true;
        IsHitTestVisible = true;
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetAccessibilityView(this, Microsoft.UI.Xaml.Automation.Peers.AccessibilityView.Content);
        // The half that sticks out draws above the neighbouring tile.
        Canvas.SetZIndex(tile, 1);
        var visual = Microsoft.UI.Xaml.Hosting.ElementCompositionPreview.GetElementVisual(this);
        visual.CenterPoint = new System.Numerics.Vector3((float)Box / 2, (float)Box / 2, 0);
        if (!Motion.Reduced) { visual.StopAnimation("Scale"); visual.Scale = new System.Numerics.Vector3(0.6f, 0.6f, 1); }
        Motion.Scale(this, 1, Motion.Press);
        Motion.Fade(this, 1);
    }

    void Hide()
    {
        if (!shown) return;
        shown = false;
        IsHitTestVisible = false;
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetAccessibilityView(this, Microsoft.UI.Xaml.Automation.Peers.AccessibilityView.Raw);
        Canvas.SetZIndex(tile, 0);
        Motion.Fade(this, 0);
        Motion.Scale(this, 0.8, Motion.Snappy);
    }
}

/// <summary>A pinned tab, shown as an icon tile in the sidebar and the top strip.</summary>
public sealed partial class PinnedTile : Grid
{
    public PinnedTile(Tab tab, BrowserModel browser, double height = 44)
    {
        Height = height; Background = Palette.Clear; IsTabStop = true;
        var plate = Ui.Rounded(Radius.Row);
        Children.Add(plate);
        Children.Add(new TabIcon(tab, 20) { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center });
        var badge = new TileCloseBadge(this, tab, browser);
        Interaction? interaction = null;
        void Render()
        {
            var selected = browser.SelectedId == tab.Id;
            plate.Background = selected ? Palette.Selected.Brush() : interaction?.Hover == true ? Palette.Pressed.Brush() : Palette.Hover.Brush();
            plate.BorderBrush = selected ? Palette.HairlineStrong.Brush() : null;
            plate.BorderThickness = new Thickness(selected ? 1 : 0);
            this.Tip(browser.Text("закреплена: ", "Закреплена: ") + tab.DisplayTitle(browser.Store));
            badge.SetLabel(browser.Text("закрыть: ", "Закрыть: ") + tab.DisplayTitle(browser.Store));
        }
        interaction = new Interaction(this, Render, 0.94, plate);
        interaction.Invoked += () => browser.Select(tab);
        TabInteractions.Attach(this, tab, browser);
        this.Bind(browser, Render); this.Bind(tab, Render);
        Motion.AnimateLayoutMoves(this, Motion.Snappy);
    }
}

/// <summary>Site icon of a tab in the collapsed sidebar: the same filled 36 px plate as the plus below, with the
/// favicon or a plain monogram inside instead of a nested box.</summary>
public sealed partial class RailTile : Grid
{
    public RailTile(Tab tab, BrowserModel browser)
    {
        Width = 36; Height = 36; Background = Palette.Clear; IsTabStop = true; HorizontalAlignment = HorizontalAlignment.Center;
        var plate = Ui.Rounded(Radius.Row, Palette.Hover.Brush());
        var icon = new TabIcon(tab, 20, plain: true) { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        Children.Add(plate);
        Children.Add(icon);
        var pin = new Glyph("pin", 8, Palette.Ink.Brush()) { HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Top, IsHitTestVisible = false };
        Children.Add(pin);
        var badge = new TileCloseBadge(this, tab, browser);
        Interaction? interaction = null;
        void Render()
        {
            var selected = browser.SelectedId == tab.Id;
            var hover = interaction?.Hover == true;
            plate.Background = selected ? Palette.Selected.Brush() : hover ? Palette.Pressed.Brush() : Palette.Hover.Brush();
            plate.Shadow = selected ? Shadows.Soft : null;
            icon.SetTint(selected || hover ? Palette.Ink.Brush() : Palette.Text2.Brush());
            Motion.Fade(pin, tab.Pinned && !hover ? 1 : 0);
            this.Tip((tab.Pinned ? browser.Text("закреплена: ", "Закреплена: ") : "") + tab.DisplayTitle(browser.Store));
            badge.SetLabel(browser.Text("закрыть: ", "Закрыть: ") + tab.DisplayTitle(browser.Store));
        }
        interaction = new Interaction(this, Render, 0.92, plate);
        interaction.Invoked += () => browser.Select(tab);
        TabInteractions.Attach(this, tab, browser);
        this.Bind(browser, Render); this.Bind(tab, Render);
        Motion.AnimateLayoutMoves(this, Motion.Snappy);
    }
}

/// <summary>Square plus used by the rail and the top strip.</summary>
public sealed partial class PlusTile : Grid
{
    public PlusTile(BrowserModel browser, double width = 36, double height = 36)
    {
        Width = width; Height = height; Background = Palette.Clear; IsTabStop = true;
        var plate = Ui.Rounded(Radius.Row, Palette.Hover.Brush());
        var glyph = new Glyph("plus", 13, Palette.Text2.Brush()) { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        Children.Add(plate); Children.Add(glyph);
        Interaction? interaction = null;
        interaction = new Interaction(this, () => { plate.Background = interaction!.Hover ? Palette.Pressed.Brush() : Palette.Hover.Brush(); glyph.Foreground = interaction.Hover ? Palette.Ink.Brush() : Palette.Text2.Brush(); }, 0.92);
        interaction.Invoked += () => { browser.Add(); browser.FocusAddress(); };
        this.Tip(browser.Text("новая вкладка", "Новая вкладка") + (Keymap.Label("tab") is { } k ? " " + k : ""));
    }
}

public sealed partial class NewTabRow : Grid
{
    public NewTabRow(BrowserModel browser)
    {
        Height = 32; Background = Palette.Clear; IsTabStop = true;
        var plate = Ui.Rounded(Radius.Row);
        var glyph = new Glyph("plus", 12, Palette.Text2.Brush()) { Width = 18 };
        var text = Ui.Text(browser.Text("новая вкладка", "Новая вкладка"), 12.5, Palette.Text2.Brush());
        var hint = KeyHint.Make(Keymap.Label("tab") ?? "Ctrl+T"); hint.Opacity = 0; hint.HorizontalAlignment = HorizontalAlignment.Right; hint.Margin = new Thickness(0, 0, 8, 0);
        var row = Ui.H(10, glyph, text); row.Margin = new Thickness(8, 0, 8, 0);
        Children.Add(plate); Children.Add(row); Children.Add(hint);
        Interaction? interaction = null;
        interaction = new Interaction(this, () =>
        {
            var hover = interaction!.Hover;
            plate.Background = hover ? Palette.Hover.Brush() : Palette.Clear;
            text.Foreground = glyph.Foreground = hover ? Palette.Ink.Brush() : Palette.Text2.Brush();
            Motion.Fade(hint, hover ? 1 : 0);
        }, 0.98);
        interaction.Invoked += () => { browser.Add(); browser.FocusAddress(); };
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(this, browser.Text("новая вкладка", "Новая вкладка"));
    }
}

/// <summary>Keeps a panel's children in step with a keyed list: new items pop in, removed ones fade out, moved ones
/// spring to their place through implicit offset animations.</summary>
public static class Reconcile
{
    /// <summary>Elements carry their key in Tag; a leaving element is marked so it is not reused while it fades.</summary>
    public static void Run(Microsoft.UI.Xaml.Controls.Panel panel, IReadOnlyList<string> keys, Func<string, FrameworkElement> make, int offset = 0)
    {
        var existing = new Dictionary<string, FrameworkElement>();
        foreach (var e in panel.Children.OfType<FrameworkElement>()) if (e.Tag is string key && !key.StartsWith("leaving:", StringComparison.Ordinal)) existing[key] = e;
        foreach (var (key, element) in existing)
            if (!keys.Contains(key)) { element.Tag = "leaving:" + key; Motion.Disappear(element, () => panel.Children.Remove(element)); }
        for (var i = 0; i < keys.Count; i++)
        {
            var key = keys[i];
            if (!existing.TryGetValue(key, out var element))
            {
                element = make(key); element.Tag = key;
                panel.Children.Insert(Math.Min(offset + i, panel.Children.Count), element);
                Motion.Appear(element);
                continue;
            }
            var current = panel.Children.IndexOf(element);
            var target = Math.Min(offset + i, panel.Children.Count - 1);
            if (current != target) panel.Children.Move((uint)current, (uint)target);
        }
    }
}

/// <summary>Sidebar with pinned tiles, the new-tab row, the tab list and the footer controls; collapsed it becomes
/// a rail of site icons (macOS Sidebar).</summary>
public sealed partial class Sidebar : Grid
{
    readonly BrowserModel browser; readonly bool compact; readonly TabLayout edge;
    readonly VariableSizedWrapGrid pinned = new() { Orientation = Orientation.Horizontal, ItemHeight = 50, ItemWidth = 58 };
    readonly StackPanel pinnedRail = new() { Spacing = 6 };
    readonly StackPanel regular = new() { Spacing = 2 };
    readonly StackPanel footer = new() { Spacing = 2 };
    readonly Grid extensions = new();
    string footerKey = "";

    public Sidebar(BrowserModel browser, bool compact, TabLayout edge)
    {
        this.browser = browser; this.compact = compact; this.edge = edge;
        var store = browser.Store;
        Background = Palette.Clear;
        RowDefinitions.Add(Ui.RowAuto()); RowDefinitions.Add(Ui.RowAuto()); RowDefinitions.Add(Ui.RowAuto()); RowDefinitions.Add(Ui.RowStar()); RowDefinitions.Add(Ui.RowAuto()); RowDefinitions.Add(Ui.RowAuto());
        if (compact)
        {
            Width = Chrome.Rail; Padding = new Thickness(0, 0, 0, Space.Small);
            regular.Spacing = 6; footer.HorizontalAlignment = HorizontalAlignment.Center;
            this.Row(pinnedRail, 0);
            // The scroll viewer clips; it reaches up by the close badge overhang so the first tile's badge is whole.
            // The pinned column leaves that much room below it, so the scroll viewer never lies over a pinned tile.
            pinnedRail.Margin = new Thickness(0, 0, 0, TileCloseBadge.Overhang);
            regular.Padding = new Thickness(0, TileCloseBadge.Overhang, 0, 0);
            var scroll = Ui.Scroll(regular); scroll.VerticalScrollBarVisibility = ScrollBarVisibility.Hidden;
            scroll.Margin = new Thickness(0, -TileCloseBadge.Overhang, 0, 0);
            this.Row(scroll, 3);
        }
        else
        {
            Padding = new Thickness(Space.Small, 0, Space.Small, Space.Small);
            RowSpacing = Space.Small;
            footer.Orientation = Orientation.Horizontal;
            this.Row(pinned, 0);
            this.Row(new NewTabRow(browser), 1);
            this.Row(Ui.Hairline().Margin(Space.Small, 0, Space.Small, 0), 2);
            var scroll = Ui.Scroll(regular); scroll.VerticalScrollBarVisibility = ScrollBarVisibility.Hidden;
            this.Row(scroll, 3);
        }
        this.Row(extensions, 4);
        this.Row(footer, 5);
        this.ContextMenu(() => browser.CustomizingToolbar ? [] :
        [
            MenuEntry.Item(browser.Text("новая вкладка", "Новая вкладка"), () => { browser.Add(); browser.FocusAddress(); }, "plus"),
            MenuEntry.Item(browser.Prefs.SidebarCollapsed ? browser.Text("развернуть боковую панель", "Развернуть боковую панель") : browser.Text("свернуть боковую панель", "Свернуть боковую панель"), () => store.Change(p => p.SidebarCollapsed = !p.SidebarCollapsed), edge == TabLayout.Right ? "sidebar.right" : "sidebar.left"),
            MenuEntry.Separator, .. LayoutMenu.Entries(store), MenuEntry.Separator,
            MenuEntry.Item(store.Text("настроить панель инструментов…", "Настроить панель инструментов…"), () => browser.CustomizingToolbar = true, "slider.horizontal.3"),
        ]);
        this.Bind(browser, Render);
        this.Bind(h => store.PreferencesUpdated += h, h => store.PreferencesUpdated -= h, Render);
        this.Bind(h => store.Extensions.Changed += h, h => store.Extensions.Changed -= h, Render);
    }

    void Render()
    {
        var store = browser.Store;
        var pinnedTabs = browser.Tabs.Where(t => t.Pinned).Select(t => t.Id.ToString()).ToList();
        var regularTabs = browser.Tabs.Where(t => !t.Pinned).Select(t => t.Id.ToString()).ToList();
        Tab Find(string key) => browser.Tabs.First(t => t.Id.ToString() == key);
        if (compact)
        {
            Reconcile.Run(pinnedRail, pinnedTabs, key => new RailTile(Find(key), browser));
            if (regular.Children.LastOrDefault() is not PlusTile) regular.Children.Add(new PlusTile(browser));
            Reconcile.Run(regular, regularTabs, key => new RailTile(Find(key), browser));
            if (regular.Children.LastOrDefault() is not PlusTile) { var plus = regular.Children.OfType<PlusTile>().FirstOrDefault(); if (plus is not null) regular.Children.Move((uint)regular.Children.IndexOf(plus), (uint)(regular.Children.Count - 1)); }
        }
        else
        {
            pinned.Visibility = pinnedTabs.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
            Reconcile.Run(pinned, pinnedTabs, key => new PinnedTile(Find(key), browser) { Width = 52, Margin = new Thickness(3) });
            Reconcile.Run(regular, regularTabs, key => new TabRow(Find(key), browser, horizontal: false));
        }
        var items = browser.Prefs.Toolbar.Resolve(sidebarAvailable: true).Sidebar;
        var key = string.Join(",", items) + browser.CustomizingToolbar;
        if (key == footerKey) return;
        footerKey = key;
        footer.Children.Clear(); extensions.Children.Clear();
        if (browser.CustomizingToolbar)
        {
            footer.Children.Add(new ToolbarDropZone(ToolbarZone.Sidebar, items, browser, edge, compact ? HorizontalAlignment.Center : HorizontalAlignment.Left, vertical: compact));
            return;
        }
        if (items.Contains(ToolbarControl.Extensions)) extensions.Children.Add(Extensions.ExtensionButtons.Strip(browser, vertical: compact));
        foreach (var item in items) foreach (var button in ToolbarButton.Make(item, browser, edge, inSidebar: true)) footer.Children.Add(button);
    }
}

/// <summary>Horizontal tabs share the width evenly; the new-tab button sits right after the last tab. In the caption band
/// (titleBand) the strip keeps free space at its end, where the window can still be dragged.</summary>
public sealed partial class TabStrip : Grid
{
    readonly BrowserModel browser;
    readonly StackPanel row = new() { Orientation = Orientation.Horizontal, Spacing = Space.Micro };
    readonly PlusTile plus;
    readonly ScrollViewer scroll;
    readonly bool titleBand;
    /// <summary>Empty caption band left after the tabs, so the window always has somewhere to be dragged by.</summary>
    const double DragRoom = 64;
    /// <summary>The tabs and the plus button: in the caption band this area passes clicks through, the rest drags.</summary>
    public FrameworkElement Tabs => scroll;
    public TabStrip(BrowserModel browser, bool titleBand = false)
    {
        this.browser = browser;
        this.titleBand = titleBand;
        Height = titleBand ? BrowserWindow.Bar : 32 + TileCloseBadge.Overhang * 2;
        plus = new PlusTile(browser, 32, 32);
        scroll = Ui.Scroll(row, horizontal: true); scroll.HorizontalScrollBarVisibility = ScrollBarVisibility.Hidden;
        scroll.Padding = new Thickness(0, (Height - 32) / 2, 0, (Height - 32) / 2);
        if (titleBand) scroll.HorizontalAlignment = HorizontalAlignment.Left;
        Children.Add(scroll);
        row.Children.Add(plus);
        // Under the address the free space after the tabs opens the strip menu (macOS TabStrip.menu); a tab handles
        // its own menu first. In the caption band that space belongs to the window, whose system menu opens there.
        if (!titleBand) Background = Palette.Clear;
        this.ContextMenu(() => browser.CustomizingToolbar ? [] : Menu(browser));
        this.Bind(browser, Render);
        SizeChanged += (_, _) => Render();
    }

    /// <summary>Menu of the strip's free space: a new tab, the tab layout and the toolbar editor.</summary>
    public static List<MenuEntry> Menu(BrowserModel browser) =>
    [
        MenuEntry.Item(browser.Text("новая вкладка", "Новая вкладка"), () => { browser.Add(); browser.FocusAddress(); }, "plus", shortcut: Keymap.Label("tab")),
        MenuEntry.Separator, .. LayoutMenu.Entries(browser.Store), MenuEntry.Separator,
        MenuEntry.Item(browser.Store.Text("настроить панель инструментов…", "Настроить панель инструментов…"), () => browser.CustomizingToolbar = true, "slider.horizontal.3"),
    ];
    void Render()
    {
        var regularCount = browser.Tabs.Count;
        var available = ActualWidth - (titleBand ? DragRoom : 0);
        var fixedWidth = 32 + browser.Tabs.Count * Space.Micro;
        var width = regularCount == 0 ? 0 : Math.Min(240, Math.Max(130, (available - fixedWidth) / regularCount));
        if (titleBand && ActualWidth > 0) scroll.Width = Math.Max(0, Math.Min(fixedWidth + regularCount * width, available));
        Reconcile.Run(row, browser.Tabs.Select(t => t.Id.ToString()).ToList(), key =>
        {
            var tab = browser.Tabs.First(t => key.StartsWith(t.Id.ToString(), StringComparison.Ordinal));
            return new TabRow(tab, browser, horizontal: true) { Width = width };
        });
        foreach (var r in row.Children.OfType<TabRow>()) r.Width = width;
        var index = row.Children.IndexOf(plus);
        if (index != row.Children.Count - 1) row.Children.Move((uint)index, (uint)(row.Children.Count - 1));
    }
}

/// <summary>A site's stored favicon, or its monogram until an icon is known (macOS SiteIcon). Tiled, for list rows, the
/// icon sits at 60 % on the same plate as the monogram; untiled it fills the size, as on start page tiles. The icon
/// fades in over the monogram it replaces; opacity only, so Reduce Motion keeps it.</summary>
public sealed partial class SiteIcon : Grid
{
    readonly string url; readonly Favicons favicons; readonly double size; readonly bool tiled;
    ImageSource? shown;
    bool rendered;
    public SiteIcon(string url, Favicons favicons, double size, bool tiled = false)
    {
        this.url = url; this.favicons = favicons; this.size = size; this.tiled = tiled;
        Width = size; Height = size; IsHitTestVisible = false;
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetAccessibilityView(this, Microsoft.UI.Xaml.Automation.Peers.AccessibilityView.Raw);
        this.Bind(h => favicons.Changed += h, h => favicons.Changed -= h, Render);
    }
    void Render()
    {
        var image = favicons.Image(url);
        if (rendered && ReferenceEquals(image, shown)) return;
        var arrived = rendered && shown is null && image is not null;
        rendered = true; shown = image;
        Children.Clear();
        if (image is null) { Children.Add(new Monogram(AddressParser.Host(url), size)); return; }
        var side = tiled ? Math.Round(size * 0.6) : size;
        if (tiled) Children.Add(Ui.Rounded(size * 0.3, Palette.Track.Brush()));
        var icon = new Border { Width = side, Height = side, CornerRadius = new CornerRadius(side * 0.2), Background = new ImageBrush { ImageSource = image, Stretch = Stretch.Uniform }, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        Children.Add(icon);
        if (arrived) { Microsoft.UI.Xaml.Hosting.ElementCompositionPreview.GetElementVisual(icon).Opacity = 0; Motion.Fade(icon, 1); }
    }
}
