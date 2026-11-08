using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Mica.Core;
using Mica.Design;
using Windows.ApplicationModel.DataTransfer;

namespace Mica.App.Library;

/// <summary>Library panel beside the page: bookmarks, history by day, downloads, extensions (macOS SidePanel).</summary>
public sealed partial class SidePanel : Grid
{
    readonly LibraryPanel panel; readonly BrowserModel browser;
    readonly MTextField? query;
    readonly StackPanel list = new() { Spacing = 2 };
    readonly Grid content = new();

    public SidePanel(LibraryPanel panel, BrowserModel browser)
    {
        this.panel = panel; this.browser = browser;
        var store = browser.Store;
        Padding = new Thickness(14);
        RowSpacing = Space.Normal;
        RowDefinitions.Add(Ui.RowAuto()); RowDefinitions.Add(Ui.RowStar());
        var title = panel switch { LibraryPanel.Bookmarks => browser.Text("закладки", "Закладки"), LibraryPanel.History => browser.Text("история", "История"), LibraryPanel.Downloads => browser.Text("загрузки", "Загрузки"), _ => browser.Text("расширения", "Расширения") };
        var head = new Grid(); head.ColumnDefinitions.Add(Ui.Star()); head.ColumnDefinitions.Add(Ui.Auto());
        var t = Ui.Text(title, 17); t.CharacterSpacing = -18; head.Column(t, 0);
        var close = new IconButton("xmark", browser.Text("закрыть панель", "Закрыть панель")); close.Click += () => browser.Panel = null; head.Column(close, 1);
        this.Row(head, 0);
        this.Row(content, 1);
        if (panel == LibraryPanel.Extensions) { content.Children.Add(new Extensions.ExtensionsPanel(browser)); return; }
        if (panel == LibraryPanel.Downloads) { content.Children.Add(new Downloads.DownloadsPanel(browser)); return; }
        query = new MTextField(browser.Text("поиск", "Поиск"), symbol: "magnifyingglass");
        query.Box.TextChanged += (_, _) => Render();
        var stack = new Grid { RowSpacing = Space.Normal };
        stack.RowDefinitions.Add(Ui.RowAuto()); stack.RowDefinitions.Add(Ui.RowAuto()); stack.RowDefinitions.Add(Ui.RowStar()); stack.RowDefinitions.Add(Ui.RowAuto());
        stack.Row(query, 0);
        if (panel == LibraryPanel.History && browser.PrivateMode) stack.Row(Ui.Text(browser.Text("история окна инкогнито не записывается", "История окна инкогнито не записывается"), 11.5, Palette.Text3.Brush(), wrap: true), 1);
        var scroll = Ui.Scroll(list); scroll.VerticalScrollBarVisibility = ScrollBarVisibility.Hidden;
        stack.Row(scroll, 2);
        if (panel == LibraryPanel.History && !browser.PrivateMode)
        {
            var clear = new MButton(browser.Text("очистить историю…", "Очистить историю…"), ButtonKind.Destructive, compact: true).Tip(browser.Text("очистить историю", "Очистить историю") + (Keymap.Label("clearData") is { } k ? " " + k : ""));
            clear.Click += () => browser.ShowClearData = true;
            stack.Row(clear, 3);
        }
        content.Children.Add(stack);
        if (panel == LibraryPanel.History) this.Bind(h => store.HistoryChanged += h, h => store.HistoryChanged -= h, Render);
        else this.Bind(h => store.BookmarksChanged += h, h => store.BookmarksChanged -= h, Render);
    }

    void Render()
    {
        var store = browser.Store;
        var q = query?.Text ?? "";
        var visits = (panel == LibraryPanel.History ? store.History : store.Bookmarks).Where(v => q.Length == 0 || v.Title.Contains(q, StringComparison.CurrentCultureIgnoreCase) || v.Url.Contains(q, StringComparison.CurrentCultureIgnoreCase)).ToList();
        list.Children.Clear();
        if (visits.Count == 0)
        {
            list.Children.Add(new EmptyState(panel == LibraryPanel.History ? "clock" : "bookmark", q.Length == 0
                ? (panel == LibraryPanel.History ? browser.Text("история пока пуста", "История пока пуста") : browser.Text("добавьте закладку через ", "Добавьте закладку через ") + (Keymap.Label("bookmark") ?? "Ctrl+D"))
                : browser.Text("ничего не найдено", "Ничего не найдено")) { Margin = new Thickness(0, 48, 0, 0) });
            return;
        }
        if (panel == LibraryPanel.History)
            foreach (var (day, group) in HistoryOps.Days(visits.Take(600)))
            {
                list.Children.Add(DayHeader(day, store));
                foreach (var visit in group) list.Children.Add(new VisitRow(visit, panel, browser));
            }
        else foreach (var visit in visits) list.Children.Add(new VisitRow(visit, panel, browser));
    }

    /// <summary>Today, yesterday, then weekday and date in the interface language; authored words follow the case style.</summary>
    static TextBlock DayHeader(DateTime day, Store store)
    {
        string title;
        if (day == DateTime.Today) title = store.Text("сегодня", "Сегодня");
        else if (day == DateTime.Today.AddDays(-1)) title = store.Text("вчера", "Вчера");
        else
        {
            var culture = store.Culture;
            var text = day.ToString(day.Year == DateTime.Today.Year ? (culture.Name.StartsWith("ru") ? "dddd, d MMMM" : "dddd, MMMM d") : (culture.Name.StartsWith("ru") ? "dddd, d MMMM yyyy" : "dddd, MMMM d, yyyy"), culture);
            title = store.Preferences.Lowercase ? text.ToLower(culture) : char.ToUpper(text[0], culture) + text[1..];
        }
        var header = Ui.Text(title, 11.5, Palette.Text3.Brush(), Ui.Medium);
        header.Margin = new Thickness(8, Space.Small, 8, Space.Micro);
        return header;
    }
}

public sealed partial class VisitRow : Grid
{
    public VisitRow(Visit visit, LibraryPanel panel, BrowserModel browser)
    {
        var store = browser.Store;
        Background = Palette.Clear; IsTabStop = true;
        var plate = Ui.Rounded(Radius.Row);
        var title = Ui.Text(visit.Title.Length == 0 ? visit.Url : visit.Title, 12.5);
        var detail = Ui.Text((visit.Host ?? visit.Url) + (panel == LibraryPanel.History ? "  " + visit.Date.LocalDateTime.ToString("t", store.Culture) : ""), 11, Palette.Text3.Brush());
        var row = new Grid { Padding = new Thickness(8, 6, 32, 6), ColumnSpacing = 10 };
        row.ColumnDefinitions.Add(Ui.Auto()); row.ColumnDefinitions.Add(Ui.Star());
        row.Column(new Monogram(visit.Host, 22), 0); row.Column(Ui.V(1, title, detail), 1);
        var more = new MenuButton(browser.Text("действия", "Действия"), () => Menu(visit, panel, browser)) { HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 6, 0), Opacity = 0 };
        Children.Add(plate); Children.Add(row); Children.Add(more);
        Interaction? interaction = null;
        interaction = new Interaction(this, () => { plate.Background = interaction!.Hover ? Palette.Hover.Brush() : Palette.Clear; Motion.Fade(more, interaction.Hover ? 1 : 0); }, 0.98, plate);
        interaction.Invoked += () => browser.Selected?.Load(visit.Url);
        this.ContextMenu(() => Menu(visit, panel, browser));
    }

    static IEnumerable<MenuEntry> Menu(Visit visit, LibraryPanel panel, BrowserModel browser)
    {
        var store = browser.Store;
        yield return MenuEntry.Item(browser.Text("открыть в новой вкладке", "Открыть в новой вкладке"), () => browser.Open(visit.Url), "plus.square");
        yield return MenuEntry.Item(browser.Text("копировать адрес", "Копировать адрес"), () => { var data = new DataPackage(); data.SetText(visit.Url); Clipboard.SetContent(data); }, "link");
        yield return MenuEntry.Separator;
        if (panel == LibraryPanel.History && visit.Host is { } host)
            yield return MenuEntry.Item(browser.Text("удалить всё с сайта ", "Удалить всё с сайта ") + host, () => store.SetHistory(HistoryOps.RemovingHost(store.History, host)), "trash.slash", destructive: true);
        yield return MenuEntry.Item(browser.Text("удалить", "Удалить"), () =>
        {
            if (panel == LibraryPanel.History) store.SetHistory(store.History.Where(v => v.Id != visit.Id).ToList());
            else store.SetBookmarks(store.Bookmarks.Where(v => v.Id != visit.Id).ToList());
        }, "trash", destructive: true);
    }
}

/// <summary>Clears data of regular windows for a period (macOS ClearDataPanel).</summary>
public sealed partial class ClearDataPanel : StackPanel
{
    public ClearDataPanel(BrowserModel browser)
    {
        var store = browser.Store;
        Spacing = Space.Section; Padding = new Thickness(28);
        var title = Ui.Text(store.Text("очистить данные", "Очистить данные"), 20); title.CharacterSpacing = -20;
        Children.Add(Ui.V(Space.Micro, title, Ui.Text(store.Text("только обычные окна. закладки и открытые вкладки останутся", "Только обычные окна. Закладки и открытые вкладки останутся"), 12.5, Palette.Text2.Brush(), wrap: true)));
        var choice = store.Preferences.Clearing.Copy();
        var period = new Segmented<ClearPeriod>(choice.Period, [(ClearPeriod.Hour, store.Text("час", "Час")), (ClearPeriod.Day, store.Text("сутки", "Сутки")), (ClearPeriod.Week, store.Text("неделя", "Неделя")), (ClearPeriod.Month, store.Text("4 недели", "4 недели")), (ClearPeriod.All, store.Text("всё время", "Всё время"))], minWidth: 424, label: store.Text("период", "Период"));
        Children.Add(Ui.V(Space.Small, Ui.Text(store.Text("период", "Период"), 12, Palette.Text2.Brush(), Ui.Medium), period));
        var group = new SettingsGroup();
        ToggleRow? historyRow = null;
        MButton run = null!;
        void Save() => store.Change(p => p.Clearing = choice.Copy());
        string Count(int n)
        {
            if (store.Preferences.Language == Mica.Core.Language.En) return n + " " + (n == 1 ? "entry" : "entries");
            int ten = n % 10, hundred = n % 100;
            return n + " " + (ten == 1 && hundred != 11 ? "запись" : ten is >= 2 and <= 4 && hundred is not (>= 12 and <= 14) ? "записи" : "записей");
        }
        string HistoryDetail() { var visits = HistoryOps.Count(store.History, choice.Period.Start(DateTimeOffset.Now)); return visits == 0 ? store.Text("за этот период записей нет", "За этот период записей нет") : Count(visits); }
        historyRow = new ToggleRow(store.Text("история посещений", "История посещений"), choice.History, v => { choice.History = v; Save(); Refresh(); }, detail: HistoryDetail());
        group.Add(historyRow);
        group.Add(new ToggleRow(store.Text("cookie и данные сайтов", "Cookie и данные сайтов"), choice.SiteData, v => { choice.SiteData = v; Save(); Refresh(); }, detail: store.Text("вы выйдете из аккаунтов на сайтах, открытых за этот период", "Вы выйдете из аккаунтов на сайтах, открытых за этот период")));
        group.Add(new ToggleRow(store.Text("кэш", "Кэш"), choice.Cache, v => { choice.Cache = v; Save(); Refresh(); }, detail: store.Text("страницы загрузятся заново, это безопасно", "Страницы загрузятся заново, это безопасно")));
        group.Add(new ToggleRow(store.Text("разрешения сайтов", "Разрешения сайтов"), choice.Permissions, v => { choice.Permissions = v; Save(); Refresh(); }, divider: false, detail: store.Text("камера, микрофон, уведомления и геолокация, за всё время: у решений нет даты", "Камера, микрофон, уведомления и геолокация, за всё время: у решений нет даты")));
        Children.Add(group);
        var cancel = new MButton(store.Text("отмена", "Отмена"), ButtonKind.Ghost);
        cancel.Click += () => browser.ShowClearData = false;
        run = new MButton(store.Text("очистить", "Очистить"), ButtonKind.Destructive) { IsEnabled = !choice.IsEmpty };
        run.Click += async () =>
        {
            run.IsEnabled = false; run.Title = store.Text("очищаем…", "Очищаем…");
            await store.ClearAsync(choice.Copy());
            browser.ShowClearData = false;
        };
        var buttons = Ui.H(Space.Small, cancel, run); buttons.HorizontalAlignment = HorizontalAlignment.Right;
        Children.Add(buttons);
        period.Changed += value => { choice.Period = value; Save(); Refresh(); };
        void Refresh()
        {
            run.IsEnabled = !choice.IsEmpty;
            var labels = historyRow!.Children.OfType<StackPanel>().FirstOrDefault();
            if (labels?.Children.Count > 1 && labels.Children[1] is TextBlock detail) detail.Text = HistoryDetail();
        }
    }
}
