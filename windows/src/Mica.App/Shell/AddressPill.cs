using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Mica.Core;
using Mica.Design;

namespace Mica.App;

/// <summary>Address field in the top bar (macOS AddressPill): site info on the left, the host in the middle (the
/// command bar opens on click), the Chrome Web Store install button and the bookmark star on the right, and a thin
/// load progress line along the bottom.</summary>
public sealed partial class AddressPill : Grid
{
    readonly Tab tab;
    readonly BrowserModel browser;
    readonly Border fill;
    readonly IconButton info, bookmark, install;
    readonly TextBlock text;
    readonly Border progress;
    bool hover;

    public AddressPill(Tab tab, BrowserModel browser)
    {
        this.tab = tab; this.browser = browser;
        var store = browser.Store;
        Height = Chrome.Field + 4;
        fill = Ui.Rounded(Radius.Icon, Palette.Field.Brush());
        Children.Add(fill);
        var row = new Grid { Margin = new Thickness(3, 0, 3, 0), ColumnSpacing = 4 };
        row.ColumnDefinitions.Add(Ui.Auto()); row.ColumnDefinitions.Add(Ui.Star()); row.ColumnDefinitions.Add(Ui.Auto()); row.ColumnDefinitions.Add(Ui.Auto());
        var control = Height - 6;
        info = new IconButton("magnifyingglass", browser.Text("сведения о сайте", "Сведения о сайте"), control) { VerticalAlignment = VerticalAlignment.Center };
        info.Click += () =>
        {
            var flyout = new Flyout { Content = new SiteInfo(tab, browser) { Width = 320 }, Placement = Microsoft.UI.Xaml.Controls.Primitives.FlyoutPlacementMode.BottomEdgeAlignedLeft };
            flyout.ShowAt(info);
        };
        text = Ui.Text("", 12.5);
        text.HorizontalAlignment = HorizontalAlignment.Center;
        text.TextTrimming = TextTrimming.CharacterEllipsis;
        var field = new Grid { Background = Palette.Clear };
        field.Children.Add(text);
        field.Tapped += (_, _) => browser.CommandBar = true;
        install = new IconButton("puzzlepiece.extension", browser.Text("установить расширение в mica", "Установить расширение в mica"), control) { VerticalAlignment = VerticalAlignment.Center };
        install.Click += async () => { browser.Panel = LibraryPanel.Extensions; if (tab.Url is { } url) await store.Extensions.InstallFromChromeStoreAsync(url); };
        bookmark = new IconButton("bookmark", browser.Text("добавить или удалить закладку", "Добавить или удалить закладку"), control) { VerticalAlignment = VerticalAlignment.Center };
        bookmark.Click += () => store.Bookmark(tab);
        row.Column(info, 0); row.Column(field, 1); row.Column(install, 2); row.Column(bookmark, 3);
        Children.Add(row);
        // Load progress: flush with the bottom edge from the very left, clipped by a track with the field's own corner
        // radius so it follows the rounded corners instead of stopping short of them. Drawn under the border stroke.
        progress = new Border { Background = Look.Progress, Height = 3, VerticalAlignment = VerticalAlignment.Bottom, HorizontalAlignment = HorizontalAlignment.Left, Opacity = 0 };
        Children.Add(new Border { CornerRadius = new CornerRadius(Radius.Icon), Background = Palette.Clear, IsHitTestVisible = false, Child = progress });
        Children.Add(new Border { CornerRadius = new CornerRadius(Radius.Icon), BorderBrush = Palette.FieldBorder.Brush(), BorderThickness = new Thickness(1), IsHitTestVisible = false });
        PointerEntered += (_, _) => { hover = true; Render(); };
        PointerExited += (_, _) => { hover = false; Render(); };
        this.Bind(tab, Render);
        this.Bind(h => store.BookmarksChanged += h, h => store.BookmarksChanged -= h, Render);
        this.Bind(h => store.Extensions.Changed += h, h => store.Extensions.Changed -= h, Render);
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(field, browser.Text("адресная строка", "Адресная строка"));
        SizeChanged += (_, _) => Render();
    }

    void Render()
    {
        var store = browser.Store;
        info.Symbol = browser.PrivateMode ? Glyph.Incognito : tab.Secure ? "lock.fill" : tab.Url is null ? "magnifyingglass" : "exclamationmark.shield";
        info.IsEnabled = tab.Url is not null;
        text.Text = Display();
        text.Foreground = tab.Url is null ? Palette.Text3.Brush() : Palette.Ink.Brush();
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(this, browser.Text("адресная строка: ", "Адресная строка: ") + (tab.Url ?? ""));
        var bookmarked = store.IsBookmarked(tab.Url);
        bookmark.Symbol = bookmarked ? "bookmark.fill" : "bookmark";
        bookmark.IsEnabled = tab.Url is not null;
        Motion.Fade(bookmark, tab.Url is not null && (hover || bookmarked) ? 1 : 0);
        var storeId = !browser.PrivateMode && tab.Url is not null ? ChromeStore.ExtensionId(tab.Url) : null;
        install.Visibility = storeId is not null && !store.Extensions.Records.Any(r => r.Source == "cws:" + storeId) ? Visibility.Visible : Visibility.Collapsed;
        fill.Background = hover ? Palette.FieldHover.Brush() : Palette.Field.Brush();
        progress.Width = Math.Max(0, ActualWidth * Math.Clamp(tab.Progress, 0, 1));
        Motion.Fade(progress, tab.Loading ? 1 : 0);
    }

    string Display()
    {
        if (tab.Url is not { } url) return browser.Text("адрес или поиск", "Адрес или поиск");
        if (AddressParser.Host(url) is { } host) return host.StartsWith("www.", StringComparison.Ordinal) ? host[4..] : host;
        return url;
    }
}
