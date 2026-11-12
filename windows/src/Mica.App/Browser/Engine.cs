using Microsoft.Web.WebView2.Core;
using Mica.Core;

namespace Mica.App;

/// <summary>One WebView2 environment for the app (one browser process tree, like one WebKit networking process).
/// Normal windows share the "mica" profile; every incognito window gets its own in-private profile, so incognito
/// windows share nothing with each other or with normal windows (macOS: one .nonPersistent store per window).</summary>
public sealed partial class Engine(Store store)
{
    public CoreWebView2Environment? Environment { get; private set; }
    public CoreWebView2Profile? NormalProfile { get; set; }
    public string NormalProfileName => Program.QA ? "mica-qa" : "mica";
    public string DataFolder => Path.Combine(store.Root, "WebView2");
    public string? RuntimeVersion { get; private set; }
    public string? Failure { get; private set; }
    public event Action? BrowserProcessExited;

    public async Task StartAsync()
    {
        try { RuntimeVersion = CoreWebView2Environment.GetAvailableBrowserVersionString(); }
        catch (Exception e) { Failure = e.Message; }
        var options = new CoreWebView2EnvironmentOptions
        {
            AreBrowserExtensionsEnabled = true,
            Language = store.Preferences.Language == Language.Ru ? "ru-RU" : "en-US",
            // Media waits for a user gesture, the same rule mica applies on macOS (mediaTypesRequiringUserActionForPlayback = .all).
            AdditionalBrowserArguments = "--autoplay-policy=user-gesture-required",
        };
        try
        {
            Environment = await CoreWebView2Environment.CreateWithOptionsAsync(null, DataFolder, options);
            Environment.BrowserProcessExited += (_, _) => MicaApplication.Current?.Dispatcher.TryEnqueue(() => BrowserProcessExited?.Invoke());
        }
        catch (Exception e)
        {
            Failure = e.Message;
            store.Issue = store.Text("не удалось запустить WebView2. установите WebView2 Runtime от Microsoft и перезапустите mica: ", "Не удалось запустить WebView2. Установите WebView2 Runtime от Microsoft и перезапустите mica: ") + e.Message;
        }
    }

    public CoreWebView2ControllerOptions? Options(BrowserModel window)
    {
        if (Environment is null) return null;
        var options = Environment.CreateCoreWebView2ControllerOptions();
        options.ProfileName = window.PrivateMode ? "incognito-" + window.Id.ToString("N") : NormalProfileName;
        options.IsInPrivateModeEnabled = window.PrivateMode;
        options.ScriptLocale = store.Preferences.Language == Language.Ru ? "ru-RU" : "en-US";
        return options;
    }

    /// <summary>Clears the normal profile only; incognito profiles vanish with their windows.</summary>
    public async Task ClearAsync(CoreWebView2BrowsingDataKinds kinds, DateTime start, DateTime end)
    {
        var profile = NormalProfile;
        if (profile is null) return;
        await profile.ClearBrowsingDataAsync(kinds, start, end);
    }
}

/// <summary>Third-party domain blocking with the shared Peter Lowe list (macOS compiles it to a WebKit rule list).</summary>
public sealed partial class Blocker(Store store)
{
    public DomainBlocker? Rules { get; private set; }
    public string Status { get; private set; } = "";
    public int Count => Rules?.Count ?? 0;
    public bool Updating { get; private set; }
    public event Action? Changed;
    int generation;

    public async Task RebuildAsync()
    {
        var version = ++generation;
        try
        {
            var cached = Path.Combine(store.Root, "blocklist.txt");
            var source = File.Exists(cached) ? await File.ReadAllTextAsync(cached) : Blocklist.Bundled();
            var domains = DomainBlocker.Builtin.Concat(DomainBlocker.ParseDomains(source)).Distinct().ToList();
            var rules = new DomainBlocker(domains, store.Preferences.BlockingExceptions);
            if (version != generation) return;
            Rules = rules;
            Status = store.Text("локальные правила готовы", "Локальные правила готовы");
            foreach (var window in store.Windows) foreach (var tab in window.Model.Tabs) tab.ApplyBlocking();
        }
        catch (Exception e) when (e is IOException or FormatException)
        {
            if (version != generation) return;
            Status = e.Message;
            store.Issue = store.Text("ошибка блокировки: ", "Ошибка блокировки: ") + e.Message;
        }
        Changed?.Invoke();
    }

    public bool ShouldBlock(string request, string? top) => store.Preferences.Blocking && Rules?.ShouldBlock(request, top) == true;

    /// <summary>Manual update over HTTPS from pgl.yoyo.org, validated before it replaces the working list.</summary>
    public async Task UpdateAsync()
    {
        if (Updating || !store.Preferences.Blocking) return;
        Updating = true; Changed?.Invoke();
        try
        {
            using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(25) };
            http.DefaultRequestHeaders.UserAgent.ParseAdd("mica/" + typeof(Store).Assembly.GetName().Version);
            using var response = await http.GetAsync("https://pgl.yoyo.org/adservers/serverlist.php?hostformat=plain&showintro=0&mimetype=plaintext", HttpCompletionOption.ResponseHeadersRead);
            if (!response.IsSuccessStatusCode || response.RequestMessage?.RequestUri?.Host != "pgl.yoyo.org" || response.RequestMessage.RequestUri.Scheme != "https") throw new IOException("HTTP " + (int)response.StatusCode);
            if (response.Content.Headers.ContentLength > 2_000_000) throw new IOException("too large");
            var text = await response.Content.ReadAsStringAsync();
            if (text.Length > 2_000_000) throw new IOException("too large");
            var domains = DomainBlocker.ParseDomains(text);
            if (domains.Count < 100) throw new FormatException("list too short");
            Persistence.WriteBytes(System.Text.Encoding.UTF8.GetBytes(text), Path.Combine(store.Root, "blocklist.txt"));
            await RebuildAsync();
        }
        catch (Exception e) when (e is IOException or HttpRequestException or TaskCanceledException or FormatException)
        {
            Status = e.Message;
            store.Issue = store.Text("список не обновлён, предыдущие правила сохранены: ", "Список не обновлён, предыдущие правила сохранены: ") + e.Message;
        }
        finally { Updating = false; Changed?.Invoke(); }
    }
}
