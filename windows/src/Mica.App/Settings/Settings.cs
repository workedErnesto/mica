using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Mica.Core;
using Mica.Design;

namespace Mica.App.Settings;

public enum SettingsSection { Space, Appearance, Start, Search, Session, Transfer, Permissions, Passwords, About }

public static class Sections
{
    public static string Symbol(this SettingsSection s) => s switch
    {
        SettingsSection.Space => "sidebar.squares.left", SettingsSection.Appearance => "paintbrush", SettingsSection.Start => "square.grid.2x2",
        SettingsSection.Search => "shield.lefthalf.filled", SettingsSection.Session => "square.stack", SettingsSection.Transfer => "square.and.arrow.down.on.square",
        SettingsSection.Permissions => "hand.raised", SettingsSection.Passwords => "key", _ => "info.circle",
    };
    public static string Title(this SettingsSection s, Store store) => s switch
    {
        SettingsSection.Space => store.Text("пространство", "Пространство"), SettingsSection.Appearance => store.Text("оформление", "Оформление"),
        SettingsSection.Start => store.Text("начальная страница", "Начальная страница"), SettingsSection.Search => store.Text("поиск и защита", "Поиск и защита"),
        SettingsSection.Session => store.Text("сессия и память", "Сессия и память"), SettingsSection.Transfer => store.Text("перенос данных", "Перенос данных"),
        SettingsSection.Permissions => store.Text("разрешения сайтов", "Разрешения сайтов"), SettingsSection.Passwords => store.Text("пароли", "Пароли"), _ => "mica",
    };
}

/// <summary>Settings float over the window; a click on the dim area or Esc closes them (macOS SettingsOverlay).</summary>
public sealed partial class SettingsOverlay : Grid
{
    public static string Draft { get; set; } = "";
    public SettingsOverlay(BrowserModel browser)
    {
        async void Close()
        {
            var store = browser.Store;
            if (Draft.Trim().Length == 0) { Draft = ""; browser.ShowSettings = false; return; }
            var answer = await Dialogs.Ask(browser.Window, store.Text("адрес не добавлен", "Адрес не добавлен"), store.Text("введённый адрес «", "Введённый адрес «") + Draft + store.Text("» ещё не сохранён в списке.", "» ещё не сохранён в списке."), [store.Text("продолжить редактирование", "Продолжить редактирование"), store.Text("закрыть без сохранения", "Закрыть без сохранения")]);
            if (answer == 1) { Draft = ""; browser.ShowSettings = false; }
        }
        Children.Add(new ModalCard(new SettingsView(browser, Close), 860, 660, dismiss: Close));
    }
}

public sealed partial class SettingsView : Grid
{
    readonly BrowserModel browser; readonly Action dismiss;
    readonly StackPanel nav = new() { Spacing = 2 };
    readonly Grid pane = new();
    readonly Grid footer = new();
    readonly List<(SettingsSection Section, NavItem Item)> items = [];
    bool compact;

    public SettingsView(BrowserModel browser, Action dismiss)
    {
        this.browser = browser; this.dismiss = dismiss;
        var store = browser.Store;
        ColumnDefinitions.Add(Ui.Fixed(228)); ColumnDefinitions.Add(Ui.Fixed(1)); ColumnDefinitions.Add(Ui.Star());
        var side = new Grid { Background = Look.Shell, Padding = new Thickness(Space.Normal) };
        side.RowDefinitions.Add(Ui.RowStar()); side.RowDefinitions.Add(Ui.RowAuto());
        side.Row(nav, 0); side.Row(footer, 1);
        this.Column(side, 0);
        this.Column(Ui.Hairline(vertical: true), 1);
        var right = new Grid { Background = Palette.Canvas.Brush() };
        right.Children.Add(pane);
        this.Column(right, 2);
        SizeChanged += (_, e) => { var next = e.NewSize.Width < 720; if (next != compact || items.Count == 0) { compact = next; BuildNav(); } };
        Loaded += (_, _) => Show(browser.SettingsSection, animated: false);
        _ = store;
    }

    void BuildNav()
    {
        var store = browser.Store;
        ColumnDefinitions[0].Width = new GridLength(compact ? 60 : 228);
        nav.Children.Clear(); items.Clear(); footer.Children.Clear();
        if (!compact) { var title = Ui.Text(store.Text("настройки", "Настройки"), 20); title.CharacterSpacing = -20; title.Margin = new Thickness(10, 6, 10, Space.Normal); nav.Children.Add(title); }
        foreach (var section in Enum.GetValues<SettingsSection>())
        {
            var item = new NavItem(section.Title(store), section.Symbol(), section == browser.SettingsSection, compact, () => Show(section, true));
            items.Add((section, item)); nav.Children.Add(item);
        }
        if (compact) { var close = new IconButton("xmark", store.Text("готово", "Готово"), 36); close.Click += dismiss; footer.Children.Add(close); }
        else { var done = new MButton(store.Text("готово", "Готово"), ButtonKind.Primary, stretch: true); done.Click += dismiss; footer.Children.Add(done); }
    }

    void Show(SettingsSection section, bool animated)
    {
        browser.SettingsSection = section;
        foreach (var (s, item) in items) item.Selected = s == section;
        var store = browser.Store;
        var stack = new StackPanel { Spacing = Space.Section, Padding = new Thickness(28) };
        var title = Ui.Text(section.Title(store), 22); title.CharacterSpacing = -22;
        stack.Children.Add(title);
        stack.Children.Add(section switch
        {
            SettingsSection.Space => SettingsPages.Workspace(browser, dismiss),
            SettingsSection.Appearance => SettingsPages.Appearance(browser),
            SettingsSection.Start => SettingsPages.Start(browser),
            SettingsSection.Search => SettingsPages.Search(browser),
            SettingsSection.Session => SettingsPages.Session(browser),
            SettingsSection.Transfer => new Import.ImportView(browser),
            SettingsSection.Permissions => SettingsPages.Permissions(browser),
            SettingsSection.Passwords => new Passwords.PasswordSettings(browser),
            _ => SettingsPages.About(browser, dismiss),
        });
        var scroll = Ui.Scroll(stack); scroll.VerticalScrollBarVisibility = ScrollBarVisibility.Hidden;
        var host = new Grid(); host.RowDefinitions.Add(Ui.RowStar()); host.RowDefinitions.Add(Ui.RowAuto());
        host.Row(scroll, 0);
        if (section == SettingsSection.About) host.Row(Ui.Text(store.Text("develop whoa with ❤️", "Develop whoa with ❤️"), 12, Palette.Text3.Brush()).Margin(28, Space.Small, 28, 22), 1);
        pane.Children.Clear(); pane.Children.Add(host);
        if (animated) Motion.Appear(host, Motion.Edge.Bottom);
    }
}

/// <summary>Shared pickers (macOS Pickers.swift).</summary>
public static class Pickers
{
    public static ToggleRow SidebarToggle(Store s)
    {
        var row = new ToggleRow(s.Text("свернуть боковую панель до иконок", "Свернуть боковую панель до иконок"), s.Preferences.SidebarCollapsed, v => s.Change(p => p.SidebarCollapsed = v), divider: false);
        void Render() => row.Switch.IsEnabled = !s.Preferences.Layout.IsHorizontal();
        row.Bind(h => s.PreferencesUpdated += h, h => s.PreferencesUpdated -= h, Render);
        Render();
        return row;
    }
    public static Segmented<TabLayout> LayoutPicker(Store s, double width = 0)
    {
        var picker = new Segmented<TabLayout>(s.Preferences.Layout, [(TabLayout.Left, s.Text("слева", "Слева")), (TabLayout.Top, s.Text("под адресом", "Под адресом")), (TabLayout.TabsAbove, s.Text("над адресом", "Над адресом")), (TabLayout.Right, s.Text("справа", "Справа"))], minWidth: width, label: s.Text("вкладки", "Вкладки"), symbols: ["sidebar.left", "rectangle.topthird.inset.filled", "macwindow", "sidebar.right"]);
        picker.Changed += v => s.Change(p => p.Layout = v);
        return picker;
    }
    public static Segmented<Theme> ThemePicker(Store s, double width = 0)
    {
        var picker = new Segmented<Theme>(s.Preferences.Theme, [(Core.Theme.System, s.Text("системная", "Системная")), (Core.Theme.Light, s.Text("светлая", "Светлая")), (Core.Theme.Dark, s.Text("тёмная", "Тёмная")), (Core.Theme.Custom, s.Text("кастом", "Кастом"))], minWidth: width, label: s.Text("тема", "Тема"));
        picker.Changed += v => s.Change(p => p.Theme = v);
        return picker;
    }
    /// <summary>Each option is written in the style it selects.</summary>
    public static Segmented<bool> CasePicker(Store s, double width = 0)
    {
        var english = s.Preferences.Language == Language.En;
        var picker = new Segmented<bool>(s.Preferences.Lowercase, [(true, english ? "lowercase" : "со строчной"), (false, english ? "Standard" : "Обычный")], minWidth: width, label: s.Text("текст интерфейса", "Текст интерфейса"));
        picker.Changed += v => s.Change(p => p.Lowercase = v);
        return picker;
    }
    /// <summary>Language names are written in their own language.</summary>
    public static Segmented<Language> LanguagePicker(Store s, double width = 0)
    {
        var picker = new Segmented<Language>(s.Preferences.Language, [(Core.Language.Ru, s.Preferences.Lowercase ? "русский" : "Русский"), (Core.Language.En, s.Preferences.Lowercase ? "english" : "English")], minWidth: width, label: s.Text("язык", "Язык"));
        picker.Changed += v => s.Change(p => p.Language = v);
        return picker;
    }

    public static IEnumerable<UIElement> NameRows(Store s)
    {
        var field = new MTextField(s.Text("как к вам обращаться", "Как к вам обращаться"), s.Preferences.UserName, "person") { Width = 220, IsHitTestVisible = s.Preferences.GreetByName, Opacity = s.Preferences.GreetByName ? 1 : 0.45 };
        field.Box.MaxLength = Preferences.NameLimit;
        field.Box.TextChanged += (_, _) => s.Change(p => p.UserName = field.Text);
        yield return new SettingRow(s.Text("имя", "Имя"), field, s.Text("для приветствия на начальной странице", "Для приветствия на начальной странице"));
        yield return new ToggleRow(s.Text("не обращаться по имени", "Не обращаться по имени"), !s.Preferences.GreetByName, v => { s.Change(p => p.GreetByName = !v); field.IsHitTestVisible = !v; field.Opacity = v ? 0.45 : 1; }, divider: false);
    }

    public static UIElement Search(Store s)
    {
        var grid = new VariableSizedWrapGrid { Orientation = Orientation.Horizontal, ItemWidth = 156, ItemHeight = 42 };
        void Render()
        {
            grid.Children.Clear();
            foreach (var engine in SearchEngines.All)
            {
                var selected = s.Preferences.Search == engine;
                var plate = Ui.Rounded(Radius.Row, Palette.Track.Brush(), selected ? Palette.FocusRing.Brush() : null, 1.5);
                var row = new Grid { Padding = new Thickness(10, 0, 10, 0), ColumnSpacing = 8, Height = 36, Margin = new Thickness(3) };
                row.ColumnDefinitions.Add(Ui.Auto()); row.ColumnDefinitions.Add(Ui.Star()); row.ColumnDefinitions.Add(Ui.Auto());
                row.Children.Add(plate); Grid.SetColumnSpan(plate, 3); plate.Margin = new Thickness(-10, 0, -10, 0);
                row.Column(new Monogram(AddressParser.Host(engine.Home()), 20) { VerticalAlignment = VerticalAlignment.Center }, 0);
                row.Column(Ui.Text(engine.Title(s.Preferences.Language), 12.5, selected ? Palette.Ink.Brush() : Palette.Text2.Brush(), selected ? Ui.Medium : Ui.Regular), 1);
                if (selected) row.Column(new Glyph("checkmark", 10, Palette.Ink.Brush()) { VerticalAlignment = VerticalAlignment.Center }, 2);
                row.Background = Palette.Clear;
                var e = engine;
                var interaction = new Interaction(row, () => { }, 0.97);
                interaction.Invoked += () => { s.Change(p => p.Search = e); Render(); };
                row.PointerEntered += (_, _) => { if (!selected) plate.Background = Palette.Hover.Brush(); };
                row.PointerExited += (_, _) => plate.Background = Palette.Track.Brush();
                Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(row, engine.Title(s.Preferences.Language));
                grid.Children.Add(row);
            }
        }
        Render();
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(grid, s.Text("поисковик", "Поисковик"));
        return grid;
    }
}

/// <summary>Domains typed one by one; a draft not yet added is kept so closing settings can ask about it.</summary>
public sealed partial class HostListEditor : StackPanel
{
    public HostListEditor(Store store, Func<Preferences, List<string>> list)
    {
        var input = new MTextField("example.com", symbol: "globe");
        var add = new MButton(store.Text("добавить", "Добавить"), compact: true) { IsEnabled = false };
        var invalid = Ui.Text(store.Text("нужен домен без пути, например mail.example.com", "Нужен домен без пути, например mail.example.com"), 11.5, Palette.Danger.Brush());
        invalid.Visibility = Visibility.Collapsed; invalid.Margin = new Thickness(14, 0, 14, Space.Small);
        var top = new Grid { ColumnSpacing = Space.Small, Padding = new Thickness(10) };
        top.ColumnDefinitions.Add(Ui.Star()); top.ColumnDefinitions.Add(Ui.Auto());
        top.Column(input, 0); top.Column(add, 1);
        Children.Add(top); Children.Add(invalid);
        var rows = new StackPanel();
        Children.Add(rows);
        void Render()
        {
            rows.Children.Clear();
            foreach (var host in list(store.Preferences))
            {
                var row = new Grid { Padding = new Thickness(14, 6, 14, 6) };
                row.ColumnDefinitions.Add(Ui.Star()); row.ColumnDefinitions.Add(Ui.Auto());
                row.Column(Ui.Text(host, 13), 0);
                var remove = new IconButton("minus.circle", store.Text("удалить ", "Удалить ") + host, 24);
                var h = host;
                remove.Click += () => { store.Change(p => list(p).Remove(h)); Render(); };
                row.Column(remove, 1);
                rows.Children.Add(Ui.V(0, Ui.Hairline(), row));
            }
        }
        void Add()
        {
            var host = input.Text.Trim().ToLowerInvariant();
            if (!Uri.TryCreate("https://" + host, UriKind.Absolute, out var url) || url.Host != host || url.AbsolutePath != "/" || !host.Contains('.')) { invalid.Visibility = Visibility.Visible; return; }
            invalid.Visibility = Visibility.Collapsed;
            if (!list(store.Preferences).Contains(host)) store.Change(p => list(p).Add(host));
            input.Text = ""; SettingsOverlay.Draft = "";
            Render();
        }
        input.Box.TextChanged += (_, _) => { add.IsEnabled = input.Text.Length > 0; SettingsOverlay.Draft = input.Text; };
        input.Submit += Add; add.Click += Add;
        Render();
    }
}
