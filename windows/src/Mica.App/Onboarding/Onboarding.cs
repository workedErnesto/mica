using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Mica.Core;
using Mica.Design;
using Mica.App.Settings;

namespace Mica.App.Onboarding;

/// <summary>First run in six steps (macOS Onboarding): language and name, data transfer, layout, look, search and
/// protection, session. Every change applies at once and stays editable in settings.</summary>
public sealed partial class OnboardingView : Grid
{
    const int Steps = 6;
    readonly BrowserModel browser;
    readonly StackPanel nav = new() { Spacing = 2 };
    readonly Grid pane = new();
    readonly TextBlock counter;
    readonly MButton back, next;
    readonly List<NavItem> items = [];
    Store Store => browser.Store;

    public OnboardingView(BrowserModel browser)
    {
        this.browser = browser;
        var s = Store;
        ColumnDefinitions.Add(Ui.Fixed(228)); ColumnDefinitions.Add(Ui.Fixed(1)); ColumnDefinitions.Add(Ui.Star());
        var side = new Grid { Background = Look.Shell, Padding = new Thickness(Space.Normal) };
        side.RowDefinitions.Add(Ui.RowStar()); side.RowDefinitions.Add(Ui.RowAuto());
        var mark = Ui.Text("mica", 22, null, Ui.Weight(300)); mark.CharacterSpacing = -36; mark.Margin = new Thickness(10, 4, 10, Space.Normal);
        nav.Children.Add(mark);
        for (var i = 0; i < Steps; i++) { var index = i; var item = new NavItem(StepName(i), StepSymbol(i), i == browser.OnboardingStep, false, () => Go(index)); items.Add(item); nav.Children.Add(item); }
        side.Row(nav, 0);
        counter = Ui.Text("", 11.5, Palette.Text3.Brush()); counter.Margin = new Thickness(10, 0, 10, Space.Micro);
        side.Row(counter, 1);
        this.Column(side, 0);
        this.Column(Ui.Hairline(vertical: true), 1);
        var right = new Grid { Background = Palette.Canvas.Brush(), Padding = new Thickness(28) };
        right.RowDefinitions.Add(Ui.RowStar()); right.RowDefinitions.Add(Ui.RowAuto());
        right.Row(pane, 0);
        back = new MButton(s.Text("назад", "Назад"), ButtonKind.Ghost);
        back.Click += () => Go(browser.OnboardingStep - 1);
        next = new MButton("", ButtonKind.Primary) { HorizontalAlignment = HorizontalAlignment.Right };
        next.Click += () =>
        {
            if (browser.OnboardingStep < Steps - 1) Go(browser.OnboardingStep + 1);
            else { s.Change(p => p.OnboardingComplete = true); browser.ShowOnboarding = false; browser.FocusAddress(); }
        };
        var buttons = new Grid { Margin = new Thickness(0, Space.Normal, 0, 0) };
        buttons.Children.Add(back); buttons.Children.Add(next);
        right.Row(buttons, 1);
        this.Column(right, 2);
        Loaded += (_, _) => Show(true, animated: false);
        SizeChanged += (_, e) => { var compact = e.NewSize.Width < 720; ColumnDefinitions[0].Width = new GridLength(compact ? 60 : 228); mark.Visibility = counter.Visibility = compact ? Visibility.Collapsed : Visibility.Visible; };
    }

    void Go(int index)
    {
        if (index == browser.OnboardingStep || index < 0 || index >= Steps) return;
        var forward = index > browser.OnboardingStep;
        browser.OnboardingStep = index;
        Show(forward, animated: true);
    }

    void Show(bool forward, bool animated)
    {
        var s = Store;
        var step = browser.OnboardingStep;
        for (var i = 0; i < items.Count; i++) items[i].Selected = i == step;
        counter.Text = s.Text("шаг ", "Шаг ") + (step + 1) + " / " + Steps;
        back.Visibility = step > 0 ? Visibility.Visible : Visibility.Collapsed;
        next.Title = step == Steps - 1 ? s.Text("начать", "Начать") : s.Text("дальше", "Дальше");
        var title = Ui.Text(Title(step), 22); title.CharacterSpacing = -22;
        var header = Ui.V(6, title, Ui.Text(Subtitle(step), 13, Palette.Text2.Brush(), wrap: true));
        var content = Content(step);
        var scroll = Ui.Scroll(content); scroll.VerticalScrollBarVisibility = ScrollBarVisibility.Hidden; scroll.Margin = new Thickness(0, Space.Section, 0, 0);
        var page = new Grid(); page.RowDefinitions.Add(Ui.RowAuto()); page.RowDefinitions.Add(Ui.RowStar());
        page.Row(header, 0); page.Row(scroll, 1);
        pane.Children.Clear(); pane.Children.Add(page);
        if (animated) Motion.Appear(page, forward ? Motion.Edge.Trailing : Motion.Edge.Leading, Motion.Panel);
    }

    string StepName(int i) => i switch
    {
        0 => Store.Text("знакомство", "Знакомство"), 1 => Store.Text("перенос данных", "Перенос данных"), 2 => Store.Text("пространство", "Пространство"),
        3 => Store.Text("оформление", "Оформление"), 4 => Store.Text("поиск и защита", "Поиск и защита"), _ => Store.Text("сессия", "Сессия"),
    };
    static string StepSymbol(int i) => i switch { 0 => "hand.wave", 1 => "square.and.arrow.down.on.square", 2 => "sidebar.squares.left", 3 => "paintbrush", 4 => "shield.lefthalf.filled", _ => "square.stack" };
    string Title(int i) => i switch
    {
        0 => Store.Text("привет, это mica", "Привет, это mica"), 1 => Store.Text("всё уже на месте", "Всё уже на месте"), 2 => Store.Text("ваше пространство", "Ваше пространство"),
        3 => Store.Text("цвет и иконка", "Цвет и иконка"), 4 => Store.Text("спокойнее с первого запуска", "Спокойнее с первого запуска"), _ => Store.Text("работа остаётся с вами", "Работа остаётся с вами"),
    };
    string Subtitle(int i) => i switch
    {
        0 => Store.Text("язык, имя и стиль текста. всё можно поменять позже в настройках", "Язык, имя и стиль текста. Всё можно поменять позже в настройках"),
        1 => Store.Text("история и закладки из другого браузера. шаг можно пропустить", "История и закладки из другого браузера. Шаг можно пропустить"),
        2 => Store.Text("изменения видны сразу", "Изменения видны сразу"),
        3 => Store.Text("тема окна, акцент и иконка mica на панели задач", "Тема окна, акцент и иконка mica на панели задач"),
        4 => Store.Text("поиск, блокировка и разрешения", "Поиск, блокировка и разрешения"),
        _ => Store.Text("вкладки, сессия и клавиши", "Вкладки, сессия и клавиши"),
    };

    UIElement Content(int step)
    {
        var s = Store;
        switch (step)
        {
            case 0:
            {
                var group = new SettingsGroup().Add(new SettingRow(s.Text("язык", "Язык"), Pickers.LanguagePicker(s, 300))).Add(new SettingRow(s.Text("текст интерфейса", "Текст интерфейса"), Pickers.CasePicker(s, 300)));
                foreach (var row in Pickers.NameRows(s)) group.Add(row);
                return Ui.V(Space.Normal, new Appearance.GreetingPreview(s), new DefaultBrowserSetting(s), group);
            }
            case 1: return new Import.ImportView(browser);
            case 2:
                return Ui.V(Space.Normal, new Appearance.LayoutPreview(s) { Height = 150 }, new SettingsGroup()
                    .Add(new SettingRow(s.Text("вкладки", "Вкладки"), Pickers.LayoutPicker(s, 300)))
                    .Add(Pickers.SidebarToggle(s)));
            case 3:
                return Ui.V(Space.Normal, new Appearance.LayoutPreview(s) { Height = 120 }, SettingsPages.ThemeGroup(s),
                    new SettingsGroup().Add(new ToggleRow(s.Text("матовое стекло оболочки", "Матовое стекло оболочки"), s.ActivePrefs.Frosted, v => s.Change(p => p.Frosted = v), divider: false)),
                    new SettingsGroup(s.Text("иконка приложения", "Иконка приложения")).Add(new Appearance.IconPicker(s) { Margin = new Thickness(14) }));
            case 4:
                return Ui.V(Space.Normal, new SettingsGroup()
                        .Add(Ui.V(8, Ui.Text(s.Text("поисковик", "Поисковик"), 13), Pickers.Search(s)).Margin(14, 10, 14, 10))
                        .Add(Ui.Hairline().Margin(14, 0, 0, 0))
                        .Add(new ToggleRow(s.Text("блокировать рекламу и трекеры", "Блокировать рекламу и трекеры"), s.Preferences.Blocking, v => s.Change(p => p.Blocking = v), divider: false, detail: s.Text("локальная проверка запросов к известным сторонним доменам", "Локальная проверка запросов к известным сторонним доменам"))),
                    Note("hand.raised", s.Text("камера, микрофон и геолокация запрашиваются только по запросу сайта, с его адресом в вопросе", "Камера, микрофон и геолокация запрашиваются только по запросу сайта, с его адресом в вопросе")),
                    Note(Glyph.Incognito, s.Text("окна инкогнито не сохраняют историю, cookie и сессию", "Окна инкогнито не сохраняют историю, cookie и сессию")),
                    Note("arrow.down.circle", s.Text("список блокировки обновляется только вручную в настройках", "Список блокировки обновляется только вручную в настройках")));
            default:
            {
                ToggleRow? lazy = null;
                var group = new SettingsGroup(footnote: s.Text("после открытия вкладки остаются живыми, mica не выгружает страницы по таймеру. после сбоя восстановятся адреса, но не несохранённые формы.", "После открытия вкладки остаются живыми, mica не выгружает страницы по таймеру. После сбоя восстановятся адреса, но не несохранённые формы."))
                    .Add(new ToggleRow(s.Text("восстанавливать окна и вкладки", "Восстанавливать окна и вкладки"), s.Preferences.Restore, v => { s.Change(p => p.Restore = v); if (lazy is not null) lazy.Switch.IsEnabled = v; }));
                lazy = new ToggleRow(s.Text("загружать сохранённые вкладки при выборе", "Загружать сохранённые вкладки при выборе"), s.Preferences.LazyRestore, v => s.Change(p => p.LazyRestore = v), divider: false);
                group.Add(lazy);
                var keys = new Grid { ColumnSpacing = Space.Normal, RowSpacing = Space.Normal, Margin = new Thickness(0, Space.Small, 0, 0) };
                keys.ColumnDefinitions.Add(Ui.Star()); keys.ColumnDefinitions.Add(Ui.Star()); keys.RowDefinitions.Add(Ui.RowAuto()); keys.RowDefinitions.Add(Ui.RowAuto());
                var hints = new[] { ("address", s.Text("адрес и поиск", "Адрес и поиск")), ("tab", s.Text("новая вкладка", "Новая вкладка")), ("private", s.Text("окно инкогнито", "Окно инкогнито")), ("sidebar", s.Text("боковая панель", "Боковая панель")) };
                for (var i = 0; i < hints.Length; i++)
                {
                    var hint = KeyHint.Make(Keymap.Label(hints[i].Item1) ?? ""); hint.MinWidth = 44;
                    var cell = Ui.H(10, hint, Ui.Text(hints[i].Item2, 12.5, Palette.Text2.Brush()));
                    Grid.SetColumn(cell, i % 2); Grid.SetRow(cell, i / 2); keys.Children.Add(cell);
                }
                return Ui.V(Space.Normal, group, keys);
            }
        }
    }

    static StackPanel Note(string symbol, string text)
    {
        var badge = Ui.Rounded(7, Palette.Track.Brush(), child: new Glyph(symbol, 12, Palette.Text2.Brush()) { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center });
        badge.Width = 26; badge.Height = 26;
        return Ui.H(10, badge, Ui.Text(text, 12.5, Palette.Text2.Brush(), wrap: true));
    }
}
