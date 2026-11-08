using System.Numerics;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
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

    [STAThread]
    static int Main(string[] args)
    {
        Arguments = args;
        using var single = new Mutex(true, "mica-setup", out var first);
        if (!first) return 0;
        WinRT.ComWrappersSupport.InitializeComWrappers();
        Application.Start(callback =>
        {
            SynchronizationContext.SetSynchronizationContext(new DispatcherQueueSynchronizationContext(DispatcherQueue.GetForCurrentThread()));
            _ = new SetupApplication();
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
    readonly XamlControlsXamlMetaDataProvider provider = new();
    public IXamlType GetXamlType(Type type) => provider.GetXamlType(type);
    public IXamlType GetXamlType(string fullName) => provider.GetXamlType(fullName);
    public XmlnsDefinition[] GetXmlnsDefinitions() => provider.GetXmlnsDefinitions();
    public Window? Window { get; private set; }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        Resources.MergedDictionaries.Add(new XamlControlsResources());
        var settings = new Windows.UI.ViewManagement.UISettings();
        Palette.Apply(settings.GetColorValue(Windows.UI.ViewManagement.UIColorType.Background).R < 128, new Windows.UI.ViewManagement.AccessibilitySettings().HighContrast);
        Look.Apply(false, "#6E56CF", 0);
        Window = new Window { ExtendsContentIntoTitleBar = true, Title = "mica" };
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
        Window.Content = view;
        Window.Activate();
        if (Program.Has("--self-test")) { var t = DispatcherQueue.GetForCurrentThread().CreateTimer(); t.Interval = TimeSpan.FromSeconds(3); t.Tick += (_, _) => Exit(); t.Start(); }
    }
}

static partial class Win32Dpi
{
    [System.Runtime.InteropServices.LibraryImport("user32.dll")] private static partial uint GetDpiForWindow(nint hwnd);
    public static double Scale(Window window) { var dpi = GetDpiForWindow(WinRT.Interop.WindowNative.GetWindowHandle(window)); return dpi == 0 ? 1 : dpi / 96.0; }
}

public sealed partial class SetupView : Grid
{
    readonly SetupApplication app;
    readonly Grid page = new();
    readonly Image icon;
    readonly Language language = LanguageInfo.Preferred();
    string folder = InstallLayout.InstalledFolder() ?? InstallLayout.DefaultFolder;
    bool desktop, launch = true, makeDefault;
    readonly string version = typeof(SetupView).Assembly.GetName().Version is { } v ? $"{v.Major}.{v.Minor}.{v.Build}" : "?";
    string T(string low, string regular) => Copy.Text(low, regular, true, language);

    public SetupView(SetupApplication app, bool transparent)
    {
        this.app = app;
        RequestedTheme = Palette.ElementTheme;
        Background = transparent ? new SolidColorBrush(Palette.WithAlpha(Palette.Shell.Resolve(), 0.55)) : Palette.Shell.Brush();
        icon = new Image { Width = 88, Height = 88, Source = LoadIcon() };
        Children.Add(page);
        Loaded += (_, _) =>
        {
            if (Program.Has("--update")) _ = Install(update: true);
            else if (Program.Has("--quiet")) { launch = false; _ = Install(update: false); }
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

    StackPanel Hero(string title, string subtitle)
    {
        if (icon.Parent is Panel old) old.Children.Remove(icon);
        var name = Ui.Text(title, 34, null, Ui.Weight(300)); name.CharacterSpacing = -30; name.HorizontalAlignment = HorizontalAlignment.Center; name.TextAlignment = TextAlignment.Center;
        var sub = Ui.Text(subtitle, 13.5, Palette.Text2.Brush(), wrap: true); sub.HorizontalAlignment = HorizontalAlignment.Center; sub.TextAlignment = TextAlignment.Center; sub.MaxWidth = 420;
        var hero = Ui.V(Space.Normal, icon, name, sub);
        icon.HorizontalAlignment = HorizontalAlignment.Center;
        return hero;
    }

    void ShowWelcome()
    {
        var installed = InstallLayout.InstalledVersion();
        var stack = new StackPanel { Spacing = Space.Section, Padding = new Thickness(48, 56, 48, 24), HorizontalAlignment = HorizontalAlignment.Stretch };
        stack.Children.Add(Hero("mica", T("браузер, в котором вкладки не перезагружаются, когда вы к ним возвращаетесь", "Браузер, в котором вкладки не перезагружаются, когда вы к ним возвращаетесь")));
        var install = new MButton(installed is null ? T("установить", "Установить") : T("обновить", "Обновить"), ButtonKind.Primary) { Width = 220, HorizontalAlignment = HorizontalAlignment.Center };
        install.Click += () => _ = Install(update: false);
        stack.Children.Add(install);
        var options = BuildOptions();
        options.Visibility = Visibility.Collapsed;
        var toggle = new MButton(T("параметры", "Параметры"), ButtonKind.Ghost, compact: true) { HorizontalAlignment = HorizontalAlignment.Center };
        toggle.Click += () => { options.Visibility = options.Visibility == Visibility.Visible ? Visibility.Collapsed : Visibility.Visible; if (options.Visibility == Visibility.Visible) Motion.Appear(options, Motion.Edge.Top); };
        stack.Children.Add(toggle);
        stack.Children.Add(options);
        var note = Ui.Text((installed is null ? "" : T("установлена версия ", "Установлена версия ") + installed + ". ") + T("установка только для вашей учётной записи, права администратора не нужны. версия ", "Установка только для вашей учётной записи, права администратора не нужны. Версия ") + version, 11.5, Palette.Text3.Brush(), wrap: true);
        note.HorizontalAlignment = HorizontalAlignment.Center; note.TextAlignment = TextAlignment.Center;
        var root = new Grid(); root.RowDefinitions.Add(Ui.RowStar()); root.RowDefinitions.Add(Ui.RowAuto());
        var scroll = Ui.Scroll(stack); scroll.VerticalScrollBarVisibility = ScrollBarVisibility.Hidden;
        root.Row(scroll, 0); root.Row(note.Margin(48, 0, 48, 20), 1);
        Show(root);
        icon.Opacity = 0;
        Motion.Appear(icon, Motion.Edge.None, new Spring(0.5, 0.7));
    }

    SettingsGroup BuildOptions()
    {
        var path = Ui.Text(folder, 12, Palette.Text2.Brush()); path.TextTrimming = TextTrimming.CharacterEllipsis; path.MaxWidth = 300;
        var change = new MButton(T("изменить…", "Изменить…"), compact: true);
        change.Click += async () =>
        {
            var picker = new Windows.Storage.Pickers.FolderPicker();
            picker.FileTypeFilter.Add("*");
            if (app.Window is { } w) WinRT.Interop.InitializeWithWindow.Initialize(picker, WinRT.Interop.WindowNative.GetWindowHandle(w));
            if (await picker.PickSingleFolderAsync() is { } chosen) { folder = Path.Combine(chosen.Path, "mica"); path.Text = folder; }
        };
        return new SettingsGroup()
            .Add(new SettingRow(T("папка", "Папка"), Ui.H(Space.Small, path, change)))
            .Add(new ToggleRow(T("ярлык на рабочем столе", "Ярлык на рабочем столе"), desktop, v => desktop = v))
            .Add(new ToggleRow(T("сделать браузером по умолчанию", "Сделать браузером по умолчанию"), makeDefault, v => makeDefault = v, detail: T("после установки откроются параметры windows для подтверждения", "После установки откроются параметры Windows для подтверждения")))
            .Add(new ToggleRow(T("открыть mica после установки", "Открыть mica после установки"), launch, v => launch = v, divider: false));
    }

    void ShowRuntime()
    {
        var stack = new StackPanel { Spacing = Space.Section, Padding = new Thickness(48, 56, 48, 24) };
        stack.Children.Add(Hero(T("нужен WebView2", "Нужен WebView2"), T("mica показывает страницы движком Microsoft Edge WebView2. на этом компьютере его нет. установщик Microsoft скачает и установит его, это около 2 МБ загрузки.", "mica показывает страницы движком Microsoft Edge WebView2. На этом компьютере его нет. Установщик Microsoft скачает и установит его, это около 2 МБ загрузки.")));
        var get = new MButton(T("установить WebView2", "Установить WebView2"), ButtonKind.Primary) { Width = 220, HorizontalAlignment = HorizontalAlignment.Center };
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
        Show(stack);
    }

    async Task Install(bool update)
    {
        if (update && InstallLayout.InstalledFolder() is { } existing) folder = existing;
        var stack = new StackPanel { Spacing = Space.Section, Padding = new Thickness(48, 64, 48, 24) };
        stack.Children.Add(Hero(update ? T("обновляем mica", "Обновляем mica") : T("устанавливаем mica", "Устанавливаем mica"), folder));
        var track = new Grid { Height = 6, Width = 360, HorizontalAlignment = HorizontalAlignment.Center };
        track.Children.Add(Ui.Rounded(3, Palette.Track.Brush()));
        var fill = Ui.Rounded(3, Look.Primary);
        track.Children.Add(fill);
        var status = Ui.Text(T("готовим файлы…", "Готовим файлы…"), 12, Palette.Text3.Brush()); status.HorizontalAlignment = HorizontalAlignment.Center;
        stack.Children.Add(Ui.V(Space.Normal, track, status));
        Show(stack, Motion.Edge.Trailing);
        Motion.Stretch(fill, 0, Motion.Snappy);
        try
        {
            using var payload = typeof(SetupView).Assembly.GetManifestResourceStream("mica.payload.zip") ?? throw new InvalidDataException(T("в этой сборке установщика нет файлов mica", "В этой сборке установщика нет файлов mica"));
            if (update || Processes.Running(folder).Any())
            {
                status.Text = T("ждём, пока mica закроется…", "Ждём, пока mica закроется…");
                if (!await Processes.WaitForExit(folder, TimeSpan.FromSeconds(30))) throw new IOException(T("mica всё ещё открыта. закройте её и запустите установку снова.", "mica всё ещё открыта. Закройте её и запустите установку снова."));
            }
            var progress = new Progress<(long Done, long Total, string File)>(p =>
            {
                var fraction = p.Total > 0 ? (double)p.Done / p.Total : 0;
                Motion.Stretch(fill, fraction, Motion.Snappy);
                status.Text = T("распаковка ", "Распаковка ") + Math.Round(fraction * 100) + "%";
            });
            var bytes = await Task.Run(() => Payload.Extract(payload, folder, progress, CancellationToken.None));
            status.Text = T("регистрируем mica в windows…", "Регистрируем mica в Windows…");
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
        if (Program.Has("--quiet")) { app.Exit(); return; }
        var stack = new StackPanel { Spacing = Space.Section, Padding = new Thickness(48, 56, 48, 24) };
        stack.Children.Add(Hero(T("mica установлена", "mica установлена"), T("ярлык есть в меню «пуск». вкладки, закладки и настройки хранятся только на этом компьютере.", "Ярлык есть в меню «Пуск». Вкладки, закладки и настройки хранятся только на этом компьютере.")));
        var check = Ui.Rounded(16, Look.Primary, child: new Glyph("checkmark", 14, Look.OnPrimary) { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center });
        check.Width = 32; check.Height = 32; check.HorizontalAlignment = HorizontalAlignment.Center; check.Margin = new Thickness(0, -60, -70, 0);
        stack.Children.Insert(1, check);
        var open = new MButton(T("открыть mica", "Открыть mica"), ButtonKind.Primary) { Width = 220, HorizontalAlignment = HorizontalAlignment.Center };
        open.Click += () => { System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(exe) { UseShellExecute = true, WorkingDirectory = Path.GetDirectoryName(exe) }); app.Exit(); };
        var close = new MButton(T("закрыть", "Закрыть"), ButtonKind.Ghost, compact: true) { HorizontalAlignment = HorizontalAlignment.Center };
        close.Click += () => app.Exit();
        stack.Children.Add(open); stack.Children.Add(close);
        Show(stack, Motion.Edge.Trailing);
        check.Opacity = 0;
        Motion.Appear(check, Motion.Edge.None, new Spring(0.45, 0.6));
        if (launch && !Program.Has("--self-test")) { /* the user still sees the result; "open mica" starts it */ }
    }

    void ShowError(string message)
    {
        var stack = new StackPanel { Spacing = Space.Section, Padding = new Thickness(48, 56, 48, 24) };
        stack.Children.Add(Hero(T("не удалось установить mica", "Не удалось установить mica"), message));
        var retry = new MButton(T("попробовать ещё раз", "Попробовать ещё раз"), ButtonKind.Primary) { Width = 220, HorizontalAlignment = HorizontalAlignment.Center };
        retry.Click += ShowWelcome;
        stack.Children.Add(retry);
        Show(stack);
    }
}
