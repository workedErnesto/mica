using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Mica.Core;
using Mica.Design;

namespace Mica.App.Settings;

/// <summary>Settings sections (macOS Settings/Sections). Windows-specific wording replaces macOS where the system
/// differs: Windows privacy settings, default apps, the taskbar instead of the Dock.</summary>
public static class SettingsPages
{
    static StackPanel Page(params UIElement[] parts) => Ui.V(Mica.Design.Space.Section, parts);

    public static UIElement Workspace(BrowserModel b, Action dismiss)
    {
        var s = b.Store;
        var layout = new SettingsGroup(s.Text("раскладка", "Раскладка"), s.Text("при ширине окна меньше 760 px вкладки временно переходят наверх. в свёрнутой боковой панели остаются иконки сайтов, ", "При ширине окна меньше 760 px вкладки временно переходят наверх. В свёрнутой боковой панели остаются иконки сайтов, ") + (Keymap.Label("sidebar") ?? "Ctrl+Shift+S") + ".")
            .Add(new SettingRow(s.Text("вкладки", "Вкладки"), Pickers.LayoutPicker(s, 260)))
            .Add(Pickers.SidebarToggle(s));
        var customize = new MButton(s.Text("настроить", "Настроить"), compact: true);
        customize.Click += () => { dismiss(); b.CustomizingToolbar = true; };
        var toolbar = new SettingsGroup(s.Text("панель инструментов", "Панель инструментов"), s.Text("кнопки расставляются перетаскиванием прямо в окне: в шапку, вниз боковой панели или обратно в набор. то же меню есть в меню «…» и по правому клику на боковой панели.", "Кнопки расставляются перетаскиванием прямо в окне: в шапку, вниз боковой панели или обратно в набор. То же меню есть в меню «…» и по правому клику на боковой панели."))
            .Add(new SettingRow(s.Text("кнопки и адресная строка", "Кнопки и адресная строка"), customize, s.Text("порядок, сторона и длина строки", "Порядок, сторона и длина строки"), divider: false));
        return Page(new DefaultBrowserSetting(s), ProfileScope.Make(b), new Appearance.LayoutPreview(s) { Height = 168 }, layout, toolbar);
    }

    public static UIElement ThemeGroup(Store s)
    {
        var host = new Grid();
        void Render()
        {
            host.Children.Clear();
            var custom = s.ActivePrefs.Theme == Theme.Custom;
            var group = new SettingsGroup(s.Text("тема", "Тема"), custom ? s.Text("акцент окрашивает оболочку, переключатели, основные кнопки и индикатор загрузки. страницы сайтов не меняются.", "Акцент окрашивает оболочку, переключатели, основные кнопки и индикатор загрузки. Страницы сайтов не меняются.") : null);
            var theme = Pickers.ThemePicker(s, 380);
            theme.Changed += _ => host.DispatcherQueue.TryEnqueue(Render);
            group.Add(new SettingRow(s.Text("тема", "Тема"), theme, divider: custom));
            if (custom)
            {
                var basis = new Segmented<Theme>(s.ActivePrefs.CustomBase, [(Theme.System, s.Text("как в системе", "Как в системе")), (Theme.Light, s.Text("светлая", "Светлая")), (Theme.Dark, s.Text("тёмная", "Тёмная"))], minWidth: 380, label: s.Text("основа темы", "Основа темы"));
                basis.Changed += v => s.Change(p => p.CustomBase = v);
                group.Add(new SettingRow(s.Text("основа", "Основа"), basis));
                group.Add(new SettingRow(s.Text("акцент", "Акцент"), new Appearance.AccentPicker(s)));
                var tint = new MSlider(s.ActivePrefs.CustomTint, 0, 0.6, s.Text("цвет оболочки", "Цвет оболочки")) { Width = 180 };
                var value = Ui.Text(Math.Round(s.ActivePrefs.CustomTint / 0.6 * 100) + "%", 11.5, Palette.Text3.Brush()); value.Width = 34; value.TextAlignment = TextAlignment.Right;
                tint.Changed += v => { value.Text = Math.Round(v / 0.6 * 100) + "%"; s.Change(p => p.CustomTint = v); };
                group.Add(new SettingRow(s.Text("цвет оболочки", "Цвет оболочки"), Ui.H(Mica.Design.Space.Small, tint, value), s.Text("насколько акцент окрашивает фон окна", "Насколько акцент окрашивает фон окна"), divider: false));
            }
            host.Children.Add(group);
        }
        Render();
        return host;
    }

    public static UIElement Appearance(BrowserModel b)
    {
        var s = b.Store;
        var transparency = new MSlider(s.ActivePrefs.Transparency, 0, 1, s.Text("прозрачность", "Прозрачность")) { Width = 180, IsEnabled = s.ActivePrefs.Frosted };
        var percent = Ui.Text(Math.Round(s.ActivePrefs.Transparency * 100) + "%", 11.5, Palette.Text3.Brush()); percent.Width = 34; percent.TextAlignment = TextAlignment.Right;
        transparency.Changed += v => { percent.Text = Math.Round(v * 100) + "%"; s.Change(p => p.Transparency = v); };
        var material = new SettingsGroup(s.Text("материал оболочки", "Материал оболочки"), s.Text("размытие и прозрачность относятся только к оболочке, страницы остаются непрозрачными. выключенные «эффекты прозрачности» windows и контрастные темы имеют приоритет.", "Размытие и прозрачность относятся только к оболочке, страницы остаются непрозрачными. Выключенные «Эффекты прозрачности» Windows и контрастные темы имеют приоритет."))
            .Add(new ToggleRow(s.Text("матовое стекло", "Матовое стекло"), s.ActivePrefs.Frosted, v => { s.Change(p => p.Frosted = v); transparency.IsEnabled = v; }))
            .Add(new SettingRow(s.Text("прозрачность", "Прозрачность"), Ui.H(Mica.Design.Space.Small, transparency, percent), divider: false));
        var icon = new SettingsGroup(s.Text("иконка приложения", "Иконка приложения"), s.Text("иконка меняется на панели задач и в переключателе окон, пока mica открыта. ярлыки в меню «пуск» и закреплённый значок остаются стандартными.", "Иконка меняется на панели задач и в переключателе окон, пока mica открыта. Ярлыки в меню «Пуск» и закреплённый значок остаются стандартными."))
            .Add(new Appearance.IconPicker(s) { Margin = new Thickness(14) });
        var language = new SettingsGroup(s.Text("язык и текст", "Язык и текст"), s.Text("язык меняет только интерфейс mica. страницы сайтов, адреса и ваши данные не переводятся.", "Язык меняет только интерфейс mica. Страницы сайтов, адреса и ваши данные не переводятся."))
            .Add(new SettingRow(s.Text("язык", "Язык"), Pickers.LanguagePicker(s, 260)))
            .Add(new SettingRow(s.Text("текст интерфейса", "Текст интерфейса"), Pickers.CasePicker(s, 260), divider: false));
        return Page(ProfileScope.Make(b), new Appearance.LayoutPreview(s) { Height = 168 }, ThemeGroup(s), material, icon, language);
    }

    public static UIElement Start(BrowserModel b)
    {
        var s = b.Store;
        var host = new StackPanel { Spacing = Mica.Design.Space.Section };
        void Render()
        {
            host.Children.Clear();
            host.Children.Add(ProfileScope.Make(b));
            var start = s.ActivePrefs.Start;
            var greeting = new SettingsGroup(s.Text("приветствие", "Приветствие"), s.Text("с именем над поиском появляется приветствие, без имени остаётся знак mica. имя хранится только на этом компьютере.", "С именем над поиском появляется приветствие, без имени остаётся знак mica. Имя хранится только на этом компьютере."));
            foreach (var row in Pickers.NameRows(s)) greeting.Add(row);
            host.Children.Add(greeting);
            var show = new SettingsGroup(s.Text("что показывать", "Что показывать"), s.Text("стрелки меняют порядок разделов. частые сайты считаются по истории обычных окон и не показываются в окне инкогнито.", "Стрелки меняют порядок разделов. Частые сайты считаются по истории обычных окон и не показываются в окне инкогнито."));
            show.Add(new ToggleRow(s.Text("приветствие или знак mica", "Приветствие или знак mica"), start.Wordmark, v => s.Change(p => p.Start.Wordmark = v)));
            foreach (var section in start.Sections.Concat(Enum.GetValues<StartSection>().Where(x => !start.Sections.Contains(x))).ToList())
            {
                var visible = start.Sections.Contains(section);
                var toggle = new Switch(visible, StartPage.StartSections.Title(section, s));
                toggle.Toggled += v => { s.Change(p => p.Start.SetVisible(section, v)); Render(); };
                var up = new IconButton("chevron.up", s.Text("выше", "Выше") + ": " + StartPage.StartSections.Title(section, s), 22) { IsEnabled = visible && start.Sections.FirstOrDefault() != section };
                up.Click += () => { s.Change(p => p.Start.Shift(section, -1)); Render(); };
                var down = new IconButton("chevron.down", s.Text("ниже", "Ниже") + ": " + StartPage.StartSections.Title(section, s), 22) { IsEnabled = visible && start.Sections.LastOrDefault() != section };
                down.Click += () => { s.Change(p => p.Start.Shift(section, 1)); Render(); };
                show.Add(new SettingRow(StartPage.StartSections.Title(section, s), Ui.H(Mica.Design.Space.Normal, toggle, Ui.H(0, up, down))));
            }
            var count = new Segmented<int>(start.FrequentCount, Mica.Core.StartPage.FrequentChoices.Select(c => (c, c.ToString())), compact: true, minWidth: 180, label: s.Text("сайтов в разделе", "Сайтов в разделе"));
            count.Changed += v => s.Change(p => p.Start.FrequentCount = v);
            show.Add(new SettingRow(s.Text("сайтов в разделе", "Сайтов в разделе"), count, s.Text("для частых сайтов и закладок", "Для частых сайтов и закладок"), divider: false));
            host.Children.Add(show);
            var own = new SettingsGroup(s.Text("свои сайты", "Свои сайты"), s.Text("на начальной странице плитки можно перетаскивать, контекстное меню изменяет и удаляет их.", "На начальной странице плитки можно перетаскивать, контекстное меню изменяет и удаляет их."));
            for (var i = 0; i < start.Shortcuts.Count; i++)
            {
                var shortcut = start.Shortcuts[i]; var id = shortcut.Id;
                var up = new IconButton("chevron.up", s.Text("выше", "Выше"), 22) { IsEnabled = i > 0 }; up.Click += () => { s.Change(p => p.Start.ShiftShortcut(id, -1)); Render(); };
                var down = new IconButton("chevron.down", s.Text("ниже", "Ниже"), 22) { IsEnabled = i < start.Shortcuts.Count - 1 }; down.Click += () => { s.Change(p => p.Start.ShiftShortcut(id, 1)); Render(); };
                var remove = new IconButton("minus.circle", s.Text("удалить ", "Удалить ") + AddressParser.Host(shortcut.Url), 22); remove.Click += () => { s.Change(p => p.Start.Shortcuts.RemoveAll(x => x.Id == id)); Render(); };
                own.Add(new SettingRow(shortcut.Title.Length == 0 ? AddressParser.Host(shortcut.Url) ?? shortcut.Url : shortcut.Title, Ui.H(0, up, down, remove), shortcut.Url));
            }
            var input = new MTextField(s.Text("адрес сайта", "Адрес сайта"), symbol: "plus");
            var add = new MButton(s.Text("добавить", "Добавить"), compact: true) { IsEnabled = false };
            var invalid = Ui.Text(s.Text("нужен адрес сайта, а не поисковый запрос", "Нужен адрес сайта, а не поисковый запрос"), 11.5, Palette.Danger.Brush()); invalid.Visibility = Visibility.Collapsed;
            void Add()
            {
                if (Mica.Core.StartPage.ShortcutUrl(input.Text, s.Preferences.Search) is not { } url) { invalid.Visibility = Visibility.Visible; return; }
                s.Change(p => { p.Start.Shortcuts.Add(new StartShortcut { Url = url }); p.Start.SetVisible(StartSection.Custom, true); });
                SettingsOverlay.Draft = ""; Render();
            }
            input.Box.TextChanged += (_, _) => { add.IsEnabled = input.Text.Trim().Length > 0; SettingsOverlay.Draft = input.Text; invalid.Visibility = Visibility.Collapsed; };
            input.Submit += Add; add.Click += Add;
            var addRow = new Grid { ColumnSpacing = Mica.Design.Space.Small }; addRow.ColumnDefinitions.Add(Ui.Star()); addRow.ColumnDefinitions.Add(Ui.Auto());
            addRow.Column(input, 0); addRow.Column(add, 1);
            own.Add(Ui.V(6, addRow, invalid).Margin(10));
            host.Children.Add(own);
            if (start.HiddenHosts.Count > 0)
            {
                var hidden = new SettingsGroup(s.Text("скрытые из частых", "Скрытые из частых"));
                foreach (var h in start.HiddenHosts.ToList())
                {
                    var back = new MButton(s.Text("вернуть", "Вернуть"), ButtonKind.Ghost, compact: true);
                    back.Click += () => { s.Change(p => p.Start.HiddenHosts.Remove(h)); Render(); };
                    hidden.Add(new SettingRow(h, back, divider: h != start.HiddenHosts[^1]));
                }
                host.Children.Add(hidden);
            }
        }
        Render();
        return host;
    }

    public static UIElement Search(BrowserModel b)
    {
        var s = b.Store;
        var search = new SettingsGroup(s.Text("поиск", "Поиск"), s.Text("запрос из адресной строки уходит только выбранному поисковику", "Запрос из адресной строки уходит только выбранному поисковику")).Add(((FrameworkElement)Pickers.Search(s)).Margin(10));
        var update = new MButton(s.Blocker.Updating ? s.Text("обновление…", "Обновление…") : s.Text("обновить", "Обновить"), compact: true) { IsEnabled = !s.Blocker.Updating };
        update.Click += async () => { update.IsEnabled = false; update.Title = s.Text("обновление…", "Обновление…"); await s.Blocker.UpdateAsync(); update.IsEnabled = true; update.Title = s.Text("обновить", "Обновить"); };
        var detail = s.Blocker.Count + s.Text(" доменов. ", " доменов. ") + (s.Blocker.Status.Length == 0 ? s.Text("обновление только по кнопке, запрос к pgl.yoyo.org", "Обновление только по кнопке, запрос к pgl.yoyo.org") : s.Blocker.Status);
        var blocking = new SettingsGroup(s.Text("блокировка", "Блокировка"))
            .Add(new ToggleRow(s.Text("блокировать рекламу и трекеры", "Блокировать рекламу и трекеры"), s.Preferences.Blocking, v => s.Change(p => p.Blocking = v), detail: s.Text("только сторонние запросы, без косметических фильтров", "Только сторонние запросы, без косметических фильтров")))
            .Add(new SettingRow(s.Text("список Peter Lowe", "Список Peter Lowe"), update, detail, divider: false, info: s.Text("открытый список доменов рекламных сетей и счётчиков, который Peter Lowe ведёт на pgl.yoyo.org. mica проверяет по нему каждый запрос страницы к чужому домену и не даёт загрузить баннеры, пиксели и скрипты слежки. сам сайт открывается как обычно. список встроен в приложение и работает без сети. «обновить» скачивает свежую версию, по расписанию mica в сеть не ходит.", "Открытый список доменов рекламных сетей и счётчиков, который Peter Lowe ведёт на pgl.yoyo.org. mica проверяет по нему каждый запрос страницы к чужому домену и не даёт загрузить баннеры, пиксели и скрипты слежки. Сам сайт открывается как обычно. Список встроен в приложение и работает без сети. «Обновить» скачивает свежую версию, по расписанию mica в сеть не ходит.")));
        var page = Page(search, blocking);
        if (s.Preferences.BlockingExceptions.Count > 0)
        {
            var exceptions = new SettingsGroup(s.Text("сайты без блокировки", "Сайты без блокировки"));
            foreach (var host in s.Preferences.BlockingExceptions.ToList())
            {
                var back = new MButton(s.Text("вернуть блокировку", "Вернуть блокировку"), ButtonKind.Ghost, compact: true);
                var row = new SettingRow(host, back, divider: host != s.Preferences.BlockingExceptions[^1]);
                back.Click += () => { s.Change(p => p.BlockingExceptions.Remove(host)); exceptions.Rows.Children.Remove(row); };
                exceptions.Add(row);
            }
            page.Children.Add(exceptions);
        }
        var clear = new MButton(s.Text("очистить…", "Очистить…"), ButtonKind.Destructive, compact: true);
        clear.Click += () => b.ShowClearData = true;
        page.Children.Add(new SettingsGroup(s.Text("данные", "Данные")).Add(new SettingRow(s.Text("история и данные сайтов", "История и данные сайтов"), clear, s.Text("cookie, кэш и локальное хранилище обычных окон", "Cookie, кэш и локальное хранилище обычных окон"), divider: false)));
        return page;
    }

    public static UIElement Session(BrowserModel b)
    {
        var s = b.Store;
        ToggleRow? lazy = null;
        var startup = new SettingsGroup(s.Text("при запуске", "При запуске"), s.Text("это касается только запуска. открытые вами вкладки остаются живыми, включая фоновые. несохранённые формы после сбоя не восстанавливаются.", "Это касается только запуска. Открытые вами вкладки остаются живыми, включая фоновые. Несохранённые формы после сбоя не восстанавливаются."))
            .Add(new ToggleRow(s.Text("восстанавливать окна и вкладки", "Восстанавливать окна и вкладки"), s.Preferences.Restore, v => { s.Change(p => p.Restore = v); if (lazy is not null) lazy.Switch.IsEnabled = v; }));
        lazy = new ToggleRow(s.Text("загружать сохранённые вкладки при выборе", "Загружать сохранённые вкладки при выборе"), s.Preferences.LazyRestore, v => s.Change(p => p.LazyRestore = v), divider: false);
        lazy.Switch.IsEnabled = s.Preferences.Restore;
        startup.Add(lazy);
        var eager = new SettingsGroup(s.Text("всегда загружать при запуске", "Всегда загружать при запуске"), s.Text("например, почта или мессенджер, которым нужны уведомления сразу", "Например, почта или мессенджер, которым нужны уведомления сразу")).Add(new HostListEditor(s, p => p.EagerHosts));
        var memory = new SettingsGroup(s.Text("память", "Память"), s.Text("WebView2 не сообщает надёжно о звонках, формах и WebSocket, поэтому mica не выгружает живые вкладки. автоматического таймера выгрузки нет; скрытые вкладки сами притормаживает Chromium.", "WebView2 не сообщает надёжно о звонках, формах и WebSocket, поэтому mica не выгружает живые вкладки. Автоматического таймера выгрузки нет; скрытые вкладки сами притормаживает Chromium."))
            .Add(new SettingRow(s.Text("выгрузка живых вкладок", "Выгрузка живых вкладок"), Ui.Text(s.Text("выключена", "Выключена"), 12, Palette.Text3.Brush()), divider: false));
        return Page(startup, eager, memory);
    }

    public static UIElement Permissions(BrowserModel b)
    {
        var s = b.Store;
        var system = new SettingsGroup("Windows", s.Text("системный доступ к камере, микрофону, геолокации и уведомлениям меняется в параметрах windows", "Системный доступ к камере, микрофону, геолокации и уведомлениям меняется в параметрах Windows"));
        foreach (var (title, uri) in new[] { (s.CapabilityName(SiteCapability.Camera), "ms-settings:privacy-webcam"), (s.CapabilityName(SiteCapability.Microphone), "ms-settings:privacy-microphone"), (s.CapabilityName(SiteCapability.Location), "ms-settings:privacy-location"), (s.CapabilityName(SiteCapability.Notifications), "ms-settings:notifications") })
        {
            var open = new MButton(s.Text("открыть", "Открыть"), compact: true);
            open.Click += async () => await Windows.System.Launcher.LaunchUriAsync(new Uri(uri));
            system.Add(new SettingRow(title, open, divider: uri != "ms-settings:notifications"));
        }
        var notifications = new SettingsGroup(s.Text("уведомления сайтов", "Уведомления сайтов"), s.Text("уведомления приходят от открытых вкладок. push-уведомления закрытых сайтов не поддерживаются. в окнах инкогнито уведомления запрещены.", "Уведомления приходят от открытых вкладок. Push-уведомления закрытых сайтов не поддерживаются. В окнах инкогнито уведомления запрещены."))
            .Add(new ToggleRow(s.Text("сайты могут спрашивать разрешение", "Сайты могут спрашивать разрешение"), s.Preferences.NotificationRequests, v => s.Change(p => p.NotificationRequests = v), divider: false));
        var decisions = new SettingsGroup(s.Text("решения для сайтов", "Решения для сайтов"), s.Text("решения окон инкогнито существуют только внутри окна.", "Решения окон инкогнито существуют только внутри окна."));
        if (s.Permissions.Count == 0) decisions.Add(Ui.Text(s.Text("сайты пока ничего не запрашивали", "Сайты пока ничего не запрашивали"), 13, Palette.Text3.Brush()).Margin(14));
        for (var i = 0; i < s.Permissions.Count; i++)
        {
            var record = s.Permissions[i];
            var picker = new Segmented<Decision>(record.Decision, [(Decision.Ask, s.Text("спрашивать", "Спрашивать")), (Decision.Allow, s.Text("разрешить", "Разрешить")), (Decision.Deny, s.Text("запретить", "Запретить"))], compact: true, minWidth: 270, label: record.Origin);
            picker.Changed += d => s.SetPermission(record.Origin, record.Capability, d);
            decisions.Add(new SettingRow(record.Origin, picker, s.CapabilityName(record.Capability), divider: i < s.Permissions.Count - 1));
        }
        return Page(system, notifications, decisions);
    }

    public static UIElement About(BrowserModel b, Action dismiss)
    {
        var s = b.Store;
        var intro = Ui.V(Mica.Design.Space.Normal,
            Ui.Text(s.Text("mica — браузер, в котором вкладки не перезагружаются, когда вы к ним возвращаетесь: страница остаётся такой, какой вы её оставили.", "mica — браузер, в котором вкладки не перезагружаются, когда вы к ним возвращаетесь: страница остаётся такой, какой вы её оставили."), 13.5, Palette.Text2.Brush(), wrap: true),
            Ui.Text(s.Text("реклама и трекеры блокируются сразу, расширения ставятся из Chrome Web Store. собственной телеметрии нет.", "Реклама и трекеры блокируются сразу, расширения ставятся из Chrome Web Store. Собственной телеметрии нет."), 13.5, Palette.Text2.Brush(), wrap: true));
        intro.MaxWidth = 520; intro.HorizontalAlignment = HorizontalAlignment.Left;
        var version = Ui.Text(Update.Updater.CurrentVersion?.ToString() ?? "?", 12, Palette.Text2.Brush());
        var engine = Ui.Text("WebView2 " + (s.Engine.RuntimeVersion ?? "?"), 12, Palette.Text2.Brush());
        var group = new SettingsGroup()
            .Add(new SettingRow(s.Text("версия", "Версия"), version))
            .Add(new SettingRow(s.Text("движок", "Движок"), engine))
            .Add(new ToggleRow(s.Text("проверять обновления каждый день", "Проверять обновления каждый день"), s.Preferences.UpdateChecks, s.Updater.EnableChecks, divider: false));
        var again = new MButton(s.Text("пройти знакомство ещё раз", "Пройти знакомство ещё раз"));
        again.Click += () => { dismiss(); b.OnboardingStep = 0; b.ShowOnboarding = true; };
        return Page(intro, group, again);
    }
}

/// <summary>Default browser on Windows: mica registers its capabilities for the current user, then Windows Settings
/// confirms the choice. Windows does not let apps switch the default themselves.</summary>
public sealed partial class DefaultBrowserSetting : StackPanel
{
    public DefaultBrowserSetting(Store s)
    {
        Spacing = Mica.Design.Space.Small;
        var group = new SettingsGroup(s.Text("браузер по умолчанию", "Браузер по умолчанию"), s.Text("windows подтверждает выбор в параметрах: откроется раздел приложений по умолчанию с mica.", "Windows подтверждает выбор в параметрах: откроется раздел приложений по умолчанию с mica."));
        Children.Add(group);
        var failed = Ui.Text(s.Text("не удалось зарегистрировать mica как браузер. попробуйте ещё раз", "Не удалось зарегистрировать mica как браузер. Попробуйте ещё раз"), 12.5, Palette.Danger.Brush(), wrap: true, trim: false);
        failed.Visibility = Visibility.Collapsed;
        Children.Add(failed);
        bool? shown = null;
        var busy = false;
        void Render()
        {
            var isDefault = Mica.Install.DefaultBrowser.IsDefault();
            if (isDefault) failed.Visibility = Visibility.Collapsed;
            // Rebuilding only on a real change keeps the button that has focus or is being pressed in the tree.
            if (shown == isDefault) return;
            shown = isDefault;
            group.Rows.Children.Clear();
            var button = new MButton(s.Text("сделать основным", "Сделать основным"), compact: true) { Visibility = isDefault ? Visibility.Collapsed : Visibility.Visible, IsEnabled = !busy };
            button.Click += async () =>
            {
                if (busy) return;
                busy = true; button.IsEnabled = false; failed.Visibility = Visibility.Collapsed;
                try { Mica.Install.DefaultBrowser.Register(); await Mica.Install.DefaultBrowser.OpenSettingsAsync(); }
                catch (Exception e) when (e is UnauthorizedAccessException or IOException or System.Security.SecurityException)
                {
                    Diagnostics.Log.Error(e); failed.Visibility = Visibility.Visible;
                }
                finally { busy = false; button.IsEnabled = true; }
            };
            group.Add(new SettingRow(isDefault ? s.Text("mica открывает веб-ссылки", "mica открывает веб-ссылки") : s.Text("открывать веб-ссылки в mica", "Открывать веб-ссылки в mica"), button, divider: false));
        }
        Render();
        // Returning from Windows Settings re-checks the state. The handler lives only while the page is shown,
        // so reopening settings does not stack handlers on the window root.
        FrameworkElement? root = null;
        RoutedEventHandler recheck = (_, _) => Render();
        Loaded += (_, _) => { if (root is null && XamlRoot?.Content is FrameworkElement r) { root = r; r.GotFocus += recheck; } Render(); };
        Unloaded += (_, _) => { if (root is not null) root.GotFocus -= recheck; root = null; };
    }
}
