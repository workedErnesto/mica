using System.Numerics;
using System.Text.Json;
using Microsoft.UI;
using Microsoft.UI.Composition.SystemBackdrops;
using Microsoft.UI.Input;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Hosting;
using Mica.Core;
using Mica.Design;
using WinRT;

namespace Mica.App;

/// <summary>A browser window (macOS BrowserWindow). Two layers over the backdrop: the shell (ShellView), which draws all
/// of mica's interface, and above it the WebView2 of the selected tab, placed into the hole the shell leaves in its
/// content card and clipped to the card's corners. While the shell draws over the page (menus, the command bar,
/// window cards) it moves above the page layer. The content extends into the title bar; the system caption buttons
/// stay (Snap Layouts, accessibility), empty bar areas move the window, and the shell's controls there take clicks.</summary>
public sealed partial class BrowserWindow : Window
{
    public BrowserModel Model { get; }
    public bool IsKey { get; private set; }
    /// <summary>Height of the first row on Windows: the tall caption buttons are 48 px, macOS uses 44 pt for its bar.</summary>
    public const double Bar = 48;
    readonly Grid root = new();
    readonly Grid pages = new() { HorizontalAlignment = HorizontalAlignment.Stretch, VerticalAlignment = VerticalAlignment.Stretch };
    readonly ShellView shell;
    DesktopAcrylicController? acrylic;
    SystemBackdropConfiguration? backdropConfiguration;
    bool closingConfirmed, quitting, covered, keepPage;
    Windows.Foundation.Rect? pageRect;
    /// <summary>Where the page sits in the window, in DIPs, as the shell last reported it.</summary>
    public Windows.Foundation.Rect? PageRect => pageRect;
    double pageRadius = Radius.Card;
    Tab? shownTab;

    public BrowserWindow(BrowserModel model)
    {
        Model = model;
        model.Window = this;
        ExtendsContentIntoTitleBar = true;
        AppWindow.TitleBar.PreferredHeightOption = TitleBarHeightOption.Tall;
        AppWindow.TitleBar.ButtonBackgroundColor = Colors.Transparent;
        AppWindow.TitleBar.ButtonInactiveBackgroundColor = Colors.Transparent;
        root.Background = new Microsoft.UI.Xaml.Media.SolidColorBrush(Colors.Transparent);
        shell = new ShellView(model, this);
        root.Children.Add(shell);
        root.Children.Add(pages);
        pages.IsHitTestVisible = true;
        Content = root;
        Commands.Install(root, model);
        PlaceInitially();
        if (AppWindow.Presenter is OverlappedPresenter presenter) { presenter.PreferredMinimumWidth = 620; presenter.PreferredMinimumHeight = 460; }
        AppWindow.SetIcon(Appearance.AppIcons.Ico(model.Store.Preferences.AppIcon) ?? Path.Combine(AppContext.BaseDirectory, "Assets", "mica.ico"));
        Activated += (_, e) =>
        {
            IsKey = e.WindowActivationState != WindowActivationState.Deactivated;
            if (backdropConfiguration is not null) backdropConfiguration.IsInputActive = true;
            if (!IsKey) shell.Event("closeMenus");
            Model.Touch();
        };
        AppWindow.Closing += OnClosing;
        Closed += OnClosed;
        AppWindow.Changed += (_, e) => { if (e.DidPresenterChange) { model.FullScreen = AppWindow.Presenter.Kind == AppWindowPresenterKind.FullScreen; } };
        shell.LayoutReported += OnLayout;
        shell.Ready += () => FocusContent();
        model.WebViewCreated += tab => { if (tab.WebView is { } view && view.Parent is null) { Prepare(view); pages.Children.Add(view); } Arrange(); };
        model.Changed += Arrange;
        model.Message += text => _ = Dialogs.Show(this, text);
        root.SizeChanged += (_, _) => { ClipPage(); };
        UpdateTitle();
    }

    /// <summary>Right edge the shell leaves to the caption buttons, in DIPs.</summary>
    public double CaptionInset
    {
        get
        {
            if (Model.FullScreen) return 0;
            var scale = root.XamlRoot?.RasterizationScale ?? 1;
            var inset = AppWindow.TitleBar.RightInset / scale;
            return inset > 0 ? Math.Ceiling(inset) : Chrome.CaptionInset;
        }
    }

    void PlaceInitially()
    {
        var area = DisplayArea.GetFromWindowId(AppWindow.Id, DisplayAreaFallback.Primary).WorkArea;
        var scale = Win32.DpiFor(this) / 96.0;
        var width = (int)Math.Min(1640 * scale, Math.Max(980 * scale, area.Width * 0.9));
        var height = (int)Math.Min(1080 * scale, Math.Max(680 * scale, area.Height * 0.92));
        if (Program.QA && Program.Has("--narrow")) { width = (int)(640 * scale); height = (int)(620 * scale); }
        width = Math.Min(width, area.Width); height = Math.Min(height, area.Height);
        var offset = Store.Shared.Windows.Count * 28;
        AppWindow.MoveAndResize(new Windows.Graphics.RectInt32(area.X + (area.Width - width) / 2 + offset, area.Y + (area.Height - height) / 2 + offset, width, height));
    }

    public void UpdateTitle() => Title = Model.WindowTitle;

    /// <summary>First appearance: the shell plays the start page entrance itself once it has the state.</summary>
    public void Enter() => Model.Entered = true;

    public void Bring() { Activate(); if (AppWindow.Presenter is OverlappedPresenter p && p.State == OverlappedPresenterState.Minimized) p.Restore(); }

    /// <summary>The shell could not start (no WebView2 Runtime): a plain message instead of an empty window.</summary>
    public void ShellFailed(string reason)
    {
        root.Children.Add(new TextBlock
        {
            Text = Model.Text("не удалось запустить WebView2. установите WebView2 Runtime от Microsoft и перезапустите mica: ", "Не удалось запустить WebView2. Установите WebView2 Runtime от Microsoft и перезапустите mica: ") + reason,
            TextWrapping = TextWrapping.Wrap, Margin = new Thickness(40), VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Center, MaxWidth = 520,
        });
    }

    /// <summary>Glass for the shell only: desktop acrylic behind the shell's own tint, kept active when the window loses
    /// focus so the material does not flip to a flat fill. Pages are never blurred. Also colours the caption buttons
    /// for the window's own theme.</summary>
    public void ApplyLook(ShellState.Look look)
    {
        root.RequestedTheme = look.Dark ? ElementTheme.Dark : ElementTheme.Light;
        if (look.Glass && acrylic is null)
        {
            backdropConfiguration = new SystemBackdropConfiguration { IsInputActive = true };
            acrylic = new DesktopAcrylicController { Kind = DesktopAcrylicKind.Base, TintOpacity = 0, LuminosityOpacity = 0.05f };
            acrylic.AddSystemBackdropTarget(this.As<Microsoft.UI.Composition.ICompositionSupportsSystemBackdrop>());
            acrylic.SetSystemBackdropConfiguration(backdropConfiguration);
        }
        else if (!look.Glass && acrylic is not null) { acrylic.Dispose(); acrylic = null; backdropConfiguration = null; }
        if (backdropConfiguration is not null) backdropConfiguration.Theme = look.Dark ? SystemBackdropTheme.Dark : SystemBackdropTheme.Light;
        // Without glass the window behind the transparent shell must still be opaque.
        root.Background = new Microsoft.UI.Xaml.Media.SolidColorBrush(look.Glass ? Colors.Transparent : Resolve(Palette.Shell, look));
        var ink = Resolve(Palette.Ink, look);
        var bar = AppWindow.TitleBar;
        bar.ButtonForegroundColor = ink;
        bar.ButtonHoverForegroundColor = ink;
        bar.ButtonPressedForegroundColor = ink;
        bar.ButtonHoverBackgroundColor = Resolve(Palette.Hover, look);
        bar.ButtonPressedBackgroundColor = Resolve(Palette.Pressed, look);
        bar.ButtonInactiveForegroundColor = Resolve(Palette.Text3, look);
        foreach (var tab in Model.Tabs) if (tab.WebView is { } view) view.DefaultBackgroundColor = look.Dark ? Windows.UI.Color.FromArgb(255, 0x18, 0x16, 0x15) : Colors.White;
    }

    static Windows.UI.Color Resolve(Swatch s, ShellState.Look look) => Palette.ColorOf(look.Dark ? (look.Contrast ? s.ContrastDark : s.Dark) : (look.Contrast ? s.ContrastLight : s.Light));

    public void SetFullScreen(bool on)
    {
        AppWindow.SetPresenter(on ? AppWindowPresenterKind.FullScreen : AppWindowPresenterKind.Overlapped);
        Model.FullScreen = on;
    }

    public void ToggleFullScreen() => SetFullScreen(AppWindow.Presenter.Kind != AppWindowPresenterKind.FullScreen);

    // Page layer

    static void Prepare(WebView2 view)
    {
        view.HorizontalAlignment = HorizontalAlignment.Left;
        view.VerticalAlignment = VerticalAlignment.Top;
    }

    /// <summary>Shows the selected tab's page in the card's hole and hides the others. Hidden pages stay alive; WebView2
    /// is told they are hidden, so Chromium throttles them as WebKit does on macOS.</summary>
    void Arrange()
    {
        var tab = Model.Selected;
        var showing = tab is { WebView: not null, Error: null } && pageRect is not null && tab.Url is not null;
        foreach (var other in Model.Tabs) other.SetVisible(showing && other == tab);
        if (showing && pageRect is { } rect && tab!.WebView is { } view)
        {
            view.Margin = new Thickness(rect.X, rect.Y, 0, 0);
            view.Width = Math.Max(1, rect.Width); view.Height = Math.Max(1, rect.Height);
            if (shownTab != tab) { shownTab = tab; ClipPage(); FocusContent(); }
        }
        else shownTab = null;
    }

    /// <summary>Rounds the page to the card's corners; the card's hairline and shadow are drawn by the shell around it.</summary>
    void ClipPage()
    {
        if (shownTab?.WebView is not { } view || pageRect is not { } rect) return;
        var visual = ElementCompositionPreview.GetElementVisual(view);
        var compositor = visual.Compositor;
        var geometry = compositor.CreateRoundedRectangleGeometry();
        geometry.Size = new Vector2((float)rect.Width, (float)rect.Height);
        geometry.CornerRadius = new Vector2((float)pageRadius, (float)pageRadius);
        visual.Clip = compositor.CreateGeometricClip(geometry);
    }

    /// <summary>The shell reports where the page goes and which parts of the bar move the window, after every render
    /// and on each frame of an animated layout change.</summary>
    void OnLayout(JsonElement layout)
    {
        Windows.Foundation.Rect? rect = null;
        if (layout.TryGetProperty("page", out var page) && page.ValueKind == JsonValueKind.Array && page.GetArrayLength() == 4)
            rect = new Windows.Foundation.Rect(page[0].GetDouble(), page[1].GetDouble(), Math.Max(0, page[2].GetDouble()), Math.Max(0, page[3].GetDouble()));
        if (layout.TryGetProperty("radius", out var radius) && radius.ValueKind == JsonValueKind.Number) pageRadius = radius.GetDouble();
        var sizeChanged = rect is { } r && (pageRect is not { } old || old.Width != r.Width || old.Height != r.Height);
        pageRect = rect;
        Arrange();
        if (sizeChanged) ClipPage();
        var cover = layout.TryGetProperty("covered", out var c) && c.ValueKind == JsonValueKind.True;
        // Only the password offer is over the page: the shell goes above it, but the page keeps the keyboard so typing
        // in the field goes on.
        var keep = cover && layout.TryGetProperty("keepPage", out var k) && k.ValueKind == JsonValueKind.True;
        if (cover != covered || keep != keepPage)
        {
            var wasKept = keepPage;
            covered = cover; keepPage = keep;
            // While the shell draws over the page it goes above the page layer; the page shows through its hole.
            Canvas.SetZIndex(shell, covered ? 1 : 0);
            Canvas.SetZIndex(pages, covered ? 0 : 1);
            pages.IsHitTestVisible = !covered;
            if (covered && !keepPage) shell.FocusShell();
            else if (!covered && !wasKept) FocusContent();
            else if (!covered) FocusContent(onlyFromShell: true);
        }
        Regions(layout);
    }

    /// <summary>Empty bar areas drag the window; the shell's controls there take clicks.</summary>
    void Regions(JsonElement layout)
    {
        if (root.XamlRoot is null) return;
        var scale = root.XamlRoot.RasterizationScale;
        Windows.Graphics.RectInt32[] Read(string key)
        {
            if (!layout.TryGetProperty(key, out var list) || list.ValueKind != JsonValueKind.Array) return [];
            return list.EnumerateArray().Where(r => r.GetArrayLength() == 4).Select(r => new Windows.Graphics.RectInt32(
                (int)Math.Floor(r[0].GetDouble() * scale), (int)Math.Floor(r[1].GetDouble() * scale),
                (int)Math.Ceiling(r[2].GetDouble() * scale), (int)Math.Ceiling(r[3].GetDouble() * scale))).ToArray();
        }
        var source = InputNonClientPointerSource.GetForWindowId(AppWindow.Id);
        source.SetRegionRects(NonClientRegionKind.Caption, Read("caption"));
        source.SetRegionRects(NonClientRegionKind.Passthrough, Read("passthrough"));
    }

    /// <summary>A page that appears or comes back from under an overlay takes the keyboard, as in Safari, so edit
    /// shortcuts and keyboard scrolling reach it without a click; otherwise the shell has it.</summary>
    void FocusContent(bool onlyFromShell = false)
    {
        // After the password offer the page normally still has the keyboard; it moved to the shell only when the offer
        // itself was clicked.
        if (onlyFromShell && !shell.HasFocus) return;
        if (!covered && shownTab?.WebView is { Visibility: Visibility.Visible } view) view.Focus(FocusState.Programmatic);
        else shell.FocusShell();
    }

    async void OnClosing(AppWindow sender, AppWindowClosingEventArgs e)
    {
        if (closingConfirmed || quitting) return;
        var running = Model.Downloads.Items.Any(d => d.State is DownloadState.Running or DownloadState.Choosing or DownloadState.Paused);
        var last = Model.Store.Windows.Count == 1;
        if (!running && !last) return;
        e.Cancel = true;
        if (running)
        {
            var answer = await Dialogs.Ask(this, Model.Text("закрыть окно и отменить загрузки?", "Закрыть окно и отменить загрузки?"), Model.Text("незавершённые загрузки этого окна будут отменены", "Незавершённые загрузки этого окна будут отменены"), [Model.Text("отмена", "Отмена"), Model.Text("закрыть", "Закрыть")], destructive: true);
            if (answer != 1) return;
            Model.Downloads.CancelAll();
        }
        // Closing the last window ends mica on Windows; the session keeps it, so the next launch restores it.
        if (last) { Model.Store.Quit(); return; }
        closingConfirmed = true;
        Close();
    }

    public void CloseForQuit() { quitting = true; Close(); }

    void OnClosed(object sender, WindowEventArgs e)
    {
        var store = Model.Store;
        Dialogs.CancelAll(Model);
        shell.Detach();
        acrylic?.Dispose();
        Model.Dispose();
        store.Windows.Remove(this);
        if (!store.ShuttingDown) store.ScheduleSession();
    }
}

/// <summary>Win32 calls the Windows App SDK does not wrap.</summary>
public static partial class Win32
{
    [System.Runtime.InteropServices.LibraryImport("user32.dll")] private static partial uint GetDpiForWindow(nint hwnd);
    public static uint DpiFor(Window window) { var dpi = GetDpiForWindow(WinRT.Interop.WindowNative.GetWindowHandle(window)); return dpi == 0 ? 96 : dpi; }
    public static nint Handle(Window window) => WinRT.Interop.WindowNative.GetWindowHandle(window);
}
