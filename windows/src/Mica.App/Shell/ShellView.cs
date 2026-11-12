using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.Web.WebView2.Core;
using Mica.Core;

namespace Mica.App;

/// <summary>The window's interface: mica's shell (windows/shell, the same layout, springs and transitions as the SwiftUI
/// views on macOS) running in its own WebView2 over the window backdrop. The shell receives the window state as JSON
/// and sends commands back; it never touches the network. Its files come from the app folder through a virtual host,
/// site icons, app icons and extension icons through https://mica.icons, answered here from memory and the extension folders.</summary>
public sealed partial class ShellView : Grid
{
    public const string Host = "mica.shell";
    readonly BrowserModel browser;
    readonly BrowserWindow window;
    readonly WebView2 view = new();
    CoreWebView2? core;
    bool ready, scheduled;
    readonly int seed = Random.Shared.Next(1000);
    string? librarySent, settingsSent;
    public event Action<JsonElement>? LayoutReported;
    public event Action? Ready;

    public ShellView(BrowserModel browser, BrowserWindow window)
    {
        this.browser = browser; this.window = window;
        // Transparent: the shell paints its own tint over the acrylic, and the site page shows through its hole.
        view.DefaultBackgroundColor = Microsoft.UI.Colors.Transparent;
        Children.Add(view);
        Observable.Touched += Schedule;
        var store = browser.Store;
        store.PreferencesUpdated += Schedule; store.ProfilesChanged += Schedule; store.BookmarksChanged += Schedule;
        store.HistoryChanged += Schedule; store.PermissionsChanged += Schedule; store.DownloadsChanged += Schedule;
        store.Extensions.Changed += Schedule; store.Importer.Changed += Schedule; store.Passwords.Changed += Schedule; store.Blocker.Changed += Schedule; store.UBlock.Changed += Schedule;
        browser.Favicons.Changed += Schedule;
        if (!browser.PrivateMode) store.Favicons.Changed += Schedule;
        browser.FocusAddressRequested += () => Event("focusAddress");
        browser.MenuRequested += () => Event("menu");
        browser.SaveMenuRequested += () => Event("saveMenu");
        browser.FindStepRequested += back => _ = ShellCommands.Run(browser, "find.run", JsonDocument.Parse("{\"query\":" + Tab.Json(lastFind) + ",\"back\":" + (back ? "true" : "false") + "}").RootElement);
        _ = StartAsync();
    }

    string lastFind = "";

    public void Detach()
    {
        Observable.Touched -= Schedule;
        var store = browser.Store;
        store.PreferencesUpdated -= Schedule; store.ProfilesChanged -= Schedule; store.BookmarksChanged -= Schedule;
        store.HistoryChanged -= Schedule; store.PermissionsChanged -= Schedule; store.DownloadsChanged -= Schedule;
        store.Extensions.Changed -= Schedule; store.Importer.Changed -= Schedule; store.Passwords.Changed -= Schedule; store.Blocker.Changed -= Schedule; store.UBlock.Changed -= Schedule;
        browser.Favicons.Changed -= Schedule;
        if (!browser.PrivateMode) store.Favicons.Changed -= Schedule;
        view.Close();
    }

    public static string Folder => Path.Combine(AppContext.BaseDirectory, "shell");

    async Task StartAsync()
    {
        var store = browser.Store;
        if (store.Engine.Environment is not { } environment) { window.ShellFailed(store.Engine.Failure ?? "WebView2"); return; }
        try
        {
            // The shell keeps its own profile: nothing of it mixes with sites, and it has no cookies or storage to clear.
            var options = environment.CreateCoreWebView2ControllerOptions();
            options.ProfileName = "mica-shell";
            options.IsInPrivateModeEnabled = true;
            await view.EnsureCoreWebView2Async(environment, options);
        }
        catch (Exception e) { Diagnostics.Log.Error(e); window.ShellFailed(e.Message); return; }
        core = view.CoreWebView2;
        var settings = core.Settings;
        settings.AreDevToolsEnabled = Program.Has("--diagnostics");
        settings.AreDefaultContextMenusEnabled = false;
        settings.AreDefaultScriptDialogsEnabled = false;
        settings.IsStatusBarEnabled = false;
        settings.IsZoomControlEnabled = false;
        settings.IsPinchZoomEnabled = false;
        settings.IsSwipeNavigationEnabled = false;
        settings.IsGeneralAutofillEnabled = false;
        settings.IsPasswordAutosaveEnabled = false;
        settings.AreBrowserAcceleratorKeysEnabled = false;
        settings.IsBuiltInErrorPageEnabled = false;
        core.SetVirtualHostNameToFolderMapping(Host, Folder, CoreWebView2HostResourceAccessKind.DenyCors);
        core.AddWebResourceRequestedFilter("https://mica.icons/*", CoreWebView2WebResourceContext.Image);
        core.WebResourceRequested += OnResourceRequested;
        // The shell is mica's own page: it never navigates away and opens no windows.
        core.NavigationStarting += (_, e) => { if (!e.Uri.StartsWith("https://" + Host + "/", StringComparison.Ordinal)) e.Cancel = true; };
        core.NewWindowRequested += (_, e) => e.Handled = true;
        core.WebMessageReceived += OnMessage;
        core.ProcessFailed += (_, e) => { ready = false; Diagnostics.Log.Error(new InvalidOperationException("shell process failed: " + e.ProcessFailedKind)); core?.Reload(); };
        core.Navigate("https://" + Host + "/index.html");
    }

    void OnResourceRequested(CoreWebView2 sender, CoreWebView2WebResourceRequestedEventArgs e)
    {
        if (!Uri.TryCreate(e.Request.Uri, UriKind.Absolute, out var uri) || uri.Host != "mica.icons") return;
        byte[]? png = null;
        var path = Uri.UnescapeDataString(uri.AbsolutePath.TrimStart('/'));
        if (path.StartsWith("app/", StringComparison.Ordinal))
        {
            if (Appearance.AppIcons.Png(path[4..]) is { } file) png = File.ReadAllBytes(file);
        }
        else if (path.StartsWith("ext/", StringComparison.Ordinal))
        {
            var record = browser.Store.Extensions.Records.FirstOrDefault(r => r.Id.ToString("N") == path[4..]);
            if (record is not null && browser.Store.Extensions.IconPath(record) is { } file) png = File.ReadAllBytes(file);
        }
        else png = browser.Favicons.IconFor(path)?.Png;
        var environment = browser.Store.Engine.Environment;
        if (environment is null) return;
        if (png is null) { e.Response = environment.CreateWebResourceResponse(null, 404, "Not Found", ""); return; }
        var stream = new MemoryStream(png).AsRandomAccessStream();
        e.Response = environment.CreateWebResourceResponse(stream, 200, "OK", "Content-Type: image/png\r\nCache-Control: max-age=31536000");
    }

    async void OnMessage(CoreWebView2 sender, CoreWebView2WebMessageReceivedEventArgs e)
    {
        // Only mica's own page may talk to the window.
        if (!e.Source.StartsWith("https://" + Host + "/", StringComparison.Ordinal)) return;
        try
        {
            using var document = JsonDocument.Parse(e.WebMessageAsJson);
            var root = document.RootElement;
            var name = root.TryGetProperty("name", out var n) ? n.GetString() ?? "" : "";
            var args = root.TryGetProperty("args", out var a) ? a.Clone() : default;
            switch (name)
            {
                case "shell.hello": ready = true; librarySent = null; settingsSent = null; Push(); return;
                case "shell.ready": Ready?.Invoke(); return;
                case "layout": LayoutReported?.Invoke(args); return;
                case "find.run": lastFind = args.TryGetProperty("query", out var q) ? q.GetString() ?? "" : ""; break;
            }
            var reply = await ShellCommands.Run(browser, name, args);
            if (root.TryGetProperty("id", out var id) && id.ValueKind == JsonValueKind.Number)
                Post(new JsonObject { ["type"] = "reply", ["id"] = id.GetInt32(), ["result"] = reply });
            Schedule();
        }
        catch (Exception ex) { Diagnostics.Log.Error(ex); }
    }

    /// <summary>Coalesces every change of a frame into one snapshot.</summary>
    public void Schedule()
    {
        if (scheduled || !ready) return;
        scheduled = true;
        DispatcherQueue.TryEnqueue(Microsoft.UI.Dispatching.DispatcherQueuePriority.Low, () => { scheduled = false; Push(); });
    }

    void Push()
    {
        if (!ready || core is null || browser.Window is null) return;
        var look = ShellState.LookOf(browser);
        var library = ShellState.Library(browser, look);
        var libraryText = library.ToJsonString();
        var open = browser.ShowSettings || browser.ShowOnboarding;
        var settings = open ? ShellState.Settings(browser, look) : null;
        var settingsText = settings?.ToJsonString();
        var state = ShellState.Build(browser, window, look, seed,
            libraryText == librarySent ? null : library,
            settingsText is null || settingsText == settingsSent ? null : settings);
        librarySent = libraryText;
        if (settingsText is not null) settingsSent = settingsText;
        window.ApplyLook(look);
        Post(new JsonObject { ["type"] = "state", ["state"] = state });
    }

    public void Event(string name, JsonObject? args = null) => Post(new JsonObject { ["type"] = "event", ["name"] = name, ["args"] = args ?? new JsonObject() });

    void Post(JsonObject message)
    {
        if (core is null) return;
        try { core.PostWebMessageAsJson(message.ToJsonString()); }
        catch (Exception e) when (e is InvalidOperationException or System.Runtime.InteropServices.COMException) { }
    }

    public void FocusShell() => view.Focus(FocusState.Programmatic);
    public bool HasFocus => view.FocusState != FocusState.Unfocused;
}
