using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Mica.Core;
using Mica.Design;

namespace Mica.App;

public enum SuggestionKind { Open, Search, Tab, Bookmark, History }

public sealed record Suggestion(string Id, SuggestionKind Kind, string Title, string Detail, string? Url = null, Guid? TabId = null)
{
    public string Symbol => Kind switch { SuggestionKind.Open => "arrow.up.right", SuggestionKind.Search => "magnifyingglass", SuggestionKind.Tab => "square.on.square", SuggestionKind.Bookmark => "bookmark", _ => "clock" };

    public static List<Suggestion> Make(string input, BrowserModel browser)
    {
        var store = browser.Store;
        var query = input.Trim();
        if (query.Length == 0) return [];
        var result = new List<Suggestion>();
        var engine = store.Preferences.Search;
        var target = AddressParser.Resolve(query, engine);
        if (target.Kind == AddressKind.Web)
        {
            var searchDetail = browser.Text("поиск: ", "Поиск: ") + engine.Title(browser.TextStyle.Language);
            if (engine.IsSearch(target.Value, query)) result.Add(new("search", SuggestionKind.Search, query, searchDetail, target.Value));
            else
            {
                result.Add(new("open", SuggestionKind.Open, target.Value, browser.Text("открыть адрес", "Открыть адрес"), target.Value));
                result.Add(new("search", SuggestionKind.Search, query, searchDetail, engine.Search(query)));
            }
        }
        bool Matches(string title, string url) => title.Contains(query, StringComparison.CurrentCultureIgnoreCase) || url.Contains(query, StringComparison.CurrentCultureIgnoreCase);
        var seen = new HashSet<string>(result.Select(r => r.Url).OfType<string>());
        foreach (var tab in browser.Tabs.Where(t => t.Id != browser.SelectedId))
            if (tab.Url is { } url && Matches(tab.Title, url) && seen.Add(url)) result.Add(new("tab-" + tab.Id, SuggestionKind.Tab, tab.Title.Length == 0 ? url : tab.Title, browser.Text("перейти к вкладке", "Перейти к вкладке"), url, tab.Id));
        foreach (var visit in store.Bookmarks)
            if (Matches(visit.Title, visit.Url) && seen.Add(visit.Url)) result.Add(new("b-" + visit.Id, SuggestionKind.Bookmark, visit.Title.Length == 0 ? visit.Url : visit.Title, visit.Host ?? visit.Url, visit.Url));
        if (!browser.PrivateMode)
            foreach (var visit in store.History)
            {
                if (!Matches(visit.Title, visit.Url) || !seen.Add(visit.Url)) continue;
                result.Add(new("h-" + visit.Id, SuggestionKind.History, visit.Title.Length == 0 ? visit.Url : visit.Title, visit.Host ?? visit.Url, visit.Url));
                if (result.Count >= 8) break;
            }
        return result.Take(8).ToList();
    }

    public void Activate(BrowserModel browser)
    {
        if (TabId is { } id && browser.Tabs.FirstOrDefault(t => t.Id == id) is { } tab) browser.Select(tab);
        else if (Url is { } url) browser.Selected?.Load(url);
    }
}

/// <summary>Suggestion rows shared by the command bar and the start page field.</summary>
public sealed partial class SuggestionList : StackPanel
{
    readonly Action<Suggestion> choose;
    List<Suggestion> items = [];
    public int Highlighted { get; private set; }
    public SuggestionList(Action<Suggestion> choose) { this.choose = choose; Spacing = 2; }
    public IReadOnlyList<Suggestion> Items => items;
    public void Set(List<Suggestion> next) { items = next; Highlighted = 0; Render(); }
    public void Move(int step) { if (items.Count == 0) return; Highlighted = Math.Clamp(Highlighted + step, 0, items.Count - 1); Render(); }
    void Render()
    {
        Children.Clear();
        for (var i = 0; i < items.Count; i++)
        {
            var item = items[i]; var index = i;
            var row = new Grid { Height = 34, Background = Palette.Clear, Padding = new Thickness(8, 0, 8, 0), ColumnSpacing = 10 };
            row.ColumnDefinitions.Add(Ui.Auto()); row.ColumnDefinitions.Add(Ui.Auto()); row.ColumnDefinitions.Add(Ui.Star()); row.ColumnDefinitions.Add(Ui.Auto());
            var plate = Ui.Rounded(Radius.Row, index == Highlighted ? Palette.Hover.Brush() : Palette.Clear); Grid.SetColumnSpan(plate, 4); plate.Margin = new Thickness(-8, 0, -8, 0);
            row.Children.Add(plate);
            var badge = Ui.Rounded(6, Palette.Track.Brush(), child: new Glyph(item.Symbol, 11, Palette.Text2.Brush()) { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center }); badge.Width = 22; badge.Height = 22;
            row.Column(badge, 0);
            var title = Ui.Text(item.Title, 13); title.MaxWidth = 380; row.Column(title, 1);
            row.Column(Ui.Text(item.Detail, 12, Palette.Text3.Brush()), 2);
            if (index == Highlighted) row.Column(new Glyph("return", 10, Palette.Text3.Brush()) { VerticalAlignment = VerticalAlignment.Center }, 3);
            row.PointerEntered += (_, _) => { if (Highlighted != index) { Highlighted = index; Render(); } };
            row.Tapped += (_, _) => choose(item);
            Children.Add(row);
        }
    }
}

/// <summary>Address and search over the page (macOS CommandBar), opened by clicking the field or Ctrl+L.</summary>
public sealed partial class CommandBar : Grid
{
    readonly BrowserModel browser;
    readonly TextBox box;
    readonly SuggestionList list;
    readonly Grid listHost = new();
    public CommandBar(BrowserModel browser)
    {
        this.browser = browser;
        var scrim = new Grid { Background = new SolidColorBrush(Palette.WithAlpha(Microsoft.UI.Colors.Black, 0.14)) };
        scrim.Tapped += (_, _) => Close();
        Children.Add(scrim);
        box = MTextField.Bare(new TextBox { PlaceholderText = browser.Text("адрес или поиск", "Адрес или поиск"), FontSize = 16, Text = browser.Selected?.Url ?? "" });
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(box, browser.Text("адресная строка", "Адресная строка"));
        list = new SuggestionList(Choose) { Margin = new Thickness(Radius.PanelPadding) };
        var field = new Grid { Height = 52, Padding = new Thickness(16, 0, 16, 0), ColumnSpacing = 10 };
        field.ColumnDefinitions.Add(Ui.Auto()); field.ColumnDefinitions.Add(Ui.Star()); field.ColumnDefinitions.Add(Ui.Auto());
        field.Column(new Glyph("magnifyingglass", 15, Palette.Text2.Brush()) { VerticalAlignment = VerticalAlignment.Center }, 0);
        field.Column(box, 1);
        field.Column(KeyHint.Make("Esc"), 2);
        var stack = Ui.V(0, field, listHost);
        var surface = Ui.Raised(stack, Radius.Panel);
        surface.MaxWidth = 640; surface.VerticalAlignment = VerticalAlignment.Top; surface.HorizontalAlignment = HorizontalAlignment.Center;
        Children.Add(surface);
        SizeChanged += (_, e) => { surface.Width = Math.Min(640, e.NewSize.Width - 64); surface.Margin = new Thickness(0, Math.Max(56, e.NewSize.Height * 0.14), 0, 0); };
        box.TextChanged += (_, _) => Update();
        box.KeyDown += (_, e) =>
        {
            switch (e.Key)
            {
                case Windows.System.VirtualKey.Down: list.Move(1); e.Handled = true; break;
                case Windows.System.VirtualKey.Up: list.Move(-1); e.Handled = true; break;
                case Windows.System.VirtualKey.Enter: Submit(); e.Handled = true; break;
                case Windows.System.VirtualKey.Escape: Close(); e.Handled = true; break;
            }
        };
        Loaded += (_, _) => { box.Focus(FocusState.Programmatic); box.SelectAll(); Motion.Appear(surface, Motion.Edge.Top); };
        Update();
    }

    void Update()
    {
        list.Set(Suggestion.Make(box.Text, browser));
        listHost.Children.Clear();
        if (list.Items.Count > 0) { listHost.Children.Add(Ui.V(0, Ui.Hairline(), list)); }
    }

    void Submit()
    {
        var items = list.Items;
        if (items.Count > list.Highlighted && (list.Highlighted > 0 || items[0].Kind is SuggestionKind.Open or SuggestionKind.Search)) Choose(items[list.Highlighted]);
        else if (box.Text.Length > 0) { browser.Navigate(box.Text); Close(); }
    }

    void Choose(Suggestion item) { item.Activate(browser); Close(); }
    void Close() => browser.CommandBar = false;
}
