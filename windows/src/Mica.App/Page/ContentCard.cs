using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Mica.Core;
using Mica.Design;
using Microsoft.Web.WebView2.Core;

namespace Mica.App;

/// <summary>The page card (macOS ContentCard): every live WebView2 of the window sits here, only the selected one
/// visible; the start page, the error page and the find bar layer above it. The card is opaque; only the shell
/// around it shows the backdrop.</summary>
public sealed partial class ContentCard : Grid
{
    readonly BrowserModel browser;
    readonly Grid pages = new();
    readonly Grid start = new();
    readonly Grid errors = new();
    readonly Grid find = new() { HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(10) };
    readonly Border shade;
    Tab? shownTab;
    StartPage.StartScreen? startScreen;
    Tab? startTab;
    bool glass, startShown;
    double startTint = 1;

    public ContentCard(BrowserModel browser)
    {
        this.browser = browser;
        CornerRadius = new CornerRadius(Radius.Card);
        Background = Palette.Canvas.Brush();
        BorderBrush = Palette.Hairline.Brush(); BorderThickness = new Thickness(1);
        Shadow = Shadows.Soft; Translation = new System.Numerics.Vector3(0, 0, 6);
        Children.Add(pages); Children.Add(start); Children.Add(errors);
        // While a mica overlay covers the page, the page dims and takes no input (macOS WebSurface shade).
        shade = new Border { Background = new SolidColorBrush(Palette.WithAlpha(Microsoft.UI.Colors.Black, 0.32)), Opacity = 0, IsHitTestVisible = false };
        Children.Add(shade);
        Children.Add(find);
        browser.WebViewCreated += tab => { if (tab.WebView is { } view && view.Parent is null) pages.Children.Add(view); Render(); };
        this.Bind(browser, Render);
    }

    /// <summary>The start page is mica's own surface, so with glass on it lets the frosted shell through; a site keeps an
    /// opaque card. A see-through card drops its raised shadow, which would show through the fill.</summary>
    public void SetGlass(bool glass, double startTint) { this.glass = glass; this.startTint = startTint; ApplyFill(); }

    void ApplyFill()
    {
        var see = glass && startShown;
        Background = see ? new SolidColorBrush(Palette.Canvas.Resolve()) { Opacity = startTint } : Palette.Canvas.Brush();
        Translation = new System.Numerics.Vector3(0, 0, see ? 0 : 6);
    }

    public void SetCovered(bool covered)
    {
        var web = browser.Selected?.WebView is not null && browser.Selected.Error is null;
        Motion.Fade(shade, covered && web ? 1 : 0, TimeSpan.FromSeconds(Motion.Reduced ? 0 : 0.16));
        shade.IsHitTestVisible = covered;
        pages.IsHitTestVisible = !covered;
    }

    void Render()
    {
        var tab = browser.Selected;
        if (tab != shownTab)
        {
            if (shownTab is not null) shownTab.Changed -= RenderTab;
            shownTab = tab;
            if (tab is not null) tab.Changed += RenderTab;
        }
        foreach (var other in browser.Tabs) other.SetVisible(other == tab && other.Error is null);
        RenderTab();
        if (browser.ShowFind && tab?.Core is not null && find.Children.Count == 0) { var bar = new FindBar(tab, browser); find.Children.Add(bar); Motion.Appear(bar, Motion.Edge.Top); }
        else if ((!browser.ShowFind || tab?.Core is null) && find.Children.Count > 0) { var bar = (FindBar)find.Children[0]; bar.Clear(); find.Children.Clear(); }
    }

    void RenderTab()
    {
        var tab = shownTab;
        tab?.SetVisible(tab.Error is null);
        var showStart = tab is not null && tab.WebView is null && tab.Url is null;
        if (showStart != startShown) { startShown = showStart; ApplyFill(); }
        // Each tab gets its own start page (macOS keys StartScreen by tab), so a new tab plays the entrance and keeps
        // its own greeting and typed text. A tab that already played it comes back with the usual fade.
        if (showStart && (startScreen is null || startTab != tab))
        {
            var returning = tab!.Introduced && startScreen is null;
            start.Children.Clear();
            startScreen = new StartPage.StartScreen(browser); startTab = tab;
            start.Children.Add(startScreen);
            if (returning) Motion.Appear(startScreen);
        }
        else if (!showStart && startScreen is not null) { start.Children.Clear(); startScreen = null; startTab = null; }
        errors.Children.Clear();
        if (tab?.Error is { } error) { var page = new ErrorPage(tab, browser, error); errors.Children.Add(page); Motion.Fade(page, 1); }
    }
}

public sealed partial class ErrorPage : Grid
{
    public ErrorPage(Tab tab, BrowserModel browser, string error)
    {
        Background = Palette.Canvas.Brush();
        var terminated = tab.Phase == TabPhase.Terminated;
        var symbol = terminated ? "arrow.triangle.2.circlepath" : tab.CertificateFailure ? "lock.trianglebadge.exclamationmark" : "wifi.exclamationmark";
        var badge = Ui.Rounded(12, Palette.Track.Brush(), child: new Glyph(symbol, 18, Palette.Text2.Brush()) { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center });
        badge.Width = 44; badge.Height = 44; badge.HorizontalAlignment = HorizontalAlignment.Left;
        var stack = new StackPanel { Spacing = Space.Normal, MaxWidth = 480, Margin = new Thickness(40), HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        stack.Children.Add(badge);
        var title = Ui.Text(terminated ? browser.Text("страница остановлена", "Страница остановлена") : browser.Text("страница недоступна", "Страница недоступна"), 24); title.CharacterSpacing = -16; title.Margin = new Thickness(0, Space.Small, 0, 0);
        stack.Children.Add(title);
        if (AddressParser.Host(tab.Url) is { } host) { var h = Ui.Text(host, 13, Palette.Text2.Brush(), Ui.Medium); h.IsTextSelectionEnabled = true; stack.Children.Add(h); }
        var detail = Ui.Text(error, 13, Palette.Text2.Brush(), wrap: true); detail.IsTextSelectionEnabled = true; detail.LineHeight = 19;
        stack.Children.Add(detail);
        var retry = new MButton(terminated ? browser.Text("восстановить", "Восстановить") : browser.Text("повторить", "Повторить"), ButtonKind.Primary);
        retry.Click += tab.Reload;
        var back = new MButton(browser.Text("назад", "Назад")) { IsEnabled = tab.CanBack };
        back.Click += () => { tab.Error = null; tab.GoBack(); tab.Changed2(); };
        var buttons = Ui.H(Space.Small, retry, back); buttons.Margin = new Thickness(0, Space.Small, 0, 0);
        stack.Children.Add(buttons);
        Children.Add(stack);
    }
}

/// <summary>Find on page with WebView2's find API (macOS FindBar with WKWebView.find).</summary>
public sealed partial class FindBar : Grid
{
    readonly Tab tab;
    readonly BrowserModel browser;
    readonly TextBox box;
    readonly TextBlock missing;
    public FindBar(Tab tab, BrowserModel browser)
    {
        this.tab = tab; this.browser = browser;
        browser.FindStepRequested += Step;
        box = MTextField.Bare(new TextBox { PlaceholderText = browser.Text("найти на странице", "Найти на странице"), Width = 180, FontSize = 13 });
        missing = Ui.Text(browser.Text("не найдено", "Не найдено"), 11.5, Palette.Danger.Brush()); missing.Opacity = 0;
        var up = new IconButton("chevron.up", browser.Text("предыдущее совпадение", "Предыдущее совпадение"), 24);
        var down = new IconButton("chevron.down", browser.Text("следующее совпадение", "Следующее совпадение"), 24);
        var close = new IconButton("xmark", browser.Text("закрыть поиск", "Закрыть поиск"), 24);
        up.Click += () => Step(back: true); down.Click += () => Step(back: false);
        close.Click += () => browser.ShowFind = false;
        var row = Ui.H(4, new Glyph("text.magnifyingglass", 12, Palette.Text3.Brush()) { Margin = new Thickness(8, 0, 0, 0) }, box, missing, up, down, close);
        row.Padding = new Thickness(4);
        Children.Add(Ui.Raised(row, 12));
        box.KeyDown += (_, e) =>
        {
            if (e.Key == Windows.System.VirtualKey.Enter) { Step(back: (Microsoft.UI.Input.InputKeyboardSource.GetKeyStateForCurrentThread(Windows.System.VirtualKey.Shift) & Windows.UI.Core.CoreVirtualKeyStates.Down) != 0); e.Handled = true; }
            if (e.Key == Windows.System.VirtualKey.Escape) { browser.ShowFind = false; e.Handled = true; }
        };
        box.TextChanged += async (_, _) => await StartAsync();
        Loaded += (_, _) => box.Focus(FocusState.Programmatic);
    }

    async Task StartAsync()
    {
        if (tab.Core is not { } core || tab.Owner?.Store.Engine.Environment is not { } env) return;
        if (box.Text.Length == 0) { core.Find.Stop(); Motion.Fade(missing, 0); return; }
        var options = env.CreateFindOptions();
        options.FindTerm = box.Text;
        options.IsCaseSensitive = false;
        options.SuppressDefaultFindDialog = true;
        options.ShouldHighlightAllMatches = true;
        await core.Find.StartAsync(options);
        Motion.Fade(missing, core.Find.MatchCount == 0 ? 1 : 0);
    }

    void Step(bool back)
    {
        if (tab.Core is not { } core || box.Text.Length == 0) return;
        if (back) core.Find.FindPrevious(); else core.Find.FindNext();
    }

    public void Clear() { browser.FindStepRequested -= Step; tab.Core?.Find.Stop(); }
}
