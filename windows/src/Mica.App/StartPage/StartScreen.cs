using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Media;
using Mica.Core;
using Mica.Design;
using Windows.ApplicationModel.DataTransfer;

namespace Mica.App.StartPage;

public sealed record StartSite(string Id, string Title, string Url, Guid? Shortcut = null)
{
    public string Host => AddressParser.Host(Url) ?? Url;
}

public static class StartSections
{
    public static string Title(this StartSection section, Store s) => section switch
    {
        StartSection.Custom => s.Text("свои сайты", "Свои сайты"), StartSection.Frequent => s.Text("часто открываете", "Часто открываете"), _ => s.Text("закладки", "Закладки"),
    };
}

/// <summary>Start page (macOS StartScreen): wordmark or greeting, search field with suggestions, site sections in
/// the user's order, and live customizing in place.</summary>
public sealed partial class StartScreen : Grid
{
    readonly BrowserModel browser;
    Store Store => browser.Store;
    readonly int seed = Random.Shared.Next(1000);
    readonly StackPanel column = new() { Spacing = 28, MaxWidth = 600, Padding = new Thickness(Space.Large, 96, Space.Large, 64) };
    readonly TextBox field;
    readonly SuggestionList suggestions;
    readonly Grid suggestionHost = new();
    readonly Border fieldSurface;
    readonly Grid corner = new() { HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Bottom, Margin = new Thickness(Space.Normal) };
    readonly StackPanel body = new() { Spacing = 28 };
    readonly Grid header = new();
    bool focused;

    public StartScreen(BrowserModel browser)
    {
        this.browser = browser;
        Background = Palette.Canvas.Brush();
        field = MTextField.Bare(new TextBox { FontSize = 16 });
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(field, browser.Text("адресная строка", "Адресная строка"));
        suggestions = new SuggestionList(item => item.Activate(browser)) { Margin = new Thickness(Radius.PanelPadding) };
        var row = new Grid { Height = 54, Padding = new Thickness(18, 0, 18, 0), ColumnSpacing = 12 };
        row.ColumnDefinitions.Add(Ui.Auto()); row.ColumnDefinitions.Add(Ui.Star()); row.ColumnDefinitions.Add(Ui.Auto());
        row.Column(new Glyph("magnifyingglass", 15, Palette.Text2.Brush()) { VerticalAlignment = VerticalAlignment.Center }, 0);
        row.Column(field, 1);
        var hint = KeyHint.Make(Keymap.Label("address") ?? "Ctrl+L");
        row.Column(hint, 2);
        fieldSurface = Ui.Rounded(Radius.Panel, Palette.Surface.Brush(), Palette.Hairline.Brush(), 1, Ui.V(0, row, suggestionHost));
        fieldSurface.Shadow = Shadows.Soft; fieldSurface.Translation = new System.Numerics.Vector3(0, 0, 6);
        field.GotFocus += (_, _) => { focused = true; Motion.Fade(hint, 0); fieldSurface.BorderBrush = Palette.HairlineStrong.Brush(); fieldSurface.Translation = new System.Numerics.Vector3(0, 0, 16); UpdateSuggestions(); };
        field.LostFocus += (_, _) => { focused = false; Motion.Fade(hint, 1); fieldSurface.BorderBrush = Palette.Hairline.Brush(); fieldSurface.Translation = new System.Numerics.Vector3(0, 0, 6); };
        field.TextChanged += (_, _) => { UpdateSuggestions(); RenderBody(); };
        field.KeyDown += (_, e) =>
        {
            if (e.Key == Windows.System.VirtualKey.Down) { suggestions.Move(1); e.Handled = true; }
            else if (e.Key == Windows.System.VirtualKey.Up) { suggestions.Move(-1); e.Handled = true; }
            else if (e.Key == Windows.System.VirtualKey.Enter)
            {
                var items = suggestions.Items;
                if (items.Count > suggestions.Highlighted && (suggestions.Highlighted > 0 || items[0].Kind is SuggestionKind.Open or SuggestionKind.Search)) items[suggestions.Highlighted].Activate(browser);
                else if (field.Text.Length > 0) browser.Navigate(field.Text);
                e.Handled = true;
            }
            else if (e.Key == Windows.System.VirtualKey.Escape && browser.CustomizingStart) { browser.CustomizingStart = false; e.Handled = true; }
        };
        column.Children.Add(header);
        column.Children.Add(fieldSurface);
        column.Children.Add(body);
        var scroll = Ui.Scroll(column); scroll.VerticalScrollBarVisibility = ScrollBarVisibility.Hidden;
        Children.Add(scroll);
        Children.Add(corner);
        browser.FocusAddressRequested += FocusField;
        Unloaded += (_, _) => { browser.FocusAddressRequested -= FocusField; browser.CustomizingStart = false; };
        Loaded += (_, _) => FocusField();
        this.Bind(browser, Render);
        this.Bind(h => Store.PreferencesUpdated += h, h => Store.PreferencesUpdated -= h, Render);
        this.Bind(h => Store.BookmarksChanged += h, h => Store.BookmarksChanged -= h, Render);
    }

    void FocusField() => DispatcherQueue.TryEnqueue(() => field.Focus(FocusState.Programmatic));

    void UpdateSuggestions()
    {
        suggestions.Set(browser.CustomizingStart ? [] : Suggestion.Make(field.Text, browser));
        suggestionHost.Children.Clear();
        if (suggestions.Items.Count > 0 && focused) suggestionHost.Children.Add(Ui.V(0, Ui.Hairline(), suggestions));
    }

    string signature = "";

    void Render()
    {
        var editing = browser.CustomizingStart;
        field.PlaceholderText = browser.Text("поиск в ", "Поиск в ") + Store.Preferences.Search.Title(Store.Preferences.Language) + browser.Text(" или адрес", " или адрес");
        fieldSurface.Opacity = editing ? 0.5 : 1; fieldSurface.IsHitTestVisible = !editing;
        column.Padding = new Thickness(Space.Large, 96, Space.Large, editing ? 128 : 64);
        var start = Store.Preferences.Start;
        var key = $"{editing}|{start.Wordmark}|{string.Join(",", start.Sections)}|{start.FrequentCount}|{start.Shortcuts.Count}|{string.Join(",", start.Shortcuts.Select(s => s.Id + s.Title + s.Url))}|{start.HiddenHosts.Count}|{Store.Bookmarks.Count}|{Store.Preferences.UserName}|{Store.Preferences.GreetByName}|{Store.Preferences.Lowercase}|{Store.Preferences.Language}";
        if (key == signature) return;
        signature = key;
        RenderHeader(editing);
        RenderBody();
        corner.Children.Clear();
        if (editing)
        {
            var bar = new StartCustomizeBar(browser) { HorizontalAlignment = HorizontalAlignment.Center };
            corner.HorizontalAlignment = HorizontalAlignment.Stretch;
            corner.Children.Add(bar);
            Motion.Appear(bar, Motion.Edge.Bottom, Motion.Panel);
        }
        else
        {
            corner.HorizontalAlignment = HorizontalAlignment.Right;
            var customize = new MButton(Store.Text("настроить", "Настроить"), ButtonKind.Ghost, compact: true).Tip(Store.Text("настроить начальную страницу", "Настроить начальную страницу"));
            customize.Click += () => browser.CustomizingStart = true;
            corner.Children.Add(customize);
        }
    }

    void RenderHeader(bool editing)
    {
        header.Children.Clear();
        var options = Store.Preferences.Start;
        var greeting = Greeting.Text(Store.Preferences, DateTime.Now.Hour, seed);
        var line = Ui.H(10); line.HorizontalAlignment = HorizontalAlignment.Center;
        if (options.Wordmark || editing)
        {
            var text = greeting is null ? Ui.Text("mica", 40, null, Ui.Weight(300)) : Ui.Text(greeting, 34, null, Ui.Weight(300), wrap: true);
            text.CharacterSpacing = greeting is null ? -40 : -32; text.TextAlignment = TextAlignment.Center; text.MaxLines = 2;
            if (editing)
            {
                // While customizing the greeting gets the same title row as the sections, so the switch never covers the text.
                text.Opacity = options.Wordmark ? 1 : 0.4;
                text.HorizontalAlignment = HorizontalAlignment.Center; text.Margin = new Thickness(StartLayout.Inset, 0, StartLayout.Inset, 0);
                var title = new StartBlockHeader(greeting is null ? Store.Text("знак mica", "Знак mica") : Store.Text("приветствие", "Приветствие"), true, options.Wordmark, Store, on => Store.Change(p => p.Start.Wordmark = on));
                header.Children.Add(new StartEditFrame(Ui.V(Space.Normal, title, text), true));
                return;
            }
            line.Children.Add(text);
        }
        if (browser.PrivateMode && !editing)
        {
            var badge = Ui.Rounded(12, Palette.Track.Brush(), child: Ui.H(6, new Glyph(Glyph.Incognito, 11.5, Palette.Text2.Brush()), Ui.Text(browser.Text("инкогнито", "Инкогнито"), 11.5, Palette.Text2.Brush(), Ui.Medium)));
            badge.Padding = new Thickness(10, 0, 10, 0); badge.Height = 24; badge.VerticalAlignment = VerticalAlignment.Center;
            line.Children.Add(badge);
        }
        if (line.Children.Count > 0) header.Children.Add(line);
    }

    void RenderBody()
    {
        body.Children.Clear();
        var editing = browser.CustomizingStart;
        if (field.Text.Length > 0 && !editing) return;
        var sections = Sections(editing);
        if (sections.Count == 0)
        {
            var hints = Ui.H(Space.Section,
                Hint(Keymap.Label("tab") ?? "Ctrl+T", browser.Text("вкладка", "Вкладка")),
                Hint(Keymap.Label("private") ?? "Ctrl+Shift+N", browser.Text("инкогнито", "Инкогнито")),
                Hint(Keymap.Label("sidebar") ?? "Ctrl+Shift+S", browser.Text("боковая панель", "Боковая панель")));
            hints.HorizontalAlignment = HorizontalAlignment.Center;
            body.Children.Add(hints);
        }
        foreach (var (section, sites) in sections) body.Children.Add(new StartSectionView(section, sites, browser, editing));
        if (browser.PrivateMode && !editing)
        {
            var note = Ui.Text(browser.Text("история и сессия этого окна не сохраняются. загруженные файлы остаются на диске.", "История и сессия этого окна не сохраняются. Загруженные файлы остаются на диске."), 12, Palette.Text3.Brush(), wrap: true);
            note.TextAlignment = TextAlignment.Center;
            body.Children.Add(note);
        }
    }

    static StackPanel Hint(string keys, string title) => Ui.H(6, KeyHint.Make(keys), Ui.Text(title, 12, Palette.Text3.Brush()));

    /// <summary>Sections in the user's order. Frequent sites never come from history in a private window; empty
    /// sections are skipped except custom sites; while customizing every section is listed, hidden ones last.</summary>
    List<(StartSection, List<StartSite>)> Sections(bool editing)
    {
        var options = Store.Preferences.Start;
        var order = editing ? options.Sections.Concat(Enum.GetValues<StartSection>().Where(s => !options.Sections.Contains(s))).ToList() : options.Sections;
        var result = new List<(StartSection, List<StartSite>)>();
        foreach (var section in order)
        {
            List<StartSite> sites;
            switch (section)
            {
                case StartSection.Custom:
                    result.Add((section, options.Shortcuts.Select(s => new StartSite(s.Id.ToString(), s.Title, s.Url, s.Id)).ToList()));
                    continue;
                case StartSection.Frequent:
                    if (browser.PrivateMode) sites = [];
                    else
                    {
                        var pinned = options.Shortcuts.Select(s => AddressParser.Host(s.Url)?.ToLowerInvariant()).OfType<string>().ToHashSet();
                        pinned.UnionWith(options.HiddenHosts);
                        sites = Mica.Core.StartPage.Frequent(Store.History, pinned, options.FrequentCount).Select(v => new StartSite("f-" + v.Host, "", v.Url)).ToList();
                    }
                    break;
                default:
                    sites = Store.Bookmarks.Take(options.FrequentCount).Select(v => new StartSite("b-" + v.Id, v.Title, v.Url)).ToList();
                    break;
            }
            if (sites.Count > 0 || editing) result.Add((section, sites));
        }
        return result;
    }
}

/// <summary>Start page block geometry (macOS StartLayout): tiles sit in 88 px columns with a 4 px gap, so a 60 px
/// icon is inset 14 px; block titles and their controls use the same inset, and the customizing outline adds only
/// vertical padding, so blocks do not shift sideways when customizing starts.</summary>
public static class StartLayout
{
    public const double Column = 88, Gap = 4, Inset = (Column - 60) / 2;
}

/// <summary>A block of the start page while customizing: a dashed outline, its radius concentric with the 20 px
/// switch in the header corner 14 px inside it. Dimming of hidden blocks belongs to their content.</summary>
public sealed partial class StartEditFrame : Grid
{
    public StartEditFrame(FrameworkElement content, bool editing)
    {
        if (editing)
        {
            var radius = 10 + StartLayout.Inset;
            Children.Add(new Microsoft.UI.Xaml.Shapes.Rectangle { Stroke = Palette.HairlineStrong.Brush(), StrokeThickness = 1, StrokeDashArray = [4, 3], RadiusX = radius, RadiusY = radius });
            Padding = new Thickness(0, Space.Normal, 0, Space.Normal);
        }
        Children.Add(content);
    }
}

/// <summary>Title row of a start page block (macOS StartBlockHeader). While customizing it carries the block's
/// controls on the right: optional order buttons and a switch that shows or hides the block. The row never dims.</summary>
public sealed partial class StartBlockHeader : Grid
{
    public StartBlockHeader(string title, bool editing, bool shown, Store store, Action<bool> setShown, params UIElement[] order)
    {
        MinHeight = 24; ColumnSpacing = Space.Small; Margin = new Thickness(StartLayout.Inset, 0, StartLayout.Inset, 0);
        ColumnDefinitions.Add(Ui.Star()); ColumnDefinitions.Add(Ui.Auto());
        this.Column(Ui.Text(title, 12, Palette.Text3.Brush(), Ui.Medium), 0);
        if (!editing) return;
        var label = store.Text("показывать", "Показывать") + ": " + title;
        var toggle = new Switch(shown, label) { VerticalAlignment = VerticalAlignment.Center }.Tip(label);
        toggle.Toggled += setShown;
        var controls = Ui.H(Space.Small);
        if (order.Length > 0) controls.Children.Add(Ui.H(0, order));
        controls.Children.Add(toggle);
        controls.VerticalAlignment = VerticalAlignment.Center;
        this.Column(controls, 1);
    }
}

/// <summary>Options for the whole start page, under the live page while customizing.</summary>
public sealed partial class StartCustomizeBar : Grid
{
    public StartCustomizeBar(BrowserModel browser)
    {
        var store = browser.Store;
        var start = store.Preferences.Start;
        var defaults = new Mica.Core.StartPage();
        MaxWidth = 520;
        var count = new Segmented<int>(start.FrequentCount, Mica.Core.StartPage.FrequentChoices.Select(c => (c, c.ToString())), compact: true, label: store.Text("сайтов в разделе", "Сайтов в разделе"));
        count.Changed += value => store.Change(p => p.Start.FrequentCount = value);
        var changed = !start.Sections.SequenceEqual(defaults.Sections) || start.Wordmark != defaults.Wordmark || start.FrequentCount != defaults.FrequentCount;
        var reset = new IconButton("arrow.counterclockwise", store.Text("вернуть как было", "Вернуть как было")) { IsEnabled = changed };
        reset.Click += () => store.Change(p => { p.Start.Sections = [.. defaults.Sections]; p.Start.Wordmark = defaults.Wordmark; p.Start.FrequentCount = defaults.FrequentCount; });
        var all = new IconButton("gearshape", store.Text("все настройки", "Все настройки"));
        all.Click += () => { browser.CustomizingStart = false; browser.SettingsSection = Settings.SettingsSection.Start; browser.ShowSettings = true; };
        var done = new MButton(store.Text("готово", "Готово"), ButtonKind.Primary, compact: true);
        done.Click += () => browser.CustomizingStart = false;
        var row = new Grid { ColumnSpacing = Space.Small, Padding = new Thickness(Space.Normal, 8, Space.Normal, 8) };
        foreach (var _ in Enumerable.Range(0, 6)) row.ColumnDefinitions.Add(Ui.Auto());
        row.ColumnDefinitions[2] = Ui.Star();
        row.Column(Ui.Text(store.Text("сайтов в разделе", "Сайтов в разделе"), 12, Palette.Text2.Brush()), 0);
        row.Column(count, 1); row.Column(reset, 3); row.Column(all, 4); row.Column(done, 5);
        Children.Add(Ui.Raised(row, Radius.Panel));
    }
}

/// <summary>One start page section with its tiles (macOS StartSectionView).</summary>
public sealed partial class StartSectionView : Grid
{
    public StartSectionView(StartSection section, List<StartSite> sites, BrowserModel browser, bool editing)
    {
        var store = browser.Store;
        var start = store.Preferences.Start;
        var visible = start.Sections.Contains(section);
        var stack = new StackPanel { Spacing = Space.Normal };
        var up = new IconButton("chevron.up", store.Text("выше", "Выше") + ": " + section.Title(store), 24) { IsEnabled = visible && start.Sections.FirstOrDefault() != section };
        up.Click += () => store.Change(p => p.Start.Shift(section, -1));
        var down = new IconButton("chevron.down", store.Text("ниже", "Ниже") + ": " + section.Title(store), 24) { IsEnabled = visible && start.Sections.LastOrDefault() != section };
        down.Click += () => store.Change(p => p.Start.Shift(section, 1));
        stack.Children.Add(new StartBlockHeader(section.Title(store), editing, visible, store, on => store.Change(p => p.Start.SetVisible(section, on)), up, down));
        FrameworkElement content;
        if (editing && sites.Count == 0 && section != StartSection.Custom)
        {
            var placeholder = section == StartSection.Frequent
                ? (browser.PrivateMode ? store.Text("в окне инкогнито частые сайты не показываются", "В окне инкогнито частые сайты не показываются") : store.Text("появятся, когда вы начнёте открывать сайты", "Появятся, когда вы начнёте открывать сайты"))
                : store.Text("здесь будут закладки, ", "Здесь будут закладки, ") + (Keymap.Label("bookmark") ?? "Ctrl+D") + store.Text(" добавляет страницу", " добавляет страницу");
            var box = new Grid { MinHeight = 60, Margin = new Thickness(StartLayout.Inset, 0, StartLayout.Inset, 0) };
            box.Children.Add(new Microsoft.UI.Xaml.Shapes.Rectangle { Stroke = Palette.Hairline.Brush(), StrokeThickness = 1, StrokeDashArray = [4, 3], RadiusX = Radius.Row, RadiusY = Radius.Row });
            var t = Ui.Text(placeholder, 12, Palette.Text3.Brush(), wrap: true); t.HorizontalAlignment = HorizontalAlignment.Center; t.TextAlignment = TextAlignment.Center; t.Margin = new Thickness(Space.Normal, 0, Space.Normal, 0); box.Children.Add(t);
            content = box;
        }
        else
        {
            // Each tile is 88 px wide and starts its 92 px cell, so the first icon sits 14 px in, under the title.
            var grid = new VariableSizedWrapGrid { Orientation = Orientation.Horizontal, ItemWidth = StartLayout.Column + StartLayout.Gap, ItemHeight = 96 };
            foreach (var site in sites) grid.Children.Add(new SiteTile(site, section, browser) { Width = StartLayout.Column, HorizontalAlignment = HorizontalAlignment.Left });
            if (section == StartSection.Custom) grid.Children.Add(new AddShortcutTile(store) { Width = StartLayout.Column, HorizontalAlignment = HorizontalAlignment.Left });
            content = grid;
        }
        content.Opacity = editing && !visible ? 0.4 : 1;
        stack.Children.Add(content);
        Children.Add(new StartEditFrame(stack, editing));
    }
}

/// <summary>60 px tile with a monogram that lifts on hover; custom sites reorder by dragging onto each other.</summary>
public sealed partial class SiteTile : Grid
{
    public SiteTile(StartSite site, StartSection section, BrowserModel browser)
    {
        var store = browser.Store;
        Background = Palette.Clear; IsTabStop = true;
        var box = Ui.Rounded(Radius.Panel, Palette.Surface.Brush(), Palette.Hairline.Brush(), 1, new Monogram(site.Host, 30) { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center });
        box.Width = 60; box.Height = 60; box.Shadow = Shadows.Soft; box.Translation = new System.Numerics.Vector3(0, 0, 3); box.HorizontalAlignment = HorizontalAlignment.Center;
        var label = site.Title.Length > 0 ? site.Title : site.Host.StartsWith("www.", StringComparison.Ordinal) ? site.Host[4..] : site.Host;
        var text = Ui.Text(label, 11.5, Palette.Text2.Brush()); text.HorizontalAlignment = HorizontalAlignment.Center; text.MaxWidth = StartLayout.Column - 4;
        Children.Add(Ui.V(Space.Small, box, text));
        Interaction? interaction = null;
        interaction = new Interaction(this, () =>
        {
            var hover = interaction!.Hover;
            text.Foreground = hover ? Palette.Ink.Brush() : Palette.Text2.Brush();
            Motion.Translate(box, new System.Numerics.Vector3(0, hover ? -2 : 0, hover ? 10 : 3), Motion.Snappy);
        }, 0.95);
        interaction.Invoked += () => browser.Selected?.Load(site.Url);
        this.Tip(site.Host);
        if (site.Shortcut is { } id)
        {
            CanDrag = true; AllowDrop = true;
            DragStarting += (_, e) => e.Data.SetText("mica-shortcut:" + id);
            DragOver += (_, e) => e.AcceptedOperation = DataPackageOperation.Move;
            Drop += async (_, e) =>
            {
                if (!e.DataView.Contains(StandardDataFormats.Text)) return;
                var payload = await e.DataView.GetTextAsync();
                if (payload.StartsWith("mica-shortcut:", StringComparison.Ordinal) && Guid.TryParse(payload[14..], out var source)) store.Change(p => p.Start.MoveShortcut(source, id));
            };
        }
        this.ContextMenu(() => Menu(site, section, browser));
    }

    IEnumerable<MenuEntry> Menu(StartSite site, StartSection section, BrowserModel browser)
    {
        var store = browser.Store;
        yield return MenuEntry.Item(browser.Text("открыть в новой вкладке", "Открыть в новой вкладке"), () => browser.Open(site.Url), "plus.square");
        yield return MenuEntry.Separator;
        if (site.Shortcut is { } id)
        {
            yield return MenuEntry.Item(browser.Text("изменить…", "Изменить…"), () => ShortcutEditor.Show(this, store, id), "pencil");
            yield return MenuEntry.Item(browser.Text("переместить левее", "Переместить левее"), () => store.Change(p => p.Start.ShiftShortcut(id, -1)), "arrow.left", enabled: store.Preferences.Start.Shortcuts.FirstOrDefault()?.Id != id);
            yield return MenuEntry.Item(browser.Text("переместить правее", "Переместить правее"), () => store.Change(p => p.Start.ShiftShortcut(id, 1)), "arrow.right", enabled: store.Preferences.Start.Shortcuts.LastOrDefault()?.Id != id);
            yield return MenuEntry.Separator;
            yield return MenuEntry.Item(browser.Text("удалить с начальной страницы", "Удалить с начальной страницы"), () => store.Change(p => p.Start.Shortcuts.RemoveAll(s => s.Id == id)), "trash", destructive: true);
        }
        else
        {
            yield return MenuEntry.Item(browser.Text("закрепить в своих сайтах", "Закрепить в своих сайтах"), () => store.Change(p => { p.Start.Shortcuts.Add(new StartShortcut { Title = site.Title, Url = site.Url }); p.Start.SetVisible(StartSection.Custom, true); }), "pin");
            if (section == StartSection.Frequent && AddressParser.Host(site.Url)?.ToLowerInvariant() is { } host)
                yield return MenuEntry.Item(browser.Text("скрыть из частых", "Скрыть из частых"), () => store.Change(p => p.Start.HiddenHosts.Add(host)), "eye.slash");
        }
        yield return MenuEntry.Separator;
        yield return MenuEntry.Item(browser.Text("настроить начальную страницу…", "Настроить начальную страницу…"), () => browser.CustomizingStart = true, "slider.horizontal.3");
    }
}

public sealed partial class AddShortcutTile : Grid
{
    public AddShortcutTile(Store store)
    {
        Background = Palette.Clear; IsTabStop = true;
        var plate = new Grid { Width = 60, Height = 60, HorizontalAlignment = HorizontalAlignment.Center };
        var fill = Ui.Rounded(Radius.Panel);
        plate.Children.Add(fill);
        plate.Children.Add(new Microsoft.UI.Xaml.Shapes.Rectangle { Stroke = Palette.HairlineStrong.Brush(), StrokeThickness = 1, StrokeDashArray = [4, 3], RadiusX = Radius.Panel, RadiusY = Radius.Panel });
        var glyph = new Glyph("plus", 16, Palette.Text2.Brush()) { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        plate.Children.Add(glyph);
        var text = Ui.Text(store.Text("добавить", "Добавить"), 11.5, Palette.Text3.Brush()); text.HorizontalAlignment = HorizontalAlignment.Center;
        Children.Add(Ui.V(Space.Small, plate, text));
        Interaction? interaction = null;
        interaction = new Interaction(this, () => { var h = interaction!.Hover; fill.Background = h ? Palette.Hover.Brush() : Palette.Clear; glyph.Foreground = h ? Palette.Ink.Brush() : Palette.Text2.Brush(); text.Foreground = h ? Palette.Ink.Brush() : Palette.Text3.Brush(); }, 0.95);
        interaction.Invoked += () => ShortcutEditor.Show(this, store, null);
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(this, store.Text("добавить сайт на начальную страницу", "Добавить сайт на начальную страницу"));
    }
}

/// <summary>Adds or edits a custom site. Plain words are refused instead of becoming a search shortcut.</summary>
public static class ShortcutEditor
{
    public static void Show(FrameworkElement anchor, Store store, Guid? editing)
    {
        var existing = editing is { } id ? store.Preferences.Start.Shortcuts.FirstOrDefault(s => s.Id == id) : null;
        var address = new SurfaceField(store.Text("адрес, например github.com", "Адрес, например github.com"), existing?.Url ?? "", "globe");
        var title = new SurfaceField(store.Text("название, необязательно", "Название, необязательно"), existing?.Title ?? "", "textformat");
        address.ClearLabel(store.Text("очистить", "Очистить")); title.ClearLabel(store.Text("очистить", "Очистить"));
        var invalid = Ui.Text(store.Text("нужен адрес сайта, а не поисковый запрос", "Нужен адрес сайта, а не поисковый запрос"), 11.5, Palette.Danger.Brush()); invalid.Visibility = Visibility.Collapsed;
        // The app canvas instead of the default acrylic, so the fields read like the start page search field.
        var presenter = new Style(typeof(FlyoutPresenter));
        presenter.Setters.Add(new Setter(Control.BackgroundProperty, Palette.Canvas.Brush()));
        presenter.Setters.Add(new Setter(Control.BorderBrushProperty, Palette.HairlineStrong.Brush()));
        presenter.Setters.Add(new Setter(Control.BorderThicknessProperty, new Thickness(1)));
        presenter.Setters.Add(new Setter(Control.CornerRadiusProperty, new CornerRadius(Radius.Panel)));
        presenter.Setters.Add(new Setter(Control.PaddingProperty, new Thickness(16)));
        var flyout = new Flyout { FlyoutPresenterStyle = presenter };
        var cancel = new MButton(store.Text("отмена", "Отмена"), ButtonKind.Ghost, compact: true);
        var save = new MButton(editing is null ? store.Text("добавить", "Добавить") : store.Text("сохранить", "Сохранить"), ButtonKind.Primary, compact: true) { IsEnabled = address.Text.Trim().Length > 0 };
        address.Box.TextChanged += (_, _) => save.IsEnabled = address.Text.Trim().Length > 0;
        void Save()
        {
            if (Mica.Core.StartPage.ShortcutUrl(address.Text, store.Preferences.Search) is not { } url) { invalid.Visibility = Visibility.Visible; return; }
            var name = title.Text.Trim();
            store.Change(p =>
            {
                if (editing is { } id && p.Start.Shortcuts.FirstOrDefault(s => s.Id == id) is { } item) { item.Url = url; item.Title = name; }
                else p.Start.Shortcuts.Add(new StartShortcut { Title = name, Url = url });
            });
            flyout.Hide();
        }
        address.Submit += Save; title.Submit += Save; save.Click += Save; cancel.Click += flyout.Hide;
        var buttons = Ui.H(Space.Small, cancel, save); buttons.HorizontalAlignment = HorizontalAlignment.Right;
        flyout.Content = Ui.V(Space.Normal, Ui.Text(editing is null ? store.Text("новый сайт", "Новый сайт") : store.Text("изменить сайт", "Изменить сайт"), 14, null, Ui.Medium), Ui.V(Space.Small, address, invalid, title), buttons).Size(300 - 32);
        flyout.Opened += (_, _) => address.Box.Focus(FocusState.Programmatic);
        flyout.ShowAt(anchor);
    }
}
