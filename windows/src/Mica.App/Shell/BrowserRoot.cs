using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;
using Mica.Core;
using Mica.Design;

namespace Mica.App;

/// <summary>Window layout (macOS BrowserRoot): top bar across the window, tabs at the top or in a sidebar on either
/// side, the page card with an optional library panel, and window-level overlays.</summary>
public sealed partial class BrowserRoot : Grid
{
    readonly BrowserModel browser;
    Store Store => browser.Store;
    readonly Grid shell = new();
    readonly TopBar topBar;
    readonly Grid tabStripHost = new();
    readonly Grid body = new();
    readonly Grid overlays = new();
    readonly ContentCard card;
    readonly Grid cardHost = new();
    readonly Grid workspace = new() { ColumnSpacing = Radius.Gutter };
    Sidebar? sidebar;
    TabStrip? strip;
    Grid? sidePanel;
    LibraryPanel? shownPanel;
    UIElement? commandBar, settings, onboarding, clearData, customize;
    string layoutKey = "";
    double? dragWidth;

    public BrowserRoot(BrowserModel browser)
    {
        this.browser = browser;
        MinWidth = 600; MinHeight = 420;
        RowDefinitions.Add(Ui.RowFixed(BrowserWindow.Bar));
        RowDefinitions.Add(Ui.RowAuto());
        RowDefinitions.Add(Ui.RowStar());
        Children.Add(shell); SetRowSpan(shell, 3);
        topBar = new TopBar(browser);
        this.Row(topBar, 0);
        this.Row(tabStripHost, 1);
        this.Row(body, 2);
        Children.Add(overlays); SetRowSpan(overlays, 3);
        card = new ContentCard(browser);
        workspace.ColumnDefinitions.Add(Ui.Star());
        workspace.ColumnDefinitions.Add(Ui.Auto());
        // The card sets its XAML Translation for shadow depth, so its entrance moves this host instead.
        workspace.Column(cardHost, 0);
        cardHost.Children.Add(card);
        browser.Changed += Render;
        browser.Message += text => _ = Dialogs.Show(browser.Window, text);
        Store.PreferencesUpdated += Render;
        Store.IssueChanged += ShowIssue;
        SizeChanged += (_, _) => Render();
        Loaded += (_, _) => { Render(); ShowIssue(); };
        KeyboardAcceleratorPlacementMode = Microsoft.UI.Xaml.Input.KeyboardAcceleratorPlacementMode.Hidden;
        Commands.Install(this, browser);
        QuitHold.Attach(overlays, browser);
    }

    void ShowIssue()
    {
        if (Store.Issue is not { } issue) return;
        Store.Issue = null;
        _ = Dialogs.Show(browser.Window, issue);
    }

    /// <summary>Elements in the caption band that take clicks: the top bar's, or with the tabs above the address the
    /// strip's tabs (the top bar is then the second row, outside the band).</summary>
    public IEnumerable<FrameworkElement> CaptionInteractive() => strip is { } s && Grid.GetRow(tabStripHost) == 0 ? topBar.Interactive().Append(s.Tabs) : topBar.Interactive();

    /// <summary>First appearance of the window: the content fades in (MotionTokens.Entrance.WindowFade) and a start page
    /// card rises a little out of the shell. A site's card is not moved or scaled; it comes with the fade.</summary>
    public void Enter(bool startPage)
    {
        Microsoft.UI.Xaml.Hosting.ElementCompositionPreview.GetElementVisual(this).Opacity = 0;
        Motion.Fade(this, 1, TimeSpan.FromSeconds(Motion.Reduced ? MotionTokens.Entrance.ReducedFade : MotionTokens.Entrance.WindowFade));
        if (startPage) Motion.Enter(cardHost, MotionTokens.Entrance.Stagger, scale: MotionTokens.Entrance.CardScale);
    }

    public void SetActive(bool active) => topBar.Opacity = active ? 1 : 0.86;

    public void SetGlass(bool glass, double tint)
    {
        shell.Background = Look.Shell;
        shell.Opacity = glass ? tint : 1;
        Background = glass ? Palette.Clear : Look.Shell;
        card.SetGlass(glass, Store.StartTint);
    }

    TabLayout EffectiveLayout => ActualWidth > 0 ? Store.Preferences.Layout.Fitting(ActualWidth) : Store.Preferences.Layout;

    void Render()
    {
        var layout = EffectiveLayout;
        var edge = layout.SidebarEdge();
        var collapsed = Store.Preferences.SidebarCollapsed && edge is not null;
        var key = $"{layout}|{collapsed}|{browser.CustomizingToolbar}";
        if (key != layoutKey)
        {
            var animate = layoutKey.Length > 0;
            layoutKey = key;
            BuildBody(layout, edge, collapsed, animate);
        }
        topBar.Render(layout, ActualWidth);
        // Clear of the caption buttons on the right; they are hidden in full screen.
        if (strip is not null && layout == TabLayout.TabsAbove) strip.Margin = new Thickness(Radius.Gutter, 0, (browser.FullScreen ? 0 : Chrome.CaptionInset) + Space.Small, 0);
        if (sidebar is not null && !collapsed && dragWidth is null) sidebar.Width = Store.Preferences.SidebarWidth;
        UpdatePanel();
        UpdateOverlays();
        card.SetCovered(browser.Modal || browser.CommandBar || browser.CustomizingToolbar);
    }

    void BuildBody(TabLayout layout, TabLayout? edge, bool collapsed, bool animate)
    {
        body.Children.Clear(); body.ColumnDefinitions.Clear();
        tabStripHost.Children.Clear();
        sidebar = null; strip = null;
        // Tabs above the address: the strip takes the caption band (row 0) and the top bar moves to the second row.
        var above = layout == TabLayout.TabsAbove;
        Grid.SetRow(tabStripHost, above ? 0 : 1);
        Grid.SetRow(topBar, above ? 1 : 0);
        topBar.Margin = above ? new Thickness(0, -Space.Micro, 0, 0) : new Thickness(0);
        if (layout.IsHorizontal())
        {
            strip = above
                ? new TabStrip(browser, titleBand: true) { VerticalAlignment = VerticalAlignment.Center }
                : new TabStrip(browser) { Margin = new Thickness(Radius.Gutter, 0, Radius.Gutter, Space.Small) };
            tabStripHost.Children.Add(strip);
            if (animate) Motion.Appear(strip, above ? Motion.Edge.None : Motion.Edge.Top, Motion.Panel);
        }
        body.ColumnDefinitions.Add(Ui.Auto()); body.ColumnDefinitions.Add(Ui.Star()); body.ColumnDefinitions.Add(Ui.Auto());
        if (workspace.Parent is Panel old) old.Children.Remove(workspace);
        workspace.Margin = new Thickness(edge == TabLayout.Left ? 0 : Radius.Gutter, 0, edge == TabLayout.Right ? 0 : Radius.Gutter, Radius.Gutter);
        body.Column(workspace, 1);
        if (edge is { } side)
        {
            sidebar = new Sidebar(browser, collapsed, side) { Width = collapsed ? Chrome.Rail : dragWidth ?? Store.Preferences.SidebarWidth };
            var host = new Grid();
            host.Children.Add(sidebar);
            if (!collapsed) host.Children.Add(ResizeHandle(side == TabLayout.Left ? 1 : -1, side));
            body.Column(host, side == TabLayout.Left ? 0 : 2);
            if (animate) Motion.Appear(host, side == TabLayout.Left ? Motion.Edge.Leading : Motion.Edge.Trailing, Motion.Panel);
        }
    }

    /// <summary>Six-pixel strip on the sidebar edge; dragging resizes within the supported range.</summary>
    FrameworkElement ResizeHandle(int sign, TabLayout side)
    {
        var handle = new ResizeGrip { Width = 6, Background = Palette.Clear, HorizontalAlignment = side == TabLayout.Left ? HorizontalAlignment.Right : HorizontalAlignment.Left };
        handle.Tip(Store.Text("ширина боковой панели", "Ширина боковой панели"));
        double start = 0, origin = 0;
        handle.PointerPressed += (_, e) => { handle.CapturePointer(e.Pointer); start = e.GetCurrentPoint(this).Position.X; origin = Store.Preferences.SidebarWidth; dragWidth = origin; e.Handled = true; };
        handle.PointerMoved += (_, e) =>
        {
            if (dragWidth is null) return;
            dragWidth = Math.Clamp(origin + (e.GetCurrentPoint(this).Position.X - start) * sign, Preferences.SidebarMin, Preferences.SidebarMax);
            if (sidebar is not null) sidebar.Width = dragWidth.Value;
        };
        void End() { if (dragWidth is { } w) { dragWidth = null; Store.Change(p => p.SidebarWidth = w); } }
        handle.PointerReleased += (_, e) => { handle.ReleasePointerCapture(e.Pointer); End(); };
        handle.PointerCaptureLost += (_, _) => End();
        return handle;
    }


    void UpdatePanel()
    {
        if (browser.Panel == shownPanel) return;
        shownPanel = browser.Panel;
        if (sidePanel is { } old) { sidePanel = null; Motion.Disappear(old, () => workspace.Children.Remove(old), Motion.Edge.Trailing); }
        if (browser.Panel is { } panel)
        {
            var content = new Library.SidePanel(panel, browser);
            var frame = Ui.Rounded(Radius.Card, Palette.Surface.Brush(), Palette.Hairline.Brush(), 1, content);
            var host = new Grid { Width = Math.Min(340, ActualWidth * 0.4) };
            host.Children.Add(frame);
            frame.Shadow = Shadows.Soft; frame.Translation = new System.Numerics.Vector3(0, 0, 6);
            sidePanel = host;
            workspace.Column(host, 1);
            Motion.Appear(host, Motion.Edge.Trailing, Motion.Panel);
        }
    }

    void UpdateOverlays()
    {
        Toggle(ref commandBar, browser.CommandBar, () => new CommandBar(browser), overlays);
        Toggle(ref settings, browser.ShowSettings, () => new Settings.SettingsOverlay(browser), overlays);
        Toggle(ref onboarding, browser.ShowOnboarding, () => new ModalCard(new Onboarding.OnboardingView(browser), 860, 660, dismissible: false), overlays);
        Toggle(ref clearData, browser.ShowClearData, () => new ModalCard(new Library.ClearDataPanel(browser), 480, dismiss: () => browser.ShowClearData = false), overlays);
        Toggle(ref customize, browser.CustomizingToolbar, () => new CustomizeLayer(browser), workspace, column: 0);
    }

    static void Toggle(ref UIElement? slot, bool shown, Func<UIElement> make, Panel host, int column = -1)
    {
        if (shown && slot is null)
        {
            slot = make();
            if (column >= 0 && slot is FrameworkElement fe) Grid.SetColumn(fe, column);
            host.Children.Add(slot);
            if (slot is not ModalCard) Motion.Appear(slot);
        }
        else if (!shown && slot is { } old)
        {
            slot = null;
            Motion.Disappear(old, () => host.Children.Remove(old));
        }
    }

    /// <summary>The toolbar editor sits over the page area with a dim layer under it (macOS customize overlay).</summary>
    sealed partial class CustomizeLayer : Grid
    {
        public CustomizeLayer(BrowserModel browser)
        {
            var dim = Ui.Rounded(Radius.Card, new SolidColorBrush(Palette.WithAlpha(Microsoft.UI.Colors.Black, 0.18)));
            dim.Tapped += (_, e) => e.Handled = true;
            Children.Add(dim);
            var panel = new CustomizeToolbarPanel(browser) { Margin = new Thickness(Space.Normal, Space.Normal, Space.Normal, 0), VerticalAlignment = VerticalAlignment.Top };
            Children.Add(panel);
        }
    }
}

/// <summary>Sidebar edge with the horizontal resize cursor; ProtectedCursor is settable only from a subclass.</summary>
public sealed partial class ResizeGrip : Grid
{
    public ResizeGrip() { ProtectedCursor = Microsoft.UI.Input.InputSystemCursor.Create(Microsoft.UI.Input.InputSystemCursorShape.SizeWestEast); }
}
