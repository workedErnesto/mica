using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
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
    public CoreWebView2DownloadOperation? Operation { get; private set; }
    readonly DownloadManager manager;

    public DownloadItem(DownloadManager manager, DownloadRecord record)
    {
        this.manager = manager;
        Id = record.Id; Name = record.Name; Destination = record.Destination; Source = record.Source; Bytes = record.Bytes; Total = record.Total;
        State = record.State == "complete" ? DownloadState.Complete : DownloadState.Cancelled;
    }

    public DownloadItem(DownloadManager manager, CoreWebView2DownloadStartingEventArgs e)
    {
        this.manager = manager;
        Name = DownloadSafety.Filename(Path.GetFileName(e.ResultFilePath));
        Source = e.DownloadOperation.Uri.StartsWith("http", StringComparison.Ordinal) ? e.DownloadOperation.Uri : null;
        Operation = e.DownloadOperation;
        Total = (long)e.DownloadOperation.TotalBytesToReceive;
    }

    public DownloadRecord Record => new() { Id = Id, Name = Name, State = State.ToString().ToLowerInvariant(), Destination = Destination, Source = Source, Bytes = Bytes, Total = Total };
    public double Fraction => Total > 0 ? (double)Bytes / Total : 0;

    public void Attach(string destination)
    {
        Destination = destination;
        Name = Path.GetFileName(destination);
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
            manager.Persist(this);
            Notify();
        };
        manager.Persist(this);
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
            browser.Store.DownloadsChanged += () =>
            {
                var known = Items.Select(i => i.Id).ToHashSet();
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
            var picker = new FileSavePicker { SuggestedStartLocation = PickerLocationId.Downloads, SuggestedFileName = Path.GetFileNameWithoutExtension(item.Name) };
            var extension = Path.GetExtension(item.Name);
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

    public void CancelAll() { foreach (var item in Items.Where(i => i.State is DownloadState.Running or DownloadState.Choosing or DownloadState.Paused).ToList()) item.Cancel(); }
}

public sealed partial class DownloadsPanel : Grid
{
    readonly BrowserModel browser;
    readonly StackPanel list = new() { Spacing = Space.Small };
    public DownloadsPanel(BrowserModel browser)
    {
        this.browser = browser;
        var scroll = Ui.Scroll(list); scroll.VerticalScrollBarVisibility = ScrollBarVisibility.Hidden;
        Children.Add(scroll);
        this.Bind(browser.Downloads, Render);
    }
    void Render()
    {
        list.Children.Clear();
        if (browser.Downloads.Items.Count == 0) { list.Children.Add(new EmptyState("arrow.down.circle", browser.Text("загрузки появятся здесь", "Загрузки появятся здесь")) { Margin = new Thickness(0, 48, 0, 0) }); return; }
        foreach (var item in browser.Downloads.Items) list.Children.Add(new DownloadRow(item, browser));
    }
}

public sealed partial class DownloadRow : Grid
{
    public DownloadRow(DownloadItem item, BrowserModel browser)
    {
        var frame = Ui.Rounded(Radius.Row + 2, Palette.Canvas.Brush(), Palette.Hairline.Brush(), 1);
        Children.Add(frame);
        var stack = new StackPanel { Spacing = Space.Small, Padding = new Thickness(12) };
        Children.Add(stack);
        void Render()
        {
            stack.Children.Clear();
            var symbol = item.State switch { DownloadState.Complete => "checkmark", DownloadState.Failed => "exclamationmark.triangle", DownloadState.Cancelled => "xmark", _ => "arrow.down" };
            var badge = Ui.Rounded(8, Palette.Track.Brush(), child: new Glyph(symbol, 13, item.State == DownloadState.Failed ? Palette.Danger.Brush() : Palette.Text2.Brush()) { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center });
            badge.Width = 30; badge.Height = 30;
            var name = Ui.Text(item.Name.Length == 0 ? browser.Text("выбор файла", "Выбор файла") : item.Name, 12.5, null, Ui.Medium, wrap: true); name.MaxLines = 2;
            var status = Ui.Text(Status(item, browser), 11.5, Palette.Text3.Brush(), wrap: true); status.IsTextSelectionEnabled = true;
            var head = new Grid { ColumnSpacing = 10 }; head.ColumnDefinitions.Add(Ui.Auto()); head.ColumnDefinitions.Add(Ui.Star());
            head.Column(badge, 0); head.Column(Ui.V(2, name, status), 1);
            stack.Children.Add(head);
            if (item.State is DownloadState.Running or DownloadState.Paused)
            {
                var track = new Grid { Height = 4 };
                track.Children.Add(Ui.Rounded(2, Palette.Track.Brush()));
                var fill = Ui.Rounded(2, Look.Primary); fill.HorizontalAlignment = HorizontalAlignment.Left;
                track.Children.Add(fill);
                track.SizeChanged += (_, e) => fill.Width = e.NewSize.Width * (item.Total > 0 ? item.Fraction : 0.12);
                stack.Children.Add(track);
            }
            var buttons = Ui.H(6);
            switch (item.State)
            {
                case DownloadState.Running:
                    var pause = new MButton(browser.Text("пауза", "Пауза"), compact: true); pause.Click += item.Pause; buttons.Children.Add(pause);
                    var cancel = new MButton(browser.Text("отменить", "Отменить"), compact: true); cancel.Click += item.Cancel; buttons.Children.Add(cancel);
                    break;
                case DownloadState.Paused:
                    var resume = new MButton(browser.Text("возобновить", "Возобновить"), compact: true); resume.Click += item.Resume; buttons.Children.Add(resume);
                    var stop = new MButton(browser.Text("отменить", "Отменить"), compact: true); stop.Click += item.Cancel; buttons.Children.Add(stop);
                    break;
                case DownloadState.Complete:
                    var open = new MButton(browser.Text("открыть", "Открыть"), ButtonKind.Primary, compact: true); open.Click += item.Open; buttons.Children.Add(open);
                    var reveal = new MButton(browser.Text("показать в проводнике", "Показать в проводнике"), compact: true); reveal.Click += item.Reveal; buttons.Children.Add(reveal);
                    break;
                case DownloadState.Cancelled or DownloadState.Failed:
                    var retry = new MButton(item.Operation?.CanResume == true ? browser.Text("возобновить", "Возобновить") : browser.Text("повторить", "Повторить"), compact: true) { IsEnabled = item.Source is not null || item.Operation?.CanResume == true };
                    retry.Click += item.Retry; buttons.Children.Add(retry);
                    break;
            }
            stack.Children.Add(buttons);
        }
        this.Bind(item, Render);
    }

    static string Size(long bytes) => bytes switch { < 1024 => bytes + " B", < 1024 * 1024 => (bytes / 1024.0).ToString("0") + " KB", < 1024L * 1024 * 1024 => (bytes / 1048576.0).ToString("0.0") + " MB", _ => (bytes / 1073741824.0).ToString("0.00") + " GB" };

    static string Status(DownloadItem item, BrowserModel b) => item.State switch
    {
        DownloadState.Running => item.Total > 0 ? Size(item.Bytes) + " / " + Size(item.Total) : Size(item.Bytes),
        DownloadState.Paused => b.Text("пауза, ", "Пауза, ") + Size(item.Bytes),
        DownloadState.Complete => b.Text("сохранено", "Сохранено"),
        DownloadState.Cancelled => b.Text("отменено", "Отменено"),
        DownloadState.Failed => item.FailureText ?? b.Text("ошибка загрузки", "Ошибка загрузки"),
        _ => b.Text("ожидает выбора места", "Ожидает выбора места"),
    };
}
