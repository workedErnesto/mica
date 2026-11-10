using System.Runtime.InteropServices;
using System.Text.Json;
using Mica.Core;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Microsoft.Web.WebView2.Core;

namespace Mica.App;

/// <summary>A tab and its WebView2 (macOS Tab with WKWebView). Unselected live tabs stay alive and are collapsed,
/// which tells WebView2 they are hidden so Chromium throttles them; nothing is unloaded on a timer.</summary>
public sealed partial class Tab : Observable
{
    public Guid Id { get; }
    public BrowserModel? Owner { get; private set; }
    public string? Url { get; set; }
    public string Title { get; set; }
    public bool Pinned { get; set; }
    public TabPhase Phase { get; set; }
    public bool Loading { get; private set; }
    /// <summary>WebView2 reports navigation milestones, not byte progress: start, response, DOM ready, finish.</summary>
    public double Progress { get; private set; }
    public bool CanBack { get; private set; }
    public bool CanForward { get; private set; }
    public bool Secure { get; private set; }
    public string? Error { get; set; }
    public CoreWebView2WebErrorStatus? Failure { get; private set; }
    public double Zoom { get; private set; } = 1;
    /// <summary>Site icon for the current host from this window's icon store, or null until one is known.</summary>
    /// <summary>The icon the current page reported (FaviconChanged), else the stored icon of the page's origin.</summary>
    public ImageSource? Favicon => pageFavicon is not null && pageFaviconKey == Favicons.Key(Url) ? pageFavicon : Owner?.Favicons.Image(Url);
    ImageSource? pageFavicon;
    string? pageFaviconKey;
    public WebView2? WebView { get; private set; }
    /// <summary>The start page of this tab already played its entrance; going back to the tab shows it at rest.</summary>
    public bool Introduced { get; set; }
    public CoreWebView2? Core { get; private set; }
    Task? initializing;
    string? pendingUrl;
    string? pendingFile;
    bool fileHistoryNavigation;
    readonly HashSet<string> openedFiles = new(StringComparer.OrdinalIgnoreCase);
    bool blockingFilterInstalled;
    internal int BlockedRequestCount { get; private set; }
    readonly Passwords.PasswordBridge passwords;

    public SavedTab Saved => new() { Id = Id, Url = Url, Title = Title, Pinned = Pinned };

    public Tab(SavedTab saved, BrowserModel owner, bool restored)
    {
        Id = saved.Id; Url = saved.Url; Title = saved.Title; Pinned = saved.Pinned; Owner = owner;
        Phase = restored && saved.Url is not null ? TabPhase.Restored : TabPhase.Fresh;
        passwords = new Passwords.PasswordBridge(this);
    }

    public void Changed2() => Notify();

    public string DisplayTitle(Store store) => Title.Length > 0 ? Title : AddressParser.Host(Url) ?? store.Text("новая вкладка", "Новая вкладка");

    public Task MakeWebView()
    {
        if (initializing is not null || Owner is null) return initializing ?? Task.CompletedTask;
        var owner = Owner;
        WebView = new WebView2 { Visibility = Visibility.Collapsed, DefaultBackgroundColor = Microsoft.UI.Colors.White };
        owner.DidCreateWebView(this);
        initializing = Initialize(owner);
        return initializing;
    }

    async Task Initialize(BrowserModel owner)
    {
        var store = owner.Store;
        var environment = store.Engine.Environment;
        var options = store.Engine.Options(owner);
        if (environment is null || options is null || WebView is null) { Fail(store.Engine.Failure ?? "WebView2"); return; }
        try { await WebView.EnsureCoreWebView2Async(environment, options); }
        catch (Exception e) { Fail(e.Message); return; }
        if (WebView is null) return;
        try
        {
        var core = WebView.CoreWebView2;
        Core = core;
        if (!owner.PrivateMode && store.Engine.NormalProfile is null) { store.Engine.NormalProfile = core.Profile; _ = store.Extensions.SyncAsync(core.Profile); }
        var settings = core.Settings;
        settings.AreDevToolsEnabled = Program.Has("--diagnostics");
        settings.IsStatusBarEnabled = false;
        settings.IsPasswordAutosaveEnabled = false;
        settings.IsGeneralAutofillEnabled = false;
        settings.IsBuiltInErrorPageEnabled = false;
        settings.IsSwipeNavigationEnabled = true;
        settings.AreDefaultScriptDialogsEnabled = false;
        // mica handles find, print, reload and zoom keys itself so they work the same everywhere in the window.
        settings.AreBrowserAcceleratorKeysEnabled = false;
        settings.IsReputationCheckingRequired = true;
        core.Profile.PreferredTrackingPreventionLevel = CoreWebView2TrackingPreventionLevel.Balanced;
        core.NavigationStarting += OnNavigationStarting;
        core.FrameNavigationStarting += (_, e) => { if (Uri.TryCreate(e.Uri, UriKind.Absolute, out var frame) && frame.IsFile) e.Cancel = true; };
        core.ContentLoading += (_, _) => { Progress = 0.45; Notify(); };
        core.DOMContentLoaded += (_, _) => { Progress = 0.75; Notify(); };
        core.NavigationCompleted += OnNavigationCompleted;
        core.SourceChanged += (_, _) => { fileHistoryNavigation = false; if (Core is { } c && c.Source.Length > 0 && c.Source != "about:blank") Url = c.Source; Notify(); Owner?.Store.ScheduleSession(); };
        core.DocumentTitleChanged += (_, _) => { Title = Core?.DocumentTitle ?? Title; Notify(); Owner?.Store.ScheduleSession(); };
        core.HistoryChanged += (_, _) => { CanBack = Core?.CanGoBack ?? false; CanForward = Core?.CanGoForward ?? false; Notify(); };
        core.NewWindowRequested += OnNewWindowRequested;
        core.WindowCloseRequested += (_, _) => Owner?.Close(this);
        core.PermissionRequested += (_, e) => Permissions.Handle(this, e);
        core.DownloadStarting += (_, e) => Owner?.Downloads.Start(this, e);
        core.ScriptDialogOpening += OnScriptDialog;
        core.BasicAuthenticationRequested += OnBasicAuthentication;
        core.ServerCertificateErrorDetected += (_, e) => e.Action = CoreWebView2ServerCertificateErrorAction.Cancel;
        core.LaunchingExternalUriScheme += OnExternalScheme;
        core.ProcessFailed += OnProcessFailed;
        core.ContainsFullScreenElementChanged += (_, _) => Owner?.Window?.SetFullScreen(Core?.ContainsFullScreenElement == true);
        core.NotificationReceived += (_, e) => Notifications.Notifier.Shared.Show(this, e);
        core.WebResourceRequested += OnResourceRequested;
        core.WebMessageReceived += (_, e) => passwords.Received(e);
        core.FaviconChanged += OnFaviconChanged;
        ApplyBlocking();
        if (!owner.PrivateMode) await passwords.InstallAsync(core);
        if (pendingUrl is { } url) { pendingUrl = null; core.Navigate(url); }
        Notify();
        }
        catch (Exception e) { Diagnostics.Log.Error(e); Fail(Program.QA ? e.ToString() : e.Message); }
    }

    void Fail(string message)
    {
        Phase = TabPhase.Terminated; Loading = false;
        Error = message;
        Notify();
    }

    public void EnsureLoaded()
    {
        if (Phase is TabPhase.Live or TabPhase.Terminated || Url is null) return;
        if (AddressParser.OpenableFile(Url)) OpenFile(Url); else Load(Url);
    }

    public void Load(string url)
    {
        if (!AddressParser.Navigable(url)) return;
        pendingFile = null;
        Error = null; Failure = null; Secure = false; Phase = TabPhase.Live;
        Url = url;
        if (Core is { } core) core.Navigate(url); else { pendingUrl = url; _ = MakeWebView(); }
        Notify();
        Owner?.Store.ScheduleSession();
    }

    /// <summary>Only application activation or a restored tab calls this; address input and page links use Load.</summary>
    public void OpenFile(string url)
    {
        if (!AddressParser.OpenableFile(url)) return;
        var uri = new Uri(url);
        Url = url; Phase = TabPhase.Live; Secure = false; Failure = null;
        if (!File.Exists(uri.LocalPath))
        {
            Error = Owner?.Text("файл не найден или mica больше не может его прочитать. откройте его снова из Проводника.", "Файл не найден или mica больше не может его прочитать. Откройте его снова из Проводника.");
            Loading = false; Notify(); Owner?.Store.ScheduleSession(); return;
        }
        Error = null;
        openedFiles.Add(uri.LocalPath);
        pendingFile = uri.LocalPath;
        if (Core is { } core) core.Navigate(url); else { pendingUrl = url; _ = MakeWebView(); }
        Notify(); Owner?.Store.ScheduleSession();
    }

    public void Reload()
    {
        if (Phase == TabPhase.Terminated || Core is null) { if (Url is { } url) { if (Phase == TabPhase.Terminated) Recreate(); if (AddressParser.OpenableFile(url)) OpenFile(url); else Load(url); } return; }
        if (AddressParser.OpenableFile(Url)) { OpenFile(Url!); return; }
        Error = null; Core.Reload(); Notify();
    }

    /// <summary>Ctrl+Shift+R: the page and its resources again from the network. WebView2 has no direct call for a
    /// reload that skips the cache, so it goes through the DevTools protocol method Page.reload.</summary>
    public void ReloadFromOrigin()
    {
        if (Phase == TabPhase.Terminated || Core is null || AddressParser.OpenableFile(Url)) { Reload(); return; }
        Error = null; _ = Core.CallDevToolsProtocolMethodAsync("Page.reload", "{\"ignoreCache\":true}"); Notify();
    }

    /// <summary>After the page process ended, a fresh WebView2 replaces the dead one; nothing reloads by itself.</summary>
    void Recreate()
    {
        var old = WebView;
        DisposeWebView();
        if (old is not null) Owner?.DidCreateWebView(this);
        Phase = TabPhase.Fresh;
    }

    public void Stop() { Core?.Stop(); Loading = false; Notify(); }
    public void GoBack() { if (Core?.CanGoBack == true) { Error = null; fileHistoryNavigation = true; Core.GoBack(); } }
    public void GoForward() { if (Core?.CanGoForward == true) { Error = null; fileHistoryNavigation = true; Core.GoForward(); } }

    public void SetVisible(bool visible) { if (WebView is not null) WebView.Visibility = visible ? Visibility.Visible : Visibility.Collapsed; }

    /// <summary>The WinUI WebView2 has no zoom factor, so page zoom is CSS zoom on the document, re-applied after
    /// each navigation. Ctrl+wheel and pinch still use Chromium's own zoom.</summary>
    public void SetZoom(double zoom)
    {
        Zoom = Math.Round(zoom, 2);
        _ = Core?.ExecuteScriptAsync($"document.documentElement.style.zoom = '{Zoom.ToString(System.Globalization.CultureInfo.InvariantCulture)}'");
        Notify();
    }

    public void ApplyBlocking()
    {
        if (Core is null) return;
        var enabled = Owner?.Store.Preferences.Blocking == true;
        if (enabled == blockingFilterInstalled) return;
        if (enabled) Core.AddWebResourceRequestedFilter("*", CoreWebView2WebResourceContext.All, CoreWebView2WebResourceRequestSourceKinds.All);
        else Core.RemoveWebResourceRequestedFilter("*", CoreWebView2WebResourceContext.All, CoreWebView2WebResourceRequestSourceKinds.All);
        blockingFilterInstalled = enabled;
    }

    void OnResourceRequested(CoreWebView2 sender, CoreWebView2WebResourceRequestedEventArgs e)
    {
        var store = Owner?.Store;
        if (store is null || e.ResourceContext == CoreWebView2WebResourceContext.Document) return;
        if (store.Blocker.ShouldBlock(e.Request.Uri, sender.Source))
        {
            e.Response = store.Engine.Environment?.CreateWebResourceResponse(null, 403, "Blocked by mica", "");
            if (e.Response is not null) BlockedRequestCount++;
        }
    }

    void OnNavigationStarting(CoreWebView2 sender, CoreWebView2NavigationStartingEventArgs e)
    {
        bool history = fileHistoryNavigation && e.NavigationKind == CoreWebView2NavigationKind.BackOrForward; fileHistoryNavigation = false;
        if (Uri.TryCreate(e.Uri, UriKind.Absolute, out var uri) && uri.IsFile)
        {
            var path = uri.LocalPath;
            bool initiated = pendingFile is not null && string.Equals(pendingFile, path, StringComparison.OrdinalIgnoreCase);
            pendingFile = null;
            bool sameFile = Uri.TryCreate(sender.Source, UriKind.Absolute, out var current) && current.IsFile && string.Equals(current.LocalPath, path, StringComparison.OrdinalIgnoreCase);
            if (!AddressParser.OpenableFile(e.Uri) || !openedFiles.Contains(path) || !(initiated || history || sameFile)) { e.Cancel = true; return; }
        }
        else if (!AddressParser.Navigable(e.Uri) && !e.Uri.StartsWith("data:", StringComparison.Ordinal))
        {
            pendingFile = null;
            e.Cancel = true;
            return;
        }
        else pendingFile = null;
        Loading = true; Progress = 0.1; Secure = false; Error = null; Failure = null;
        Url = e.Uri;
        Notify();
    }

    void OnNavigationCompleted(CoreWebView2 sender, CoreWebView2NavigationCompletedEventArgs e)
    {
        Loading = false; Progress = 1;
        CanBack = sender.CanGoBack; CanForward = sender.CanGoForward;
        if (e.IsSuccess)
        {
            // Certificate errors are never bypassed, so a finished HTTPS page passed the system's TLS checks.
            Secure = sender.Source.StartsWith("https://", StringComparison.Ordinal);
            Owner?.Store.Record(this);
            if (Zoom != 1) SetZoom(Zoom);
        }
        else if (e.WebErrorStatus != CoreWebView2WebErrorStatus.OperationCanceled && e.WebErrorStatus != CoreWebView2WebErrorStatus.ValidAuthenticationCredentialsRequired)
        {
            Failure = e.WebErrorStatus;
            Error = ErrorText(e.WebErrorStatus, e.HttpStatusCode);
            Secure = false;
        }
        Owner?.Store.ScheduleSession();
        Notify();
    }

    /// <summary>WebView2 picks the page's icon itself and reports every change; mica keeps it for this tab and copies it as
    /// PNG into the window's icon store, keyed by host and port.</summary>
    async void OnFaviconChanged(CoreWebView2 sender, object args)
    {
        var page = sender.Source;
        if (string.IsNullOrEmpty(sender.FaviconUri) || !(page.StartsWith("https://", StringComparison.OrdinalIgnoreCase) || page.StartsWith("http://", StringComparison.OrdinalIgnoreCase))) return;
        var store = Owner?.Favicons;
        if (store is null) return;
        try
        {
            using var stream = await sender.GetFaviconAsync(CoreWebView2FaviconImageFormat.Png);
            if (stream is null || stream.Size == 0 || stream.Size > Favicons.ByteLimit) return;
            var bytes = new byte[stream.Size];
            using (var reader = new Windows.Storage.Streams.DataReader(stream.GetInputStreamAt(0)))
            {
                await reader.LoadAsync((uint)stream.Size);
                reader.ReadBytes(bytes);
            }
            if (await store.SetAsync(page, bytes) is { } image && sender.Source == page)
            {
                pageFavicon = image; pageFaviconKey = Favicons.Key(page);
                Notify();
            }
        }
        catch (Exception e) { Diagnostics.Log.Error(e); }
    }

    public bool CertificateFailure => Failure is CoreWebView2WebErrorStatus.CertificateCommonNameIsIncorrect or CoreWebView2WebErrorStatus.CertificateExpired
        or CoreWebView2WebErrorStatus.ClientCertificateContainsErrors or CoreWebView2WebErrorStatus.CertificateRevoked or CoreWebView2WebErrorStatus.CertificateIsInvalid;

    string ErrorText(CoreWebView2WebErrorStatus status, int http)
    {
        var store = Owner!.Store;
        return status switch
        {
            CoreWebView2WebErrorStatus.HostNameNotResolved => store.Text("сервер не найден. проверьте адрес и подключение к интернету.", "Сервер не найден. Проверьте адрес и подключение к интернету."),
            CoreWebView2WebErrorStatus.CannotConnect or CoreWebView2WebErrorStatus.ConnectionAborted or CoreWebView2WebErrorStatus.ConnectionReset => store.Text("не удалось подключиться к серверу.", "Не удалось подключиться к серверу."),
            CoreWebView2WebErrorStatus.Disconnected => store.Text("нет подключения к интернету.", "Нет подключения к интернету."),
            CoreWebView2WebErrorStatus.Timeout => store.Text("сервер слишком долго не отвечает.", "Сервер слишком долго не отвечает."),
            CoreWebView2WebErrorStatus.CertificateCommonNameIsIncorrect or CoreWebView2WebErrorStatus.CertificateExpired or CoreWebView2WebErrorStatus.ClientCertificateContainsErrors
                or CoreWebView2WebErrorStatus.CertificateRevoked or CoreWebView2WebErrorStatus.CertificateIsInvalid => store.Text("сертификат сайта не прошёл проверку Windows. соединение остановлено, обход не предусмотрен.", "Сертификат сайта не прошёл проверку Windows. Соединение остановлено, обход не предусмотрен."),
            CoreWebView2WebErrorStatus.RedirectFailed => store.Text("слишком много перенаправлений.", "Слишком много перенаправлений."),
            CoreWebView2WebErrorStatus.ServerUnreachable => store.Text("сервер недоступен.", "Сервер недоступен."),
            _ => store.Text("страницу не удалось загрузить. код: ", "Страницу не удалось загрузить. Код: ") + status + (http > 0 ? " " + http : ""),
        };
    }

    [LibraryImport("user32.dll")] private static partial short GetAsyncKeyState(int key);
    static bool KeyDown(int key) => (GetAsyncKeyState(key) & 0x8000) != 0;

    async void OnNewWindowRequested(CoreWebView2 sender, CoreWebView2NewWindowRequestedEventArgs e)
    {
        var owner = Owner;
        if (owner is null) return;
        if (Uri.TryCreate(e.Uri, UriKind.Absolute, out var destination) && destination.IsFile) { e.Handled = true; return; }
        // Ctrl+click opens in the background, Ctrl+Shift+click in front, as Command-click does on macOS.
        bool ctrl = KeyDown(0x11), shift = KeyDown(0x10);
        var deferral = e.GetDeferral();
        try
        {
            var tab = owner.Add(new SavedTab(), activate: !(ctrl && !shift) || !e.IsUserInitiated);
            tab.Phase = TabPhase.Live; tab.Url = e.Uri;
            await tab.MakeWebView();
            if (tab.Core is { } core) { e.NewWindow = core; e.Handled = true; }
        }
        finally { deferral.Complete(); }
    }

    async void OnScriptDialog(CoreWebView2 sender, CoreWebView2ScriptDialogOpeningEventArgs e)
    {
        var owner = Owner;
        if (owner is null) return;
        var deferral = e.GetDeferral();
        try
        {
            var title = Origin.Of(e.Uri) ?? "mica";
            switch (e.Kind)
            {
                case CoreWebView2ScriptDialogKind.Alert:
                    await Dialogs.Ask(owner.Window, title, e.Message, ["OK"]); e.Accept(); break;
                case CoreWebView2ScriptDialogKind.Confirm:
                case CoreWebView2ScriptDialogKind.Beforeunload:
                    if (await Dialogs.Ask(owner.Window, title, e.Kind == CoreWebView2ScriptDialogKind.Beforeunload ? owner.Text("покинуть страницу? несохранённые изменения могут потеряться.", "Покинуть страницу? Несохранённые изменения могут потеряться.") : e.Message, [owner.Text("отмена", "Отмена"), "OK"]) == 1) e.Accept();
                    break;
                case CoreWebView2ScriptDialogKind.Prompt:
                    if (await Dialogs.Prompt(owner.Window, title, e.Message, e.DefaultText) is { } text) { e.ResultText = text; e.Accept(); }
                    break;
            }
        }
        finally { deferral.Complete(); }
    }

    async void OnBasicAuthentication(CoreWebView2 sender, CoreWebView2BasicAuthenticationRequestedEventArgs e)
    {
        var owner = Owner;
        if (owner is null) { e.Cancel = true; return; }
        var deferral = e.GetDeferral();
        try
        {
            var credentials = await Dialogs.Credentials(owner.Window, owner.Text("вход на сайт", "Вход на сайт"), AddressParser.Host(e.Uri) ?? e.Uri, owner.Text("имя пользователя", "Имя пользователя"), owner.Text("пароль", "Пароль"), owner.Text("войти", "Войти"), owner.Text("отмена", "Отмена"));
            if (credentials is { } c) { e.Response.UserName = c.User; e.Response.Password = c.Password; } else e.Cancel = true;
        }
        finally { deferral.Complete(); }
    }

    async void OnExternalScheme(CoreWebView2 sender, CoreWebView2LaunchingExternalUriSchemeEventArgs e)
    {
        e.Cancel = true;
        if (Owner is { } owner && e.IsUserInitiated) await owner.ExternalAsync(e.Uri);
    }

    void OnProcessFailed(CoreWebView2 sender, CoreWebView2ProcessFailedEventArgs e)
    {
        if (e.ProcessFailedKind is CoreWebView2ProcessFailedKind.RenderProcessExited or CoreWebView2ProcessFailedKind.BrowserProcessExited or CoreWebView2ProcessFailedKind.RenderProcessUnresponsive)
        {
            Phase = TabPhase.Terminated; Loading = false;
            Error = Owner?.Text("процесс страницы завершён системой. восстановите страницу; несохранённые формы могут быть потеряны.", "Процесс страницы завершён системой. Восстановите страницу; несохранённые формы могут быть потеряны.");
            Notify();
        }
    }

    public void Print() => Core?.ShowPrintUI(CoreWebView2PrintDialogKind.Browser);

    public async Task<string?> EvaluateAsync(string script) => Core is null ? null : await Core.ExecuteScriptAsync(script);

    void DisposeWebView()
    {
        var view = WebView;
        WebView = null; Core = null; initializing = null; blockingFilterInstalled = false;
        if (view is null) return;
        if (view.Parent is Panel parent) parent.Children.Remove(view);
        view.Close();
    }

    public void Dispose()
    {
        Notifications.Notifier.Shared.RemoveFor(this);
        DisposeWebView();
        Owner = null;
    }

    public static string Json(string value) => JsonSerializer.Serialize(value, MicaJson.Info<string>());
}

/// <summary>Site icons keyed by host without "www." plus a non-default port, so apps on different ports of localhost keep
/// their own (macOS Favicons). The normal profile keeps a PNG per key in
/// %LOCALAPPDATA%\mica\Favicons and reads it lazily for restored tabs; incognito windows own a separate instance
/// that stays in memory.</summary>
public sealed class Favicons
{
    public const int ByteLimit = 1_000_000;
    readonly string? directory;
    readonly Dictionary<string, ImageSource> icons = [];
    readonly HashSet<string> probed = [];
    int generation;
    /// <summary>Raised after an icon arrives or the store is cleared, never while a caller is rendering.</summary>
    public event Action? Changed;

    public Favicons(string? directory) { this.directory = directory; }

    /// <summary>"example.com" for https://www.example.com/, "localhost:8501" for http://localhost:8501/app.</summary>
    public static string? Key(string? url)
    {
        if (!Uri.TryCreate(url, UriKind.Absolute, out var uri) || uri.Host.Length == 0) return null;
        var key = uri.Host.ToLowerInvariant();
        if (key.StartsWith("www.", StringComparison.Ordinal)) key = key[4..];
        if (key.Length == 0) return null;
        return uri.IsDefaultPort ? key : key + ":" + uri.Port;
    }

    /// <summary>The stored icon of the page's origin. Safe to call while rendering: a missing icon schedules a disk read
    /// and raises Changed later.</summary>
    public ImageSource? Image(string? url)
    {
        if (Key(url) is not { } key) return null;
        if (icons.TryGetValue(key, out var image)) return image;
        if (File(key) is { } file && probed.Add(key)) _ = LoadAsync(key, file, generation);
        return null;
    }

    async Task LoadAsync(string key, string file, int expected)
    {
        try
        {
            var bytes = await Task.Run(() => System.IO.File.Exists(file) ? System.IO.File.ReadAllBytes(file) : null);
            if (bytes is null || expected != generation || icons.ContainsKey(key)) return;
            icons[key] = await Decode(bytes);
            Changed?.Invoke();
        }
        catch { }
    }

    public async Task<ImageSource?> SetAsync(string? url, byte[] png)
    {
        if (Key(url) is not { } key) return null;
        var expected = generation;
        var image = await Decode(png);
        if (expected != generation) return null;
        icons[key] = image; probed.Add(key);
        Changed?.Invoke();
        if (File(key) is { } file && directory is { } folder)
            await Task.Run(() => { try { Directory.CreateDirectory(folder); System.IO.File.WriteAllBytes(file, png); } catch { } });
        return image;
    }

    /// <summary>Clearing history or cache forgets every icon, in memory and on disk.</summary>
    public void Clear()
    {
        generation++;
        icons.Clear(); probed.Clear();
        if (directory is not null) try { Directory.Delete(directory, true); } catch { }
        Changed?.Invoke();
    }

    string? File(string key)
    {
        if (directory is null) return null;
        var name = new string(key.Select(c => (c is (>= 'a' and <= 'z') or (>= '0' and <= '9') or '.' or '-') ? c : '_').Take(200).ToArray());
        return Path.Combine(directory, name + ".png");
    }

    static async Task<ImageSource> Decode(byte[] bytes)
    {
        var memory = new Windows.Storage.Streams.InMemoryRandomAccessStream();
        using (var writer = new Windows.Storage.Streams.DataWriter(memory.GetOutputStreamAt(0)))
        {
            writer.WriteBytes(bytes); await writer.StoreAsync(); writer.DetachStream();
        }
        memory.Seek(0);
        var image = new BitmapImage();
        await image.SetSourceAsync(memory);
        return image;
    }
}
