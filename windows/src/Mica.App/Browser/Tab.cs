using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.WindowsRuntime;
using System.Text.Json;
using System.Text.Json.Nodes;
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
    string? filterScriptId;
    readonly SemaphoreSlim filterScripts = new(1);
    public async Task RefreshUBlockAsync()
    {
        await filterScripts.WaitAsync();
        try
        {
            if (Core is not { } core || Owner is not { } owner) return;
            ApplyBlocking();
            var script = owner.Store.Preferences.Blocking ? owner.Store.UBlock.Script : "";
            var next = script.Length == 0 ? null : await core.AddScriptToExecuteOnDocumentCreatedAsync(script);
            if (Core != core) return;
            if (filterScriptId is { } previous) core.RemoveScriptToExecuteOnDocumentCreated(previous);
            filterScriptId = next;
        }
        catch (Exception e) { Diagnostics.Log.Error(e); }
        finally { filterScripts.Release(); }
    }
    internal int BlockedRequestCount { get; private set; }
    readonly Passwords.PasswordBridge passwords;
    /// <summary>The password offer beside a field of this tab's page; the shell sends the choices here.</summary>
    public Passwords.PasswordBridge PasswordOffers => passwords;

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
        // DevTools come with the browser, as in Edge and Chrome: "Inspect" in the page context menu, F12 and the menu.
        settings.AreDevToolsEnabled = true;
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
        core.FrameNavigationStarting += (_, e) =>
        {
            // srcdoc is a child document used by challenges and editors, not an external protocol.
            if (AddressParser.Navigable(e.Uri, mainFrame: false)) return;
            if (Uri.TryCreate(e.Uri, UriKind.Absolute, out var frame) && frame.IsFile) e.Cancel = true;
        };
        core.ContentLoading += (_, _) => { passwords.Leave(); Progress = 0.45; Notify(); };
        core.DOMContentLoaded += (_, _) => { Progress = 0.75; Notify(); };
        core.NavigationCompleted += OnNavigationCompleted;
        core.SourceChanged += (_, _) => { fileHistoryNavigation = false; if (Core is { } c && c.Source.Length > 0 && c.Source != "about:blank") Url = c.Source; Notify(); Owner?.Store.ScheduleSession(); };
        core.DocumentTitleChanged += (_, _) => { Title = Core?.DocumentTitle ?? Title; Notify(); Owner?.Store.ScheduleSession(); };
        core.HistoryChanged += (_, _) => { CanBack = Core?.CanGoBack ?? false; CanForward = Core?.CanGoForward ?? false; Notify(); };
        core.NewWindowRequested += OnNewWindowRequested;
        core.ContextMenuRequested += OnContextMenuRequested;
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
        await RefreshUBlockAsync();
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

    int filterNavigation;
    public void Load(string url)
    {
        var navigation = ++filterNavigation;
        if (Owner is { } waitingOwner && waitingOwner.Store.Preferences.Blocking && !waitingOwner.Store.UBlock.Prepared) {
            Url = url;
            _ = WaitForFilters();
            async Task WaitForFilters() {
                while (Owner is { } owner && !owner.Store.UBlock.Prepared && navigation == filterNavigation) await Task.Delay(50);
                if (Owner != null && navigation == filterNavigation && Url == url) Load(url);
            }
            return;
        }
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
        if (store is null || !store.Preferences.Blocking) return;
        var type = e.ResourceContext switch {
            CoreWebView2WebResourceContext.Document => "document", CoreWebView2WebResourceContext.Script => "script",
            CoreWebView2WebResourceContext.Image => "image", CoreWebView2WebResourceContext.Stylesheet => "style-sheet",
            CoreWebView2WebResourceContext.Font => "font", CoreWebView2WebResourceContext.Media => "media",
            CoreWebView2WebResourceContext.XmlHttpRequest or CoreWebView2WebResourceContext.Fetch => "fetch",
            CoreWebView2WebResourceContext.Websocket => "websocket", CoreWebView2WebResourceContext.Ping => "ping", _ => "other"
        };
        var top = Url ?? sender.Source;
        var mainFrame = type == "document" && e.Request.Uri.Split('#')[0] == top.Split('#')[0];
        var block = store.UBlock.Rules?.ShouldBlock(e.Request.Uri, top, type, mainFrame, store.Preferences.BlockingExceptions)
            ?? (type != "document" && store.Blocker.ShouldBlock(e.Request.Uri, top));
        if (block)
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

    /// <summary>WebView2 picks the page's icon itself and reports every change; mica copies it as PNG into the window's icon
    /// store, keyed by host and port, unless the store already holds a larger one (Favicons.SetFromTabAsync).</summary>
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
            if (await store.SetFromTabAsync(page, bytes) && sender.Source == page) Notify();
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
                    await Dialogs.Ask(owner.Window, title, e.Message, [owner.Text("понятно", "Понятно")], site: e.Uri); e.Accept(); break;
                case CoreWebView2ScriptDialogKind.Confirm:
                case CoreWebView2ScriptDialogKind.Beforeunload:
                    if (await Dialogs.Ask(owner.Window, title, e.Kind == CoreWebView2ScriptDialogKind.Beforeunload ? owner.Text("покинуть страницу? несохранённые изменения могут потеряться.", "Покинуть страницу? Несохранённые изменения могут потеряться.") : e.Message, [owner.Text("отмена", "Отмена"), owner.Text("ок", "ОК")], site: e.Uri) == 1) e.Accept();
                    break;
                case CoreWebView2ScriptDialogKind.Prompt:
                    if (await Dialogs.Prompt(owner.Window, title, e.Message, e.DefaultText, e.Uri) is { } text) { e.ResultText = text; e.Accept(); }
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
        if (Owner is { } owner && e.IsUserInitiated) await owner.ExternalAsync(e.Uri, Origin.Of(e.InitiatingOrigin));
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

    /// <summary>The page context menu, drawn by the shell as a mica menu (PageMenu.swift on macOS). WebView2 still builds
    /// the items for what was clicked; a chosen row runs the WebView2 item by its command id. "Save as" and the page
    /// source are left out, as on macOS.</summary>
    void OnContextMenuRequested(CoreWebView2 sender, CoreWebView2ContextMenuRequestedEventArgs e)
    {
        if (Owner is not { } owner) return;
        e.Handled = true;
        var deferral = e.GetDeferral();
        var target = e.ContextMenuTarget;
        var items = PageMenuItems(e.MenuItems, owner, top: true);
        if (target.HasSelection && !string.IsNullOrWhiteSpace(target.SelectionText))
        {
            var query = target.SelectionText.Trim();
            if (query.Length > 2000) query = query[..2000];
            var engine = owner.Prefs.Search;
            items.Insert(PageMenuSearchIndex(items), new JsonObject { ["title"] = owner.Text("искать в ", "Искать в ") + engine.Title(owner.Prefs.Language), ["enabled"] = true, ["search"] = query });
        }
        owner.ShowPageMenu(items, e.Location.X, e.Location.Y, (command, search) =>
        {
            if (command is { } id) e.SelectedCommandId = id;
            deferral.Complete();
            if (search is { Length: > 0 } text) owner.Open(owner.Prefs.Search.Search(text));
        });
    }

    static JsonArray PageMenuItems(IList<CoreWebView2ContextMenuItem> source, BrowserModel owner, bool top)
    {
        var list = new JsonArray();
        foreach (var item in source)
        {
            if (item.Name is "saveAs" or "viewPageSource") continue;
            // Back and forward appear only when they lead somewhere, as on macOS.
            if (top && item.Name is "back" or "forward" && !item.IsEnabled) continue;
            if (item.Kind == CoreWebView2ContextMenuItemKind.Separator) { list.Add(new JsonObject { ["divider"] = true }); continue; }
            var entry = new JsonObject { ["name"] = item.Name, ["title"] = PageMenuTitle(item, owner), ["enabled"] = item.IsEnabled };
            if (item.Kind == CoreWebView2ContextMenuItemKind.Submenu)
            {
                var children = PageMenuItems(item.Children, owner, top: false);
                if (children.Count == 0) continue;
                entry["submenu"] = children;
            }
            else
            {
                entry["command"] = item.CommandId;
                if (item.Kind is CoreWebView2ContextMenuItemKind.CheckBox or CoreWebView2ContextMenuItemKind.Radio && item.IsChecked) entry["checked"] = true;
            }
            list.Add(entry);
        }
        return list;
    }

    /// <summary>Right after "copy" when there is one, otherwise first.</summary>
    static int PageMenuSearchIndex(JsonArray items)
    {
        for (var i = 0; i < items.Count; i++)
            if (items[i] is JsonObject o && o["name"]?.GetValue<string>() == "copy") return i + 1;
        return 0;
    }

    /// <summary>mica words the common items itself so they follow the window's language and letter case; others keep
    /// WebView2's label without its access-key ampersand.</summary>
    static string PageMenuTitle(CoreWebView2ContextMenuItem item, BrowserModel owner)
    {
        string T(string low, string regular) => owner.Text(low, regular);
        return item.Name switch
        {
            "back" => T("назад", "Назад"),
            "forward" => T("вперёд", "Вперёд"),
            "reload" => T("перезагрузить страницу", "Перезагрузить страницу"),
            "print" => T("напечатать страницу…", "Напечатать страницу…"),
            "inspect" or "inspectElement" => T("проверить элемент", "Проверить элемент"),
            "openLinkInNewWindow" => T("открыть ссылку в новой вкладке", "Открыть ссылку в новой вкладке"),
            "saveLinkAs" => T("загрузить файл по ссылке", "Загрузить файл по ссылке"),
            "copyLinkLocation" => T("скопировать ссылку", "Скопировать ссылку"),
            "copyImage" => T("скопировать изображение", "Скопировать изображение"),
            "saveImageAs" => T("загрузить изображение", "Загрузить изображение"),
            "saveMediaAs" => T("загрузить видео", "Загрузить видео"),
            "copy" => T("копировать", "Копировать"),
            "cut" => T("вырезать", "Вырезать"),
            "paste" => T("вставить", "Вставить"),
            "share" => T("поделиться…", "Поделиться…"),
            _ => System.Text.RegularExpressions.Regex.Replace(item.Label, "&(.)", "$1"),
        };
    }
    /// <summary>WebView2 opens DevTools only in a window of their own, with no API to dock them or pick a panel.</summary>
    public void OpenDevTools() => Core?.OpenDevToolsWindow();

    public async Task<string?> EvaluateAsync(string script) => Core is null ? null : await Core.ExecuteScriptAsync(script);

    void DisposeWebView()
    {
        var view = WebView;
        WebView = null; Core = null; initializing = null; blockingFilterInstalled = false; filterScriptId = null;
        if (view is null) return;
        if (view.Parent is Panel parent) parent.Children.Remove(view);
        view.Close();
    }

    public void Dispose()
    {
        Notifications.Notifier.Shared.RemoveFor(this);
        DisposeWebView();
        filterNavigation++;
        Owner = null;
    }

    public static string Json(string value) => JsonSerializer.Serialize(value, MicaJson.Info<string>());
}

/// <summary>Site icons keyed by host without "www." plus a non-default port, so apps on different ports of localhost keep
/// their own (macOS Favicons). The normal profile keeps a PNG of at most FaviconCatalog.Pixels per key in %LOCALAPPDATA%\mica\Favicons and reads it
/// lazily for restored tabs; incognito windows own a separate instance that stays in memory. The shell shows an icon
/// through https://mica.icons/&lt;key&gt;, which ShellView answers from here.</summary>
public sealed partial class Favicons
{
    public const int ByteLimit = 1_000_000;
    readonly string? directory;
    readonly Dictionary<string, Entry> icons = [];
    readonly HashSet<string> probed = [];
    readonly Dictionary<string, Task> diskReads = [];
    /// <summary>Keys shown from a copy an earlier build stored at a smaller size: it stays on screen while discovery looks
    /// for the icon at FaviconCatalog.Pixels and is replaced only when that succeeds (macOS Favicons).</summary>
    readonly HashSet<string> stale = [];
    readonly SemaphoreSlim diskIO = new(1);
    /// <summary>PNG bytes, a version that changes with them, and for a neutral one-colour glyph (FaviconTone) its luminance.</summary>
    public sealed record Entry(byte[] Png, int Version, double? Glyph);
    int generation, version;
    /// <summary>Raised after an icon arrives or the store is cleared.</summary>
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

    /// <summary>The stored icon of the page's origin. A missing icon schedules a disk read and raises Changed later.</summary>
    public Entry? Icon(string? url)
    {
        var key = Key(url);
        var icon = key is not null ? IconFor(key) : null;
        if (icon is null || (key is not null && stale.Contains(key))) Prefetch(url);
        return icon;
    }

    public Entry? IconFor(string key)
    {
        if (icons.TryGetValue(key, out var entry)) return entry;
        if (File(key) is { } file && File(key, legacy: true) is { } legacy && probed.Add(key)) diskReads[key] = LoadAsync(key, file, legacy, generation);
        return null;
    }

    /// <summary>No icon yet, or only one stored by an earlier build at a smaller size.</summary>
    bool Missing(string key) => !icons.ContainsKey(key) || stale.Contains(key);

    async Task LoadAsync(string key, string file, string legacy, int expected)
    {
        try
        {
            byte[]? bytes; var current = true;
            await diskIO.WaitAsync();
            try
            {
                bytes = await Task.Run(() => System.IO.File.Exists(file) ? System.IO.File.ReadAllBytes(file) : null);
                if (bytes is null) { current = false; bytes = await Task.Run(() => System.IO.File.Exists(legacy) ? System.IO.File.ReadAllBytes(legacy) : null); }
            }
            finally { diskIO.Release(); }
            if (bytes is null || expected != generation || icons.ContainsKey(key)) return;
            bytes = await Normalize(bytes);
            var glyph = await Measure(bytes);
            if (expected != generation || icons.ContainsKey(key)) return;
            icons[key] = new Entry(bytes, ++version, glyph);
            if (!current) stale.Add(key);
            Changed?.Invoke();
        }
        catch (Exception e) { Diagnostics.Log.Error(e); }
    }

    public async Task<bool> SetAsync(string? url, byte[] png)
    {
        if (Key(url) is not { } key) return false;
        var expected = generation;
        png = await Normalize(png);
        double? glyph = null;
        try { glyph = await Measure(png); } catch (Exception e) { Diagnostics.Log.Error(e); }
        if (expected != generation) return false;
        icons[key] = new Entry(png, ++version, glyph); probed.Add(key); stale.Remove(key);
        Changed?.Invoke();
        if (File(key) is { } file && File(key, legacy: true) is { } legacy && directory is { } folder)
        {
            await diskIO.WaitAsync();
            try
            {
                if (expected == generation)
                    await Task.Run(() => { try { Directory.CreateDirectory(folder); System.IO.File.WriteAllBytes(file, png); System.IO.File.Delete(legacy); } catch (IOException) { } catch (UnauthorizedAccessException) { } });
            }
            finally { diskIO.Release(); }
        }
        return true;
    }

    /// <summary>WebView2 hands over the icon at tab size, often 16 or 32 px. It never replaces a larger stored icon (the
    /// bundled catalog or one found by discovery); a smaller one is stored and marked stale, so discovery looks once per
    /// session for the size start page tiles need.</summary>
    public async Task<bool> SetFromTabAsync(string url, byte[] png)
    {
        if (Key(url) is not { } key) return false;
        if (diskReads.TryGetValue(key, out var read)) await read;
        var side = await Side(png);
        if (side < FaviconCatalog.Pixels && icons.TryGetValue(key, out var known) && await Side(known.Png) > side) return false;
        if (!await SetAsync(url, png)) return false;
        if (side < FaviconCatalog.Pixels) { stale.Add(key); Prefetch(url); }
        return true;
    }

    static async Task<uint> Side(byte[] png)
    {
        try
        {
            using var input = new MemoryStream(png).AsRandomAccessStream();
            var decoder = await Windows.Graphics.Imaging.BitmapDecoder.CreateAsync(input);
            return Math.Max(decoder.PixelWidth, decoder.PixelHeight);
        }
        catch { return 0; }
    }

    /// <summary>Clearing history or cache forgets every icon, in memory and on disk.</summary>
    public void Clear()
    {
        generation++;
        cancellation.Cancel(); cancellation.Dispose(); cancellation = new();
        loadingIcons.Clear(); attempted.Clear(); diskReads.Clear();
        icons.Clear(); probed.Clear(); stale.Clear();
        _ = ClearDiskAsync();
        Changed?.Invoke();
    }

    async Task ClearDiskAsync()
    {
        await diskIO.WaitAsync();
        try { if (directory is not null) await Task.Run(() => { try { Directory.Delete(directory, true); } catch (IOException) { } catch (UnauthorizedAccessException) { } }); }
        finally { diskIO.Release(); }
    }

    /// <summary>"github.com@96.png": the size is part of the name, so a copy stored at another size is never read as current.
    /// legacy is the name builds before sized icons used ("github.com.png", 64 px).</summary>
    string? File(string key, bool legacy = false)
    {
        if (directory is null) return null;
        var name = new string(key.Select(c => (c is (>= 'a' and <= 'z') or (>= '0' and <= '9') or '.' or '-') ? c : '_').Take(200).ToArray());
        return Path.Combine(directory, name + (legacy ? "" : "@" + FaviconCatalog.Pixels) + ".png");
    }

    /// <summary>Reads the icon as straight-alpha RGBA at no more than FaviconCatalog.Pixels, the form FaviconTone expects, and returns the
    /// luminance of a neutral one-colour glyph, or null for any other icon.</summary>
    static async Task<double?> Measure(byte[] bytes)
    {
        using var stream = new Windows.Storage.Streams.InMemoryRandomAccessStream();
        using (var writer = new Windows.Storage.Streams.DataWriter(stream.GetOutputStreamAt(0)))
        {
            writer.WriteBytes(bytes); await writer.StoreAsync(); writer.DetachStream();
        }
        stream.Seek(0);
        var decoder = await Windows.Graphics.Imaging.BitmapDecoder.CreateAsync(stream);
        var scale = Math.Min(1, (double)FaviconCatalog.Pixels / Math.Max(decoder.PixelWidth, decoder.PixelHeight));
        var width = (uint)Math.Max(1, Math.Round(decoder.PixelWidth * scale)); var height = (uint)Math.Max(1, Math.Round(decoder.PixelHeight * scale));
        var transform = new Windows.Graphics.Imaging.BitmapTransform { ScaledWidth = width, ScaledHeight = height, InterpolationMode = Windows.Graphics.Imaging.BitmapInterpolationMode.Fant };
        var data = await decoder.GetPixelDataAsync(Windows.Graphics.Imaging.BitmapPixelFormat.Rgba8, Windows.Graphics.Imaging.BitmapAlphaMode.Straight, transform,
            Windows.Graphics.Imaging.ExifOrientationMode.IgnoreExifOrientation, Windows.Graphics.Imaging.ColorManagementMode.DoNotColorManage);
        return FaviconTone.Glyph(data.DetachPixelData());
    }
}
