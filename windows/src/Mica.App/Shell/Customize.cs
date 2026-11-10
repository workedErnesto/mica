using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Mica.Core;
using Mica.Design;
using Windows.ApplicationModel.DataTransfer;

namespace Mica.App;

/// <summary>Toolbar customization on the real window: zones in the bar and the sidebar footer, a palette over the
/// page. Drag a control into a zone, onto another control to put it before that one, or back onto the palette to
/// remove it; each control's context menu offers the same moves (macOS ToolbarMoves).</summary>
public static class ToolbarMoves
{
    public const string Prefix = "mica-toolbar:";
    public static string Payload(ToolbarControl item) => Prefix + item;
    public static ToolbarControl? Item(string? payload) =>
        payload is not null && payload.StartsWith(Prefix, StringComparison.Ordinal) && Enum.TryParse<ToolbarControl>(payload[Prefix.Length..], out var item) ? item : null;

    public static void Move(Store store, ToolbarControl item, ToolbarZone zone, ToolbarControl? before = null) =>
        store.Change(p => p.Toolbar.Insert(item, zone, before));

    /// <summary>In the top layout sidebar items show after the right-hand ones, so a drop at the end of the right zone joins them.</summary>
    public static void Append(Store store, ToolbarControl item, ToolbarZone zone, TabLayout layout)
    {
        if (zone == ToolbarZone.Trailing && layout.IsHorizontal() && store.ActivePrefs.Toolbar.Sidebar.Any(i => i != item)) Move(store, item, ToolbarZone.Sidebar);
        else Move(store, item, zone);
    }

    static readonly ToolbarZone[] Placements = [ToolbarZone.Leading, ToolbarZone.LeadingInner, ToolbarZone.TrailingInner, ToolbarZone.Trailing, ToolbarZone.Sidebar];

    public static IEnumerable<MenuEntry> Menu(Store store, ToolbarControl item, TabLayout layout)
    {
        var current = store.ActivePrefs.Toolbar.ZoneOf(item);
        foreach (var zone in Placements)
            yield return MenuEntry.Item(zone.Title(store), () => Move(store, item, zone), @checked: current == zone, enabled: current != zone && !(zone == ToolbarZone.Sidebar && layout.IsHorizontal()));
        yield return MenuEntry.Separator;
        yield return MenuEntry.Item(store.Text("убрать", "Убрать"), () => Move(store, item, ToolbarZone.Hidden), destructive: true, enabled: current != ToolbarZone.Hidden);
    }

    public static void MakeDraggable(UIElement element, ToolbarControl item)
    {
        element.CanDrag = true;
        element.DragStarting += (_, e) => { e.Data.SetText(Payload(item)); e.Data.RequestedOperation = DataPackageOperation.Move; };
    }

    public static async Task<ToolbarControl?> Dropped(DragEventArgs e) =>
        e.DataView.Contains(StandardDataFormats.Text) ? Item(await e.DataView.GetTextAsync()) : null;
}

/// <summary>One area that accepts controls: a side of the top bar or the bottom of the sidebar.</summary>
public sealed partial class ToolbarDropZone : Grid
{
    public ToolbarDropZone(ToolbarZone zone, IEnumerable<ToolbarControl> items, BrowserModel browser, TabLayout layout, HorizontalAlignment alignment, bool vertical = false)
    {
        var store = browser.Store;
        MinHeight = 32; MinWidth = vertical ? 36 : 64;
        var frame = Ui.Rounded(Radius.Icon + 2, Palette.Clear, Palette.HairlineStrong.Brush(), 1);
        Children.Add(frame);
        var panel = new StackPanel { Orientation = vertical ? Orientation.Vertical : Orientation.Horizontal, Spacing = 2, Padding = new Thickness(2), HorizontalAlignment = alignment, VerticalAlignment = vertical ? VerticalAlignment.Top : VerticalAlignment.Center };
        foreach (var item in items) panel.Children.Add(new ToolbarEditTile(item, browser, layout));
        Children.Add(panel);
        AllowDrop = true; Background = Palette.Clear;
        DragOver += (_, e) => { e.AcceptedOperation = DataPackageOperation.Move; frame.Background = Palette.Hover.Brush(); frame.BorderBrush = Palette.FocusRing.Brush(); };
        DragLeave += (_, _) => { frame.Background = Palette.Clear; frame.BorderBrush = Palette.HairlineStrong.Brush(); };
        Drop += async (_, e) =>
        {
            frame.Background = Palette.Clear; frame.BorderBrush = Palette.HairlineStrong.Brush();
            if (await ToolbarMoves.Dropped(e) is { } dragged) ToolbarMoves.Append(store, dragged, zone, layout);
        };
        this.Tip(zone.Title(store));
    }
}

/// <summary>A control as it looks while customizing: live size, draggable, with an insertion caret while another
/// control hovers over it.</summary>
public sealed partial class ToolbarEditTile : Grid
{
    public ToolbarEditTile(ToolbarControl item, BrowserModel browser, TabLayout layout)
    {
        var store = browser.Store;
        Width = 28; Height = 28;
        var fill = Ui.Rounded(Radius.Icon, Palette.Hover.Brush());
        var caret = Ui.Rounded(1, Look.Focus); caret.Width = 2; caret.Height = 22; caret.HorizontalAlignment = HorizontalAlignment.Left; caret.Margin = new Thickness(-2, 0, 0, 0); caret.Opacity = 0;
        Children.Add(fill);
        Children.Add(new Glyph(item == ToolbarControl.Sidebar && layout == TabLayout.Right ? "sidebar.right" : item.Symbol(), 13.5) { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center });
        Children.Add(caret);
        PointerEntered += (_, _) => fill.Background = Palette.Pressed.Brush();
        PointerExited += (_, _) => fill.Background = Palette.Hover.Brush();
        ToolbarMoves.MakeDraggable(this, item);
        AllowDrop = true;
        DragOver += (_, e) => { e.AcceptedOperation = DataPackageOperation.Move; caret.Opacity = 1; e.Handled = true; };
        DragLeave += (_, _) => caret.Opacity = 0;
        Drop += async (_, e) =>
        {
            caret.Opacity = 0; e.Handled = true;
            if (await ToolbarMoves.Dropped(e) is { } dragged && dragged != item) ToolbarMoves.Move(store, dragged, browser.Prefs.Toolbar.ZoneOf(item), item);
        };
        this.ContextMenu(() => ToolbarMoves.Menu(store, item, layout));
        this.Tip(item.Title(store));
    }
}

/// <summary>The palette over the page: every control, the address field length and the finish action.</summary>
public sealed partial class CustomizeToolbarPanel : Grid
{
    public CustomizeToolbarPanel(BrowserModel browser)
    {
        var store = browser.Store;
        var layout = browser.Prefs.Layout;
        MaxWidth = 820;
        var content = new StackPanel { Spacing = Space.Section, Padding = new Thickness(Space.Section) };
        content.Children.Add(Ui.V(4,
            Ui.Text(store.Text("перетащите кнопки на панель", "Перетащите кнопки на панель"), 15, null, Ui.Medium),
            Ui.Text(layout.IsHorizontal()
                ? store.Text("в шапке четыре места: у краёв окна и рядом с адресом. чтобы убрать кнопку, верните её сюда.", "В шапке четыре места: у краёв окна и рядом с адресом. Чтобы убрать кнопку, верните её сюда.")
                : store.Text("в шапке четыре места: у краёв окна и рядом с адресом, ещё одно внизу боковой панели. чтобы убрать кнопку, верните её сюда.", "В шапке четыре места: у краёв окна и рядом с адресом, ещё одно внизу боковой панели. Чтобы убрать кнопку, верните её сюда."), 12, Palette.Text3.Brush(), wrap: true)));
        var tiles = new VariableSizedWrapGrid { Orientation = Orientation.Horizontal, ItemWidth = 112, ItemHeight = 92 };
        var tray = Ui.Rounded(Radius.Panel - 4, new SolidColorBrush(Palette.WithAlpha(Palette.Track.Resolve(), Palette.Track.Resolve().A / 255.0 * 0.5)), null, 0, tiles);
        tray.Padding = new Thickness(Space.Small);
        content.Children.Add(tray);
        var slider = new MSlider(browser.Prefs.Toolbar.AddressWidth, ToolbarLayout.AddressMin, ToolbarLayout.AddressMax, store.Text("длина адресной строки", "Длина адресной строки")) { Width = 180 };
        var value = Ui.Text(Math.Round(browser.Prefs.Toolbar.AddressWidth) + " px", 11.5, Palette.Text3.Brush());
        slider.Changed += v => { value.Text = Math.Round(v) + " px"; store.Change(p => p.Toolbar.AddressWidth = v); };
        content.Children.Add(Ui.H(Space.Normal, Ui.Text(store.Text("длина адресной строки", "Длина адресной строки"), 12.5, Palette.Text2.Brush()), slider, value));
        var reset = new MButton(store.Text("вернуть как было", "Вернуть как было"), ButtonKind.Ghost);
        reset.Click += () => store.Change(p => p.Toolbar = new ToolbarLayout().Sanitized());
        var done = new MButton(store.Text("готово", "Готово"), ButtonKind.Primary) { HorizontalAlignment = HorizontalAlignment.Right };
        done.Click += () => browser.CustomizingToolbar = false;
        var actions = new Grid(); actions.ColumnDefinitions.Add(Ui.Auto()); actions.ColumnDefinitions.Add(Ui.Star()); actions.ColumnDefinitions.Add(Ui.Auto());
        actions.Column(reset, 0); actions.Column(done, 2);
        content.Children.Add(actions);
        var scroll = Ui.Scroll(content);
        var surface = Ui.Raised(scroll);
        Children.Add(surface);
        void Render()
        {
            tiles.Children.Clear();
            foreach (var item in ToolbarLayout.AllControls) tiles.Children.Add(new PaletteTile(item, browser.Prefs.Toolbar.ZoneOf(item), browser, layout));
            reset.IsEnabled = !Same(browser.Prefs.Toolbar, new ToolbarLayout().Sanitized());
        }
        this.Bind(h => store.PreferencesUpdated += h, h => store.PreferencesUpdated -= h, Render);
        AllowDrop = true;
        DragOver += (_, e) => { e.AcceptedOperation = DataPackageOperation.Move; tray.BorderBrush = Palette.FocusRing.Brush(); tray.BorderThickness = new Thickness(1); };
        DragLeave += (_, _) => tray.BorderThickness = new Thickness(0);
        Drop += async (_, e) => { tray.BorderThickness = new Thickness(0); if (await ToolbarMoves.Dropped(e) is { } dragged) ToolbarMoves.Move(store, dragged, ToolbarZone.Hidden); };
        KeyDown += (_, e) => { if (e.Key == Windows.System.VirtualKey.Escape) browser.CustomizingToolbar = false; };
    }

    static bool Same(ToolbarLayout a, ToolbarLayout b) => a.Leading.SequenceEqual(b.Leading) && a.LeadingInner.SequenceEqual(b.LeadingInner) && a.TrailingInner.SequenceEqual(b.TrailingInner) && a.Trailing.SequenceEqual(b.Trailing) && a.Sidebar.SequenceEqual(b.Sidebar) && a.AddressWidth == b.AddressWidth;

    sealed partial class PaletteTile : Grid
    {
        public PaletteTile(ToolbarControl item, ToolbarZone zone, BrowserModel browser, TabLayout layout)
        {
            var store = browser.Store;
            var placed = zone != ToolbarZone.Hidden;
            Margin = new Thickness(2);
            var hover = Ui.Rounded(Radius.Row);
            var plate = Ui.Rounded(Radius.Icon, placed ? Palette.Clear : Palette.Surface.Brush(), placed ? Palette.HairlineStrong.Brush() : Palette.Hairline.Brush(), 1,
                new Glyph(item.Symbol(), 14, placed ? Palette.Text3.Brush() : Palette.Ink.Brush()) { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center });
            plate.Width = 40; plate.Height = 32; plate.HorizontalAlignment = HorizontalAlignment.Center;
            var title = Ui.Text(item.Title(store), 11.5); title.HorizontalAlignment = HorizontalAlignment.Center;
            var where = Ui.Text(placed ? zone.Title(store) : store.Text("можно добавить", "Можно добавить"), 10.5, Palette.Text3.Brush()); where.HorizontalAlignment = HorizontalAlignment.Center;
            var stack = Ui.V(6, plate, Ui.V(1, title, where));
            stack.Padding = new Thickness(4, Space.Small, 4, Space.Small);
            Children.Add(hover); Children.Add(stack);
            Background = Palette.Clear;
            PointerEntered += (_, _) => hover.Background = Palette.Hover.Brush();
            PointerExited += (_, _) => hover.Background = Palette.Clear;
            ToolbarMoves.MakeDraggable(this, item);
            this.ContextMenu(() => ToolbarMoves.Menu(store, item, layout));
            Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(this, item.Title(store) + ", " + zone.Title(store));
        }
    }
}
