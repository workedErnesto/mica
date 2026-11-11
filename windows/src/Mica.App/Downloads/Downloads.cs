using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;
using Microsoft.UI.Xaml.Shapes;
using Path = Microsoft.UI.Xaml.Shapes.Path;
using Microsoft.Web.WebView2.Core;
using Mica.Core;
using Mica.Design;
using Windows.Storage.Pickers;

namespace Mica.App.Downloads;

/// <summary>One download (macOS DownloadItem): the place is chosen in the system save dialog, progress comes from
/// WebView2 events without polling, pause and resume use Chromium's own support. Windows SmartScreen and Mark of the
/// Web are applied by WebView2's download manager; mica opens nothing automatically.</summary>
public sealed partial class DownloadItem : Observable
{
    public Guid Id { get; } = Guid.NewGuid();
    public string Name { get; set; } = "";
    public DownloadState State { get; private set; } = DownloadState.Choosing;
    public long Bytes { get; private set; }
    public long Total { get; private set; }
    public string? Destination { get; private set; }
    public string? Source { get; private set; }
    public string? FailureText { get; private set; }
    /// <summary>When the download started; null only for an old record whose file is gone.</summary>
    public DateTimeOffset? Date { get; private set; }
    /// <summary>True for a short while after the file lands, while the row shows a drawn checkmark.</summary>
    public bool JustFinished { get; private set; }
    /// <summary>An old record got its date or size from the file and should be saved once.</summary>
    internal bool Backfilled { get; private set; }
    int hold;
    public CoreWebView2DownloadOperation? Operation { get; private set; }
    readonly DownloadManager manager;

    public DownloadItem(DownloadManager manager, DownloadRecord record)
    {
        this.manager = manager;
        Id = record.Id; Name = record.Name; Destination = record.Destination; Source = record.Source; Bytes = record.Bytes; Total = record.Total;
        State = record.State == "complete" ? DownloadState.Complete : DownloadState.Cancelled;
        Date = record.Date;
        if ((Date is null || (State == DownloadState.Complete && Size == 0)) && Destination is { } path && File.Exists(path))
        {
            // Records written before downloads kept a date: take the date and size from the file once.
            Date ??= new DateTimeOffset(File.GetCreationTime(path));
            if (Size == 0) Total = new FileInfo(path).Length;
            Backfilled = true;
        }
    }

    public DownloadItem(DownloadManager manager, CoreWebView2DownloadStartingEventArgs e)
    {
        this.manager = manager;
        Name = DownloadSafety.Filename(System.IO.Path.GetFileName(e.ResultFilePath));
        Source = e.DownloadOperation.Uri.StartsWith("http", StringComparison.Ordinal) ? e.DownloadOperation.Uri : null;
        Operation = e.DownloadOperation;
        Total = (long)e.DownloadOperation.TotalBytesToReceive;
        Date = DateTimeOffset.Now;
    }

    public DownloadRecord Record => new() { Id = Id, Name = Name, State = State.ToString().ToLowerInvariant(), Destination = Destination, Source = Source, Bytes = Bytes, Total = Total, Date = Date };
    public double Fraction => Total > 0 ? (double)Bytes / Total : 0;
    public DownloadKind Kind => DownloadKinds.Of(Name);
    /// <summary>Final size of a finished file; while running, Total is what the server announced.</summary>
    public long Size => Math.Max(Total, Bytes);
    /// <summary>Waiting for a place, receiving bytes or paused: such a row cannot be removed from the list.</summary>
    public bool Active => State is DownloadState.Choosing or DownloadState.Running or DownloadState.Paused;

    public void Attach(string destination)
    {
        Destination = destination;
        Name = System.IO.Path.GetFileName(destination);
        State = DownloadState.Running;
        if (Operation is not { } operation) return;
        operation.BytesReceivedChanged += (_, _) => { Bytes = operation.BytesReceived; Total = (long)operation.TotalBytesToReceive; Notify(); };
        operation.StateChanged += (_, _) =>
        {
            State = operation.State switch
            {
                CoreWebView2DownloadState.Completed => DownloadState.Complete,
                CoreWebView2DownloadState.Interrupted when operation.InterruptReason == CoreWebView2DownloadInterruptReason.UserCanceled => DownloadState.Cancelled,
                CoreWebView2DownloadState.Interrupted when operation.CanResume => DownloadState.Paused,
                CoreWebView2DownloadState.Interrupted => DownloadState.Failed,
                _ => DownloadState.Running,
            };
            if (State == DownloadState.Failed) FailureText = operation.InterruptReason.ToString();
            if (State == DownloadState.Complete) { Bytes = operation.BytesReceived; Total = Math.Max(Total, Bytes); Celebrate(); }
            manager.Persist(this);
            Notify();
        };
        manager.Persist(this);
        Notify();
    }

    /// <summary>Checkmark for MotionTokens.DoneHold seconds, then the kind icon.</summary>
    async void Celebrate()
    {
        var mine = ++hold;
        JustFinished = true;
        await Task.Delay(TimeSpan.FromSeconds(MotionTokens.DoneHold));
        if (mine != hold) return;
        JustFinished = false;
        Notify();
    }

    public void Cancel() { Operation?.Cancel(); State = DownloadState.Cancelled; manager.Persist(this); Notify(); }
    public void Pause() { if (Operation is { } o && o.State == CoreWebView2DownloadState.InProgress) { o.Pause(); State = DownloadState.Paused; Notify(); } }
    public void Resume() { if (Operation is { CanResume: true } o) { o.Resume(); State = DownloadState.Running; Notify(); } }
    public void Retry() { if (Operation?.CanResume == true) Resume(); else if (Source is { } url) manager.Browser.Selected?.Core?.Navigate(url); }

    /// <summary>Opening a downloaded file asks first; Windows checks the file itself (SmartScreen, Mark of the Web).</summary>
    public async void Open()
    {
        if (Destination is not { } path || !File.Exists(path)) return;
        var s = manager.Browser.Store;
        if (await Dialogs.Ask(manager.Browser.Window, s.Text("открыть файл?", "Открыть файл?"), Name, [s.Text("отмена", "Отмена"), s.Text("открыть", "Открыть")]) != 1) return;
        var file = await Windows.Storage.StorageFile.GetFileFromPathAsync(path);
        await Windows.System.Launcher.LaunchFileAsync(file);
    }

    public void Reveal()
    {
        if (Destination is not { } path) return;
        System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo("explorer.exe", $"/select,\"{path}\"") { UseShellExecute = true });
    }
}

public sealed partial class DownloadManager : Observable
{
    public BrowserModel Browser { get; }
    public List<DownloadItem> Items { get; } = [];
    public DownloadManager(BrowserModel browser)
    {
        Browser = browser;
        if (!browser.PrivateMode)
        {
            foreach (var record in browser.Store.DownloadRecords) Items.Add(new DownloadItem(this, record));
            foreach (var item in Items.Where(i => i.Backfilled).ToList()) Persist(item);
            browser.Store.DownloadsChanged += () =>
            {
                var known = Items.Select(i => i.Id).ToHashSet();
                var kept = browser.Store.DownloadRecords.Select(r => r.Id).ToHashSet();
                // Another window removed a finished row: drop it here too. Active downloads stay until they end.
                Items.RemoveAll(i => !kept.Contains(i.Id) && !i.Active);
                foreach (var record in browser.Store.DownloadRecords.Where(r => !known.Contains(r.Id))) Items.Add(new DownloadItem(this, record));
                Notify();
            };
        }
    }

    public void Persist(DownloadItem item)
    {
        if (Browser.PrivateMode) return;
        var records = Browser.Store.DownloadRecords.ToList();
        var index = records.FindIndex(r => r.Id == item.Id);
        if (index >= 0) records[index] = item.Record; else records.Insert(0, item.Record);
        Browser.Store.SetDownloadRecords(records);
    }

    /// <summary>WebView2 asks where to save; mica shows the system save dialog with the proposed safe name.</summary>
    public async void Start(Tab tab, CoreWebView2DownloadStartingEventArgs e)
    {
        var deferral = e.GetDeferral();
        e.Handled = true;
        var item = new DownloadItem(this, e);
        Items.Insert(0, item);
        Browser.Panel = LibraryPanel.Downloads;
        Notify();
        try
        {
            var picker = new FileSavePicker { SuggestedStartLocation = PickerLocationId.Downloads, SuggestedFileName = System.IO.Path.GetFileNameWithoutExtension(item.Name) };
            var extension = System.IO.Path.GetExtension(item.Name);
            picker.FileTypeChoices.Add(extension.Length > 0 ? extension.TrimStart('.').ToUpperInvariant() : Browser.Text("файл", "Файл"), [extension.Length > 0 ? extension : "."]);
            if (Browser.Window is { } window) WinRT.Interop.InitializeWithWindow.Initialize(picker, Win32.Handle(window));
            var file = await picker.PickSaveFileAsync();
            if (file is null) { e.Cancel = true; Items.Remove(item); Notify(); return; }
            var path = file.Path;
            // The picker created an empty placeholder; WebView2 writes the real file in its place.
            try { File.Delete(path); } catch (IOException) { }
            e.ResultFilePath = path;
            item.Attach(path);
        }
        catch (Exception ex) { e.Cancel = true; Items.Remove(item); Browser.Show(Browser.Text("загрузка не начата: ", "Загрузка не начата: ") + ex.Message); }
        finally { deferral.Complete(); Notify(); }
    }

    /// <summary>Takes a finished, failed or cancelled download off the list. The file itself stays where it was saved.</summary>
    public void Remove(DownloadItem item)
    {
        if (item.Active) return;
        Items.Remove(item);
        Notify();
        if (!Browser.PrivateMode) Browser.Store.SetDownloadRecords(Browser.Store.DownloadRecords.Where(r => r.Id != item.Id).ToList());
    }

    public void CancelAll() { foreach (var item in Items.Where(i => i.State is DownloadState.Running or DownloadState.Choosing or DownloadState.Paused).ToList()) item.Cancel(); }
}


/// <summary>Downloads in the library panel, laid out like history: search, rows grouped by day, actions on hover.</summary>
public sealed partial class DownloadsPanel : Grid
{
    readonly BrowserModel browser;
    readonly MTextField query;
    readonly StackPanel list = new() { Spacing = 2 };
    public DownloadsPanel(BrowserModel browser)
    {
        this.browser = browser;
        RowSpacing = Space.Normal;
        RowDefinitions.Add(Ui.RowAuto()); RowDefinitions.Add(Ui.RowStar());
        query = new MTextField(browser.Text("поиск", "Поиск"), symbol: "magnifyingglass");
        query.Box.TextChanged += (_, _) => Render();
        this.Row(query, 0);
        var scroll = Ui.Scroll(list); scroll.VerticalScrollBarVisibility = ScrollBarVisibility.Hidden;
        this.Row(scroll, 1);
        this.Bind(browser.Downloads, Render);
    }

    void Render()
    {
        var q = query.Text;
        var items = browser.Downloads.Items.Where(i => q.Length == 0 || i.Name.Contains(q, StringComparison.CurrentCultureIgnoreCase)).ToList();
        list.Children.Clear();
        if (items.Count == 0)
        {
            list.Children.Add(new EmptyState("arrow.down.circle", q.Length == 0 ? browser.Text("загрузки появятся здесь", "Загрузки появятся здесь") : browser.Text("ничего не найдено", "Ничего не найдено")) { Margin = new Thickness(0, 48, 0, 0) });
            return;
        }
        foreach (var (day, group) in Days(items))
        {
            list.Children.Add(Library.SidePanel.DayHeader(day, browser));
            foreach (var item in group) list.Children.Add(new DownloadRow(item, browser));
        }
    }

    /// <summary>Newest day first, rows inside a day newest first; downloads without a date go last (macOS DownloadsPanel.days).</summary>
    static IEnumerable<(DateTime? Day, List<DownloadItem> Items)> Days(IEnumerable<DownloadItem> items) =>
        items.OrderByDescending(i => i.Date ?? DateTimeOffset.MinValue)
            .GroupBy(i => i.Date?.LocalDateTime.Date)
            .Select(g => (g.Key, g.ToList()));
}

/// <summary>One download, built like a history row: badge, name, detail line, quick action and menu on hover.</summary>
public sealed partial class DownloadRow : Grid
{
    readonly DownloadItem item; readonly BrowserModel browser;
    readonly TextBlock name, detail;
    readonly DownloadBadge badge;
    readonly StackPanel actions = Ui.H(2);
    readonly Grid quick = new();
    DownloadState? shownState;

    public DownloadRow(DownloadItem item, BrowserModel browser)
    {
        this.item = item; this.browser = browser;
        Background = Palette.Clear; IsTabStop = true;
        var plate = Ui.Rounded(Radius.Row);
        badge = new DownloadBadge(item);
        name = Ui.Text("", 12.5); name.TextTrimming = TextTrimming.CharacterEllipsis;
        detail = Ui.Text("", 11, Palette.Text3.Brush());
        var row = new Grid { Padding = new Thickness(8, 6, 64, 6), ColumnSpacing = 10 };
        row.ColumnDefinitions.Add(Ui.Auto()); row.ColumnDefinitions.Add(Ui.Star());
        row.Column(badge, 0); row.Column(Ui.V(1, name, detail), 1);
        actions.Children.Add(quick);
        actions.Children.Add(new MenuButton(browser.Text("действия", "Действия"), Menu));
        actions.HorizontalAlignment = HorizontalAlignment.Right; actions.VerticalAlignment = VerticalAlignment.Center;
        actions.Margin = new Thickness(0, 0, 6, 0); actions.Opacity = 0;
        Children.Add(plate); Children.Add(row); Children.Add(actions);
        Interaction? interaction = null;
        interaction = new Interaction(this, () => { plate.Background = interaction!.Hover ? Palette.Hover.Brush() : Palette.Clear; Motion.Fade(actions, interaction.Hover ? 1 : 0); }, 0.98, plate);
        interaction.Invoked += () => { if (item.State == DownloadState.Complete) item.Open(); };
        this.ContextMenu(Menu);
        this.Bind(item, Render);
    }

    void Render()
    {
        name.Text = item.Name.Length == 0 ? browser.Text("выбор файла", "Выбор файла") : item.Name;
        detail.Text = Detail();
        detail.Foreground = item.State == DownloadState.Failed ? Palette.Danger.Brush() : Palette.Text3.Brush();
        AutomationProperties.SetName(this, item.Name + ", " + detail.Text);
        badge.Update();
        if (shownState == item.State) return;
        shownState = item.State;
        quick.Children.Clear();
        IconButton? button = item.State switch
        {
            DownloadState.Running => new IconButton("xmark", browser.Text("отменить", "Отменить"), 24, click: item.Cancel),
            DownloadState.Choosing => null,
            DownloadState.Paused => new IconButton("arrow.clockwise", browser.Text("возобновить", "Возобновить"), 24, click: item.Resume),
            DownloadState.Complete => new IconButton("folder", browser.Text("показать в проводнике", "Показать в проводнике"), 24, click: item.Reveal),
            _ => item.Source is not null || item.Operation?.CanResume == true ? new IconButton("arrow.clockwise", RetryTitle, 24, click: item.Retry) : null,
        };
        if (button is not null) quick.Children.Add(button);
    }

    string RetryTitle => item.Operation?.CanResume == true ? browser.Text("возобновить", "Возобновить") : browser.Text("повторить", "Повторить");

    IEnumerable<MenuEntry> Menu()
    {
        if (item.State == DownloadState.Complete)
        {
            yield return MenuEntry.Item(browser.Text("открыть", "Открыть"), item.Open, "arrow.up.right");
            yield return MenuEntry.Item(browser.Text("показать в проводнике", "Показать в проводнике"), item.Reveal, "folder");
        }
        if (item.State == DownloadState.Running) yield return MenuEntry.Item(browser.Text("пауза", "Пауза"), item.Pause);
        if (item.Source is { } source)
            yield return MenuEntry.Item(browser.Text("копировать адрес загрузки", "Копировать адрес загрузки"), () => { var data = new Windows.ApplicationModel.DataTransfer.DataPackage(); data.SetText(source); Windows.ApplicationModel.DataTransfer.Clipboard.SetContent(data); }, "link");
        yield return MenuEntry.Separator;
        if (item.Active) yield return MenuEntry.Item(browser.Text("отменить", "Отменить"), item.Cancel, "xmark", destructive: true);
        else yield return MenuEntry.Item(browser.Text("убрать из списка", "Убрать из списка"), () => browser.Downloads.Remove(item), "minus.circle");
    }

    static string Size(long bytes) => bytes switch { < 1024 => bytes + " B", < 1024 * 1024 => (bytes / 1024.0).ToString("0") + " KB", < 1024L * 1024 * 1024 => (bytes / 1048576.0).ToString("0.0") + " MB", _ => (bytes / 1073741824.0).ToString("0.00") + " GB" };

    /// <summary>Second line: time and size when finished, progress while running, the reason otherwise.</summary>
    string Detail() => item.State switch
    {
        DownloadState.Running => item.Total > 0 ? Size(item.Bytes) + " " + browser.Text("из", "из") + " " + Size(item.Total) : Size(item.Bytes),
        DownloadState.Paused => browser.Text("пауза, ", "Пауза, ") + Size(item.Bytes),
        DownloadState.Complete => string.Join(", ", new[] { item.Date?.LocalDateTime.ToString("t", browser.Store.Culture), item.Size > 0 ? Size(item.Size) : null }.Where(p => p is not null)),
        DownloadState.Cancelled => browser.Text("отменено", "Отменено"),
        DownloadState.Failed => item.FailureText ?? browser.Text("ошибка загрузки", "Ошибка загрузки"),
        _ => browser.Text("ожидает выбора места", "Ожидает выбора места"),
    };
}

/// <summary>Leading mark of a download row (macOS DownloadBadge). While the file arrives: one arrow inside a progress
/// ring. When it lands: a closed ring and a checkmark stroked in, held for MotionTokens.DoneHold. Then: the kind icon.</summary>
public sealed partial class DownloadBadge : Grid
{
    const double S = Chrome.RowIcon;
    enum Phase { Progress, Done, Kind }
    readonly DownloadItem item;
    readonly Grid progress = new(), done = new();
    readonly Mica.Design.ProgressRing ring = new(S);
    readonly RotateTransform spin = new() { CenterX = S / 2, CenterY = S / 2 };
    readonly Storyboard turning = new() { RepeatBehavior = RepeatBehavior.Forever };
    readonly Path check;
    Border? kind;
    Phase? shown;
    DownloadKind? shownKind; DownloadState? shownState;

    public DownloadBadge(DownloadItem item)
    {
        this.item = item;
        Width = S; Height = S; IsHitTestVisible = false;
        AutomationProperties.SetAccessibilityView(this, Microsoft.UI.Xaml.Automation.Peers.AccessibilityView.Raw);
        ring.RenderTransform = spin;
        var turn = new DoubleAnimation { From = 0, To = 360, Duration = TimeSpan.FromSeconds(1) };
        Storyboard.SetTarget(turn, spin); Storyboard.SetTargetProperty(turn, "Angle");
        turning.Children.Add(turn);
        progress.Children.Add(ring);
        progress.Children.Add(new Glyph("arrow.down", S * 0.4, Palette.Text2.Brush()) { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center });
        var accent = Look.Accent is null ? Palette.Ink.Brush() : Look.Primary;
        done.Children.Add(new Ellipse { Width = S - 2, Height = S - 2, Stroke = accent, StrokeThickness = 2 });
        var figure = new PathFigure { StartPoint = new Windows.Foundation.Point(S * 0.29, S * 0.52), IsFilled = false };
        figure.Segments.Add(new LineSegment { Point = new Windows.Foundation.Point(S * 0.44, S * 0.66) });
        figure.Segments.Add(new LineSegment { Point = new Windows.Foundation.Point(S * 0.72, S * 0.36) });
        var geometry = new PathGeometry(); geometry.Figures.Add(figure);
        check = new Path { Data = geometry, Stroke = accent, StrokeThickness = 2, StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round, StrokeLineJoin = PenLineJoin.Round };
        done.Children.Add(check);
        progress.Opacity = 0; done.Opacity = 0;
        Children.Add(progress); Children.Add(done);
        Unloaded += (_, _) => turning.Stop();
    }

    static string Symbol(DownloadKind kind) => kind switch
    {
        DownloadKind.Image => "photo",
        DownloadKind.Video => "film",
        DownloadKind.Archive => "archivebox",
        DownloadKind.Document => "doc.text",
        _ => "doc",
    };

    public void Update()
    {
        var phase = item.JustFinished ? Phase.Done : item.Active ? Phase.Progress : Phase.Kind;
        if (phase == Phase.Progress)
        {
            var unknown = item.State == DownloadState.Running && item.Total <= 0;
            ring.SetProgress(item.State is DownloadState.Running or DownloadState.Paused ? (unknown ? 0.25 : item.Fraction) : 0);
            if (unknown && !Motion.Reduced) turning.Begin(); else { turning.Stop(); spin.Angle = 0; }
        }
        else turning.Stop();
        if (phase == Phase.Kind && (kind is null || shownKind != item.Kind || shownState != item.State))
        {
            if (kind is not null) Children.Remove(kind);
            var failed = item.State == DownloadState.Failed;
            kind = Ui.Rounded(S * 0.3, Palette.Track.Brush(), child: new Glyph(failed ? "exclamationmark.triangle" : Symbol(item.Kind), S * 0.5, failed ? Palette.Danger.Brush() : Palette.Text2.Brush())
                { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center, Opacity = item.State == DownloadState.Cancelled ? 0.5 : 1 });
            kind.Width = S; kind.Height = S; kind.Opacity = shown == Phase.Kind ? 1 : 0;
            Children.Add(kind);
            shownKind = item.Kind; shownState = item.State;
        }
        if (shown == phase) return;
        var first = shown is null;
        shown = phase;
        Show(progress, phase == Phase.Progress, first);
        Show(done, phase == Phase.Done, first);
        if (kind is not null) Show(kind, phase == Phase.Kind, first);
        if (phase == Phase.Done) DrawCheck();
    }

    /// <summary>Cross-fade with a small pop, as SwiftUI Motion.pop; the first render and Reduce Motion skip the movement.</summary>
    static void Show(UIElement layer, bool visible, bool immediately)
    {
        if (immediately) { layer.Opacity = visible ? 1 : 0; return; }
        Motion.Fade(layer, visible ? 1 : 0, TimeSpan.FromSeconds(0.18));
        if (!visible || Motion.Reduced) return;
        var visual = Microsoft.UI.Xaml.Hosting.ElementCompositionPreview.GetElementVisual(layer);
        visual.CenterPoint = new System.Numerics.Vector3((float)S / 2, (float)S / 2, 0);
        visual.Scale = new System.Numerics.Vector3((float)MotionTokens.PopScale, (float)MotionTokens.PopScale, 1);
        Motion.Scale(layer, 1, Motion.Snappy);
    }

    /// <summary>Strokes the checkmark from the short arm to the long one by moving its dash offset.</summary>
    void DrawCheck()
    {
        var length = (Math.Sqrt(Math.Pow(S * 0.15, 2) + Math.Pow(S * 0.14, 2)) + Math.Sqrt(Math.Pow(S * 0.28, 2) + Math.Pow(S * 0.30, 2))) / check.StrokeThickness;
        check.StrokeDashArray = [length, length];
        if (Motion.Reduced) { check.StrokeDashOffset = 0; return; }
        check.StrokeDashOffset = length;
        var draw = new DoubleAnimation { From = length, To = 0, BeginTime = TimeSpan.FromSeconds(0.06), Duration = TimeSpan.FromSeconds(MotionTokens.CheckDraw), EnableDependentAnimation = true, EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseOut } };
        Storyboard.SetTarget(draw, check); Storyboard.SetTargetProperty(draw, "StrokeDashOffset");
        var story = new Storyboard(); story.Children.Add(draw); story.Begin();
    }
}
