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

    /// <summary>A page mica writes itself (PageSaver) rather than a WebView2 download (macOS DownloadItem.saving).</summary>
    public bool Saving { get; }
    /// <summary>Makes the saved page again into the same file; the retry button calls it.</summary>
    public Action? SaveAgain { get; set; }
    public CancellationTokenSource? Work { get; set; }
    double savingFraction;
    /// <summary>The tab whose page is being saved; the save button shows progress for it.</summary>
    public Tab? Page { get; }

    public DownloadItem(DownloadManager manager, string destination, Tab page)
    {
        this.manager = manager; Saving = true; Page = page;
        Destination = destination; Name = System.IO.Path.GetFileName(destination);
        State = DownloadState.Running; Date = DateTimeOffset.Now; savingFraction = 0.05;
    }

    public void SavingProgress(double fraction) { savingFraction = fraction; Notify(); }
    public void SavingStarted() { FailureText = null; savingFraction = 0.05; State = DownloadState.Running; manager.Persist(this); Notify(); manager.Touch(); }
    public void SavingFinished()
    {
        if (State != DownloadState.Running) return;
        Bytes = Destination is { } path && File.Exists(path) ? new FileInfo(path).Length : 0; Total = Bytes;
        State = DownloadState.Complete; savingFraction = 1; FailureText = null;
        Celebrate(); manager.Persist(this); Notify(); manager.Touch();
    }
    public void SavingFailed(string reason)
    {
        if (State != DownloadState.Running) return;
        FailureText = reason; State = DownloadState.Failed;
        manager.Persist(this); Notify(); manager.Touch();
    }

    public DownloadRecord Record => new() { Id = Id, Name = Name, State = State.ToString().ToLowerInvariant(), Destination = Destination, Source = Source, Bytes = Bytes, Total = Total, Date = Date };
    public double Fraction => Saving ? savingFraction : Total > 0 ? (double)Bytes / Total : 0;
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

    public void Cancel() { Operation?.Cancel(); Work?.Cancel(); State = DownloadState.Cancelled; manager.Persist(this); Notify(); if (Saving) manager.Touch(); }
    public void Pause() { if (Operation is { } o && o.State == CoreWebView2DownloadState.InProgress) { o.Pause(); State = DownloadState.Paused; Notify(); } }
    public void Resume() { if (Operation is { CanResume: true } o) { o.Resume(); State = DownloadState.Running; Notify(); } }
    public void Retry() { if (SaveAgain is { } again) again(); else if (Operation?.CanResume == true) Resume(); else if (Source is { } url) manager.Browser.Selected?.Core?.Navigate(url); }

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

    /// <summary>A page mica saves itself (macOS add(saved:)). The panel opens when the file is ready: opening it at once
    /// would narrow the page while it is being captured. Until then the save button shows the progress.</summary>
    public void AddSaved(DownloadItem item) { Items.Insert(0, item); Persist(item); Notify(); }

    /// <summary>Tells listeners (the save button) that a saved page changed state.</summary>
    public void Touch() => Notify();

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
