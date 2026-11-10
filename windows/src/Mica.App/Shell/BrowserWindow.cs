using Microsoft.UI;
using Microsoft.UI.Composition.SystemBackdrops;
using Microsoft.UI.Input;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media;
using Mica.Core;
using Mica.Design;
using WinRT;

namespace Mica.App;

/// <summary>A browser window (macOS BrowserWindow). The content extends into the title bar; the system caption
/// buttons stay (Snap Layouts, accessibility), mica's top bar fills the rest, and its controls are marked as
/// pass-through so clicks reach them while empty bar areas move the window.</summary>
public sealed partial class BrowserWindow : Window
{
    public BrowserModel Model { get; }
    public bool IsKey { get; private set; }
    /// <summary>Top bar height on Windows: the tall caption buttons are 48 px, macOS uses 44 pt with its smaller buttons.</summary>
    public const double Bar = 48;
    readonly BrowserRoot root;
    DesktopAcrylicController? acrylic;
    SystemBackdropConfiguration? backdropConfiguration;
    bool closingConfirmed, quitting;

    public BrowserWindow(BrowserModel model)
    {
        Model = model;
        model.Window = this;
        ExtendsContentIntoTitleBar = true;
        AppWindow.TitleBar.PreferredHeightOption = TitleBarHeightOption.Tall;
        AppWindow.TitleBar.ButtonBackgroundColor = Colors.Transparent;
        AppWindow.TitleBar.ButtonInactiveBackgroundColor = Colors.Transparent;
        root = new BrowserRoot(model);
        Content = root;
        PlaceInitially();
        if (AppWindow.Presenter is OverlappedPresenter presenter) { presenter.PreferredMinimumWidth = 620; presenter.PreferredMinimumHeight = 460; }
        AppWindow.SetIcon(Path.Combine(AppContext.BaseDirectory, "Assets", "mica.ico"));
        Activated += (_, e) =>
        {
            var wasKey = IsKey;
            IsKey = e.WindowActivationState != WindowActivationState.Deactivated;
            // The shared palette takes the theme and colours of the profile of the window in front.
            if (IsKey && !wasKey) model.Store.ApplyAppearance();
            if (backdropConfiguration is not null) backdropConfiguration.IsInputActive = true;
            root.SetActive(IsKey);
        };
        AppWindow.Closing += OnClosing;
        Closed += OnClosed;
        AppWindow.Changed += (_, e) => { if (e.DidPresenterChange) model.FullScreen = AppWindow.Presenter.Kind == AppWindowPresenterKind.FullScreen; };
        root.SizeChanged += (_, _) => UpdateDragRegions();
        root.LayoutUpdated += (_, _) => UpdateDragRegions();
        ApplyAppearance();
        UpdateTitle();
    }

    void PlaceInitially()
    {
        var area = DisplayArea.GetFromWindowId(AppWindow.Id, DisplayAreaFallback.Primary).WorkArea;
        var scale = Microsoft.UI.Windowing.DisplayArea.Primary is null ? 1.0 : 1.0;
        var width = (int)Math.Min(1640 * GetDpiScale(), Math.Max(980 * GetDpiScale(), area.Width * 0.9));
        var height = (int)Math.Min(1080 * GetDpiScale(), Math.Max(680 * GetDpiScale(), area.Height * 0.92));
        if (Program.QA && Program.Has("--narrow")) { width = (int)(640 * GetDpiScale()); height = (int)(620 * GetDpiScale()); }
        width = Math.Min(width, area.Width); height = Math.Min(height, area.Height);
        var offset = Store.Shared.Windows.Count * 28;
        AppWindow.MoveAndResize(new Windows.Graphics.RectInt32(area.X + (area.Width - width) / 2 + offset, area.Y + (area.Height - height) / 2 + offset, width, height));
        _ = scale;
    }

    double GetDpiScale() => Win32.DpiFor(this) / 96.0;

    public void UpdateTitle() => Title = Model.WindowTitle;

    /// <summary>First appearance (macOS BrowserWindow.showWindow): WinUI has no window alpha, so the window content fades
    /// in over the backdrop, and the content card and start page start their entrance.</summary>
    public void Enter()
    {
        if (Model.Entered) return;
        root.Enter(Model.Selected is { WebView: null, Url: null });
        Model.Entered = true;
    }

    public void Bring() { Activate(); if (AppWindow.Presenter is OverlappedPresenter p && p.State == OverlappedPresenterState.Minimized) p.Restore(); }

    /// <summary>Glass for the shell only: desktop acrylic behind mica's own tint, kept active when the window loses
    /// focus so the material does not flip to a flat fill. Off, with Windows transparency effects off, or in a
    /// contrast theme the shell is opaque. Pages are never blurred.</summary>
    public void ApplyAppearance()
    {
        var store = Model.Store;
        root.RequestedTheme = Palette.ElementTheme;
        var transparency = new Windows.UI.ViewManagement.UISettings().AdvancedEffectsEnabled;
        var prefs = Model.Prefs;
        var glass = prefs.Frosted && transparency && !Palette.Contrast && DesktopAcrylicController.IsSupported();
        if (glass && acrylic is null)
        {
            backdropConfiguration = new SystemBackdropConfiguration { IsInputActive = true, Theme = Palette.Dark ? SystemBackdropTheme.Dark : SystemBackdropTheme.Light };
            acrylic = new DesktopAcrylicController { Kind = DesktopAcrylicKind.Base, TintOpacity = 0, LuminosityOpacity = 0.05f };
            acrylic.AddSystemBackdropTarget(this.As<Microsoft.UI.Composition.ICompositionSupportsSystemBackdrop>());
            acrylic.SetSystemBackdropConfiguration(backdropConfiguration);
        }
        else if (!glass && acrylic is not null) { acrylic.Dispose(); acrylic = null; backdropConfiguration = null; }
        if (backdropConfiguration is not null) backdropConfiguration.Theme = Palette.Dark ? SystemBackdropTheme.Dark : SystemBackdropTheme.Light;
        root.SetGlass(glass, Store.GlassTint(prefs));
        var ink = Palette.Ink.Resolve();
        AppWindow.TitleBar.ButtonForegroundColor = ink;
        AppWindow.TitleBar.ButtonHoverForegroundColor = ink;
        AppWindow.TitleBar.ButtonHoverBackgroundColor = Palette.Hover.Resolve();
        AppWindow.TitleBar.ButtonPressedBackgroundColor = Palette.Pressed.Resolve();
        AppWindow.TitleBar.ButtonInactiveForegroundColor = Palette.Text3.Resolve();
    }

    public void SetFullScreen(bool on)
    {
        AppWindow.SetPresenter(on ? AppWindowPresenterKind.FullScreen : AppWindowPresenterKind.Overlapped);
        Model.FullScreen = on;
    }

    public void ToggleFullScreen() => SetFullScreen(AppWindow.Presenter.Kind != AppWindowPresenterKind.FullScreen);

    /// <summary>Controls inside the caption band take clicks; everything else there drags the window.</summary>
    void UpdateDragRegions()
    {
        if (root.XamlRoot is null) return;
        var scale = root.XamlRoot.RasterizationScale;
        var rects = new List<Windows.Graphics.RectInt32>();
        foreach (var element in root.CaptionInteractive())
        {
            if (element.Visibility != Visibility.Visible || element.ActualWidth <= 0 || !element.IsLoaded) continue;
            try
            {
                var bounds = element.TransformToVisual(root).TransformBounds(new Windows.Foundation.Rect(0, 0, element.ActualWidth, element.ActualHeight));
                if (bounds.Y > Bar) continue;
                rects.Add(new Windows.Graphics.RectInt32((int)(bounds.X * scale), (int)(bounds.Y * scale), (int)Math.Ceiling(bounds.Width * scale), (int)Math.Ceiling(bounds.Height * scale)));
            }
            catch (ArgumentException) { }
        }
        // While customizing, tiles are dragged across the bar, so the whole band passes input through.
        if (Model.CustomizingToolbar) rects = [new Windows.Graphics.RectInt32(0, 0, (int)(root.ActualWidth * scale), (int)(Bar * scale))];
        InputNonClientPointerSource.GetForWindowId(AppWindow.Id).SetRegionRects(NonClientRegionKind.Passthrough, rects.ToArray());
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
            var answer = await Dialogs.Ask(this, Model.Text("закрыть окно и отменить загрузки?", "Закрыть окно и отменить загрузки?"), Model.Text("незавершённые загрузки этого окна будут отменены", "Незавершённые загрузки этого окна будут отменены"), [Model.Text("отмена", "Отмена"), Model.Text("закрыть", "Закрыть")]);
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
