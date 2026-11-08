using System.Numerics;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Markup;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Microsoft.UI.Xaml.XamlTypeInfo;
using Mica.Core;
using Mica.Design;
using Mica.Install;

namespace Mica.Setup;

public static class Program
{
    public static string[] Arguments { get; private set; } = [];
    public static bool Has(string flag) => Arguments.Contains(flag);
    public static void Trace(string message)
    {
        if (Has("--self-test")) File.AppendAllText(Path.Combine(Path.GetTempPath(), "mica-setup-self-test.log"), message + Environment.NewLine);
    }

    [STAThread]
    static int Main(string[] args)
    {
        Arguments = args;
        Trace("main");
        using var single = new Mutex(true, "mica-setup", out var first);
        if (!first) return 0;
        WinRT.ComWrappersSupport.InitializeComWrappers();
        Trace("com wrappers initialized");
        Application.Start(callback =>
        {
            Trace("application callback");
            SynchronizationContext.SetSynchronizationContext(new DispatcherQueueSynchronizationContext(DispatcherQueue.GetForCurrentThread()));
            _ = new SetupApplication();
            Trace("application created");
        });
        return 0;
    }
}

/// <summary>mica Setup: one window in mica's own design. Installs for the current user without administrator rights,
/// registers mica as a browser, creates shortcuts and the "Installed apps" entry; --update replaces a running copy
/// and starts it again; --quiet installs with defaults and exits (CI). --self-test only opens the window and closes
/// it, so CI can check that WinUI starts from the single-file build.</summary>
public sealed partial class SetupApplication : Application, IXamlMetadataProvider
{
    public SetupApplication()
    {
        ResourceManagerRequested += (_, e) =>
        {
            var pri = Path.Combine(AppContext.BaseDirectory, "mica-setup.pri");
            Program.Trace("resource index: " + pri + " exists=" + File.Exists(pri));
            if (File.Exists(pri)) e.CustomResourceManager = new Microsoft.Windows.ApplicationModel.Resources.ResourceManager(pri);
        };
        UnhandledException += (_, e) => Program.Trace("unhandled: " + e.Message + " " + e.Exception);
        Program.Trace("application constructor");
    }
    readonly XamlControlsXamlMetaDataProvider provider = new();
    public IXamlType GetXamlType(Type type) => provider.GetXamlType(type);
    public IXamlType GetXamlType(string fullName) => provider.GetXamlType(fullName);
    public XmlnsDefinition[] GetXmlnsDefinitions() => provider.GetXmlnsDefinitions();
    public Window? Window { get; private set; }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        Program.Trace("launched");
        Resources.MergedDictionaries.Add(new XamlControlsResources());
        Program.Trace("resources loaded");
        var settings = new Windows.UI.ViewManagement.UISettings();
        Palette.Apply(settings.GetColorValue(Windows.UI.ViewManagement.UIColorType.Background).R < 128, new Windows.UI.ViewManagement.AccessibilitySettings().HighContrast);
        Look.Apply(false, "#6E56CF", 0);
        Window = new Window { ExtendsContentIntoTitleBar = true, Title = "mica" };
        Program.Trace("window created");
        var scale = Win32Dpi.Scale(Window);
        Window.AppWindow.Resize(new Windows.Graphics.SizeInt32((int)(640 * scale), (int)(460 * scale)));
        if (Window.AppWindow.Presenter is OverlappedPresenter presenter) { presenter.IsResizable = false; presenter.IsMaximizable = false; }
        var area = DisplayArea.GetFromWindowId(Window.AppWindow.Id, DisplayAreaFallback.Primary).WorkArea;
        Window.AppWindow.Move(new Windows.Graphics.PointInt32(area.X + (area.Width - Window.AppWindow.Size.Width) / 2, area.Y + (area.Height - Window.AppWindow.Size.Height) / 2));
        Window.AppWindow.TitleBar.ButtonBackgroundColor = Microsoft.UI.Colors.Transparent;
        Window.AppWindow.TitleBar.ButtonInactiveBackgroundColor = Microsoft.UI.Colors.Transparent;
        Window.AppWindow.TitleBar.ButtonForegroundColor = Palette.Ink.Resolve();
        var transparency = settings.AdvancedEffectsEnabled && !Palette.Contrast;
        if (transparency) Window.SystemBackdrop = Microsoft.UI.Composition.SystemBackdrops.MicaController.IsSupported() ? new MicaBackdrop() : new DesktopAcrylicBackdrop();
        var view = new SetupView(this, transparency);
        Program.Trace("view created");
        Window.Content = view;
        Window.Activate();
        Program.Trace("window activated");
        if (Program.Has("--self-test")) { var t = DispatcherQueue.GetForCurrentThread().CreateTimer(); t.Interval = TimeSpan.FromSeconds(3); t.Tick += (_, _) => Exit(); t.Start(); }
    }
}

static partial class Win32Dpi
{
    [System.Runtime.InteropServices.LibraryImport("user32.dll")] private static partial uint GetDpiForWindow(nint hwnd);
    public static double Scale(Window window) { var dpi = GetDpiForWindow(WinRT.Interop.WindowNative.GetWindowHandle(window)); return dpi == 0 ? 1 : dpi / 96.0; }
}

/// <summary>The pages of Setup. Every page is built from fresh elements: moving one element between pages left
/// UI Automation with a broken tree, so screen readers and the click test saw an empty window after the first step.</summary>
public sealed partial class SetupView : Grid
{
    readonly SetupApplication app;
    readonly Grid page = new();
    readonly BitmapImage iconSource = LoadIcon();
    readonly Language language = LanguageInfo.Preferred();
    string folder = InstallLayout.InstalledFolder() ?? InstallLayout.DefaultFolder;
    bool desktop, makeDefault;
    readonly string version = typeof(SetupView).Assembly.GetName().Version is { } v ? $"{v.Major}.{v.Minor}.{v.Build}" : "?";
    string T(string low, string regular) => Copy.Text(low, regular, true, language);

    public SetupView(SetupApplication app, bool transparent)
    {
        this.app = app;
        RequestedTheme = Palette.ElementTheme;
        Background = transparent ? new SolidColorBrush(Palette.WithAlpha(Palette.Shell.Resolve(), 0.55)) : Palette.Shell.Brush();
        Children.Add(page);
        Loaded += (_, _) =>
        {
            if (Program.Has("--update")) _ = Install(update: true);
            else if (Program.Has("--quiet")) _ = Install(update: false);
            else if (Runtime.WebView2Version() is null) ShowRuntime();
            else ShowWelcome();
        };
    }

    static BitmapImage LoadIcon()
    {
        var image = new BitmapImage();
        using var stream = typeof(SetupView).Assembly.GetManifestResourceStream("mica.icon.png");
        if (stream is not null)
        {
            var memory = new Windows.Storage.Streams.InMemoryRandomAccessStream();
            using (var writer = new Windows.Storage.Streams.DataWriter(memory.GetOutputStreamAt(0)))
            {
                var bytes = new byte[stream.Length]; stream.ReadExactly(bytes);
                writer.WriteBytes(bytes); writer.StoreAsync().AsTask().Wait(); writer.DetachStream();
            }
            memory.Seek(0);
            image.SetSource(memory);
        }
        return image;
    }

    void Show(UIElement content, Motion.Edge edge = Motion.Edge.Bottom)
    {
        page.Children.Clear();
        page.Children.Add(content);
        Motion.Appear(content, edge, Motion.Panel);
    }

    /// <summary>Content of a page above an optional footer line; scrolls only if large text makes it taller than the window.</summary>
    static Grid Layout(UIElement body, UIElement? footer = null)
    {
        var root = new Grid(); root.RowDefinitions.Add(Ui.RowStar()); root.RowDefinitions.Add(Ui.RowAuto());
        root.Row(Ui.Scroll(body), 0);
        if (footer is not null) root.Row(footer, 1);
        return root;
    }

    StackPanel Hero(string title, string subtitle, out Image icon)
    {
        icon = new Image { Width = 88, Height = 88, Source = iconSource, HorizontalAlignment = HorizontalAlignment.Center };
        AutomationProperties.SetAccessibilityView(icon, Microsoft.UI.Xaml.Automation.Peers.AccessibilityView.Raw);
        var name = Ui.Text(title, 34, null, Ui.Weight(300)); name.CharacterSpacing = -30; name.HorizontalAlignment = HorizontalAlignment.Center; name.TextAlignment = TextAlignment.Center;
        var sub = Ui.Text(subtitle, 13.5, Palette.Text2.Brush(), wrap: true); sub.HorizontalAlignment = HorizontalAlignment.Center; sub.TextAlignment = TextAlignment.Center; sub.MaxWidth = 420;
        return Ui.V(Space.Normal, icon, name, sub);
    }

    static StackPanel Column(double top) => new() { Spacing = Space.Section, Padding = new Thickness(48, top, 48, 24) };

    static MButton Primary(string title, string id)
    {
        var button = new MButton(title, ButtonKind.Primary) { Width = 220, HorizontalAlignment = HorizontalAlignment.Center };
        AutomationProperties.SetAutomationId(button, id);
        return button;
    }

    static MButton Secondary(string title, string id)
    {
        var button = new MButton(title, ButtonKind.Ghost, compact: true) { HorizontalAlignment = HorizontalAlignment.Center };
        AutomationProperties.SetAutomationId(button, id);
        return button;
    }

    string InstallTitle => InstallLayout.InstalledVersion() is null ? T("установить", "Установить") : T("обновить", "Обновить");

    void ShowWelcome() => ShowWelcome(Motion.Edge.Bottom);

    void ShowWelcome(Motion.Edge edge)
    {
        var installed = InstallLayout.InstalledVersion();
        var stack = Column(56);
        stack.Children.Add(Hero("mica", T("браузер, в котором вкладки не перезагружаются, когда вы к ним возвращаетесь", "Браузер, в котором вкладки не перезагружаются, когда вы к ним возвращаетесь"), out var icon));
        var install = Primary(InstallTitle, "setup.install");
        install.Click += () => _ = Install(update: false);
        var options = Secondary(T("параметры", "Параметры"), "setup.options");
        options.Click += ShowOptions;
        stack.Children.Add(Ui.V(Space.Normal, install, options));
        var note = Ui.Text((installed is null ? "" : T("установлена версия ", "Установлена версия ") + installed + ". ") + T("установка только для вашей учётной записи, права администратора не нужны. версия ", "Установка только для вашей учётной записи, права администратора не нужны. Версия ") + version, 11.5, Palette.Text3.Brush(), wrap: true);
        note.HorizontalAlignment = HorizontalAlignment.Center; note.TextAlignment = TextAlignment.Center;
        Show(Layout(stack, note.Margin(48, 0, 48, 20)), edge);
        if (edge == Motion.Edge.Bottom) { icon.Opacity = 0; Motion.Appear(icon, Motion.Edge.None, new Spring(0.5, 0.7)); }
    }

    /// <summary>Options are a page of their own: opened inline they fell below the window edge, where nobody saw them.</summary>
    void ShowOptions()
    {
        var stack = Column(40);
        var title = Ui.Text(T("параметры", "Параметры"), 24, null, Ui.Weight(400)); title.HorizontalAlignment = HorizontalAlignment.Center;
        stack.Children.Add(title);
        var path = Ui.Text(folder, 12, Palette.Text2.Brush()); path.TextTrimming = TextTrimming.CharacterEllipsis; path.MaxWidth = 280;
        var change = new MButton(T("изменить…", "Изменить…"), compact: true);
        AutomationProperties.SetAutomationId(change, "setup.folder");
        change.Click += async () =>
        {
            var picker = new Windows.Storage.Pickers.FolderPicker();
            picker.FileTypeFilter.Add("*");
            if (app.Window is { } w) WinRT.Interop.InitializeWithWindow.Initialize(picker, WinRT.Interop.WindowNative.GetWindowHandle(w));
            if (await picker.PickSingleFolderAsync() is { } chosen) { folder = Path.Combine(chosen.Path, "mica"); path.Text = folder; }
        };
        stack.Children.Add(new SettingsGroup()
            .Add(new SettingRow(T("папка", "Папка"), Ui.H(Space.Small, path, change)))
            .Add(new ToggleRow(T("ярлык на рабочем столе", "Ярлык на рабочем столе"), desktop, v => desktop = v))
            .Add(new ToggleRow(T("сделать браузером по умолчанию", "Сделать браузером по умолчанию"), makeDefault, v => makeDefault = v, divider: false, detail: T("после установки откроются параметры Windows для подтверждения", "После установки откроются параметры Windows для подтверждения"))));
        var install = Primary(InstallTitle, "setup.install");
        install.Click += () => _ = Install(update: false);
        var back = Secondary(T("назад", "Назад"), "setup.back");
        back.Click += () => ShowWelcome(Motion.Edge.Leading);
        stack.Children.Add(Ui.V(Space.Normal, install, back));
        Show(Layout(stack), Motion.Edge.Trailing);
    }

    void ShowRuntime()
    {
        var stack = Column(56);
        stack.Children.Add(Hero(T("нужен WebView2", "Нужен WebView2"), T("mica показывает страницы движком Microsoft Edge WebView2. на этом компьютере его нет. установщик Microsoft скачает и установит его, это около 2 МБ загрузки.", "mica показывает страницы движком Microsoft Edge WebView2. На этом компьютере его нет. Установщик Microsoft скачает и установит его, это около 2 МБ загрузки."), out _));
        var get = Primary(T("установить WebView2", "Установить WebView2"), "setup.runtime");
        var status = Ui.Text("", 12, Palette.Text3.Brush(), wrap: true); status.HorizontalAlignment = HorizontalAlignment.Center;
        get.Click += async () =>
        {
            get.IsEnabled = false; status.Text = T("загружаем установщик Microsoft…", "Загружаем установщик Microsoft…");
            try
            {
                var path = Path.Combine(Path.GetTempPath(), "MicrosoftEdgeWebview2Setup.exe");
                using (var http = new HttpClient())
                await using (var file = File.Create(path)) await (await http.GetStreamAsync(Runtime.BootstrapperUrl)).CopyToAsync(file);
                status.Text = T("устанавливаем WebView2…", "Устанавливаем WebView2…");
                var process = System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(path, "/install") { UseShellExecute = true });
                if (process is not null) await process.WaitForExitAsync();
                if (Runtime.WebView2Version() is not null) ShowWelcome(); else { status.Text = T("WebView2 не установился. попробуйте ещё раз или установите его с сайта Microsoft.", "WebView2 не установился. Попробуйте ещё раз или установите его с сайта Microsoft."); get.IsEnabled = true; }
            }
            catch (Exception e) { status.Text = e.Message; get.IsEnabled = true; }
        };
        stack.Children.Add(get); stack.Children.Add(status);
        Show(Layout(stack));
    }

    async Task Install(bool update)
    {
        if (update && InstallLayout.InstalledFolder() is { } existing) folder = existing;
        var stack = Column(64);
        stack.Children.Add(Hero(update ? T("обновляем mica", "Обновляем mica") : T("устанавливаем mica", "Устанавливаем mica"), folder, out _));
        var track = new Grid { Height = 6, Width = 360, HorizontalAlignment = HorizontalAlignment.Center };
        track.Children.Add(Ui.Rounded(3, Palette.Track.Brush()));
        var fill = Ui.Rounded(3, Look.Primary);
        track.Children.Add(fill);
        var status = Ui.Text(T("готовим файлы…", "Готовим файлы…"), 12, Palette.Text3.Brush()); status.HorizontalAlignment = HorizontalAlignment.Center;
        AutomationProperties.SetLiveSetting(status, Microsoft.UI.Xaml.Automation.Peers.AutomationLiveSetting.Polite);
        stack.Children.Add(Ui.V(Space.Normal, track, status));
        Show(Layout(stack), Motion.Edge.Trailing);
        Motion.Stretch(fill, 0, Motion.Snappy);
        try
        {
            using var payload = typeof(SetupView).Assembly.GetManifestResourceStream("mica.payload.zip") ?? throw new InvalidDataException(T("в этой сборке установщика нет файлов mica", "В этой сборке установщика нет файлов mica"));
            if (update || Processes.Running(folder).Any())
            {
                status.Text = T("ждём, пока mica закроется…", "Ждём, пока mica закроется…");
                if (!await Processes.WaitForExit(folder, TimeSpan.FromSeconds(30))) throw new IOException(T("mica всё ещё открыта. закройте её и запустите установку снова.", "mica всё ещё открыта. Закройте её и запустите установку снова."));
            }
            // Extraction reports every 64 KB; the bar and the text change only when the whole percent does.
            var shown = -1;
            var progress = new Progress<(long Done, long Total, string File)>(p =>
            {
                var percent = p.Total > 0 ? (int)(p.Done * 100 / p.Total) : 0;
                if (percent == shown) return;
                shown = percent;
                Motion.Stretch(fill, percent / 100.0, Motion.Snappy);
                status.Text = T("распаковка ", "Распаковка ") + percent + "%";
            });
            var bytes = await Task.Run(() => Payload.Extract(payload, folder, progress, CancellationToken.None));
            status.Text = T("регистрируем mica в Windows…", "Регистрируем mica в Windows…");
            var exe = Path.Combine(folder, "mica.exe");
            InstallLayout.WriteUninstallEntry(folder, version, bytes);
            DefaultBrowser.Register(exe);
            Shortcuts.Create(InstallLayout.StartMenuShortcut, exe, "mica");
            if (desktop) Shortcuts.Create(InstallLayout.DesktopShortcut, exe, "mica");
            Motion.Stretch(fill, 1, Motion.Snappy);
            if (update)
            {
                System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(exe) { UseShellExecute = true, WorkingDirectory = folder });
                app.Exit();
                return;
            }
            if (Program.Has("--quiet")) { app.Exit(); return; }
            if (makeDefault) await DefaultBrowser.OpenSettingsAsync();
            ShowDone(exe);
        }
        catch (Exception e)
        {
            if (Program.Has("--quiet")) { Console.Error.WriteLine(e.Message); Environment.Exit(1); }
            ShowError(e.Message);
        }
    }

    void ShowDone(string exe)
    {
        var stack = Column(56);
        var hero = Hero(T("mica установлена", "mica установлена"), T("ярлык есть в меню «пуск». вкладки, закладки и настройки хранятся только на этом компьютере.", "Ярлык есть в меню «Пуск». Вкладки, закладки и настройки хранятся только на этом компьютере."), out var icon);
        var check = Ui.Rounded(16, Look.Primary, child: new Glyph("checkmark", 14, Look.OnPrimary) { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center });
        check.Width = 32; check.Height = 32; check.HorizontalAlignment = HorizontalAlignment.Center; check.VerticalAlignment = VerticalAlignment.Bottom; check.Margin = new Thickness(70, 0, 0, -6);
        var badge = new Grid { HorizontalAlignment = HorizontalAlignment.Center };
        hero.Children.Remove(icon); badge.Children.Add(icon); badge.Children.Add(check);
        hero.Children.Insert(0, badge);
        stack.Children.Add(hero);
        var open = Primary(T("открыть mica", "Открыть mica"), "setup.open");
        open.Click += () => { System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(exe) { UseShellExecute = true, WorkingDirectory = Path.GetDirectoryName(exe) }); app.Exit(); };
        var close = Secondary(T("закрыть", "Закрыть"), "setup.close");
        close.Click += () => app.Exit();
        stack.Children.Add(Ui.V(Space.Normal, open, close));
        Show(Layout(stack), Motion.Edge.Trailing);
        check.Opacity = 0;
        Motion.Appear(check, Motion.Edge.None, new Spring(0.45, 0.6));
    }

    void ShowError(string message)
    {
        var stack = Column(56);
        stack.Children.Add(Hero(T("не удалось установить mica", "Не удалось установить mica"), message, out _));
        var retry = Primary(T("попробовать ещё раз", "Попробовать ещё раз"), "setup.retry");
        retry.Click += () => ShowWelcome();
        stack.Children.Add(retry);
        Show(Layout(stack));
    }
}
