using System.Security.Cryptography;
using System.Runtime.InteropServices.WindowsRuntime;
using System.Text;
using System.Text.Json;
using Microsoft.UI.Xaml;
using Microsoft.Web.WebView2.Core;

namespace Mica.App;

/// <summary>Pinned uBO compiler and lists, compiled in a temporary local-only WebView2 controller.
/// Network rules run in the request handler; CSS and scriptlets are installed before document creation.</summary>
public sealed class UBlockEngine(Store store)
{
    record FilterList(string Key, string? Local, string[] Remote, bool Trusted);
    public event Action? Changed;
    public ContentRules? Rules { get; private set; }
    public string Script { get; private set; } = "";
    public string Status { get; private set; } = "";
    public bool Prepared { get; private set; }
    public bool Busy { get; private set; }
    public bool Updating { get; private set; }
    public DateTime? ListsUpdated { get; private set; }
    public int Count => Rules?.Count ?? 0;
    string Summary => store.Text("правил для запросов: ", "Правил для запросов: ") + Count.ToString("N0");
    public string? Issue => !Busy && !Updating && Status.Length > 0 && Status != Summary ? Status : null;
    readonly SemaphoreSlim work = new(1);
    readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromHours(1) };
    bool scheduled;
    int generation;
    CancellationTokenSource? updateRequest;
    static string Assets => Path.Combine(AppContext.BaseDirectory, "Assets", "Blocking");
    string Folder => Path.Combine(store.Root, "UBlock");
    string ListFolder => Path.Combine(Folder, "lists");
    string Stamp => Path.Combine(Folder, "updated.txt");
    void Notify() => Changed?.Invoke();
    List<FilterList> Lists()
    {
        using var document = JsonDocument.Parse(File.ReadAllText(Path.Combine(Assets, "ublock", "assets", "assets.json")));
        static string[] URLs(JsonElement entry, string key) => !entry.TryGetProperty(key, out var value) ? [] : value.ValueKind == JsonValueKind.Array ? value.EnumerateArray().Select(v => v.GetString()!).ToArray() : [value.GetString()!];
        var lists = new List<FilterList>();
        foreach (var property in document.RootElement.EnumerateObject().OrderBy(p => p.Name, StringComparer.Ordinal))
        {
            var e = property.Value;
            if (!e.TryGetProperty("content", out var content) || content.GetString() != "filters" || e.TryGetProperty("off", out var off) && off.ValueKind == JsonValueKind.True || property.Name.StartsWith("urlhaus")) continue;
            var urls = URLs(e, "contentURL");
            var local = urls.Where(u => !u.StartsWith("http")).SelectMany(u => new[] { u, u.EndsWith(".txt") ? u[..^4] : u }).Select(u => Path.Combine(Assets, "ublock", u)).FirstOrDefault(File.Exists);
            lists.Add(new(property.Name, local, URLs(e, "cdnURLs").Concat(urls).Where(u => Uri.TryCreate(u, UriKind.Absolute, out var uri) && uri.Scheme == "https").ToArray(), property.Name.StartsWith("ublock-")));
        }
        return lists;
    }
    string? Source(FilterList list) { var cached = Path.Combine(ListFolder, list.Key + ".txt"); return File.Exists(cached) ? cached : list.Local; }
    public async Task StartAsync()
    {
        try { await RebuildAsync(); } finally { Prepared = true; }
        if (!scheduled) {
            scheduled = true;
            timer.Tick += async (_, _) => await UpdateIfDue();
            timer.Start();
        }
        await UpdateIfDue();
    }
    async Task UpdateIfDue()
    {
        if (store.Preferences.Blocking && (ListsUpdated is null || DateTime.UtcNow - ListsUpdated > TimeSpan.FromDays(1))) await UpdateAsync();
    }
    public async Task RebuildAsync()
    {
        var version = ++generation;
        if (!store.Preferences.Blocking)
        {
            updateRequest?.Cancel();
            Rules = null; Script = ""; Status = ""; await RefreshTabs(); Notify(); return;
        }
        await work.WaitAsync();
        try
        {
            if (version != generation) return;
            Busy = true; Status = store.Text("сборка фильтров uBlock Origin…", "Сборка фильтров uBlock Origin…"); Notify();
            Directory.CreateDirectory(Folder);
            if (File.Exists(Stamp) && DateTime.TryParse(File.ReadAllText(Stamp), System.Globalization.CultureInfo.InvariantCulture, System.Globalization.DateTimeStyles.RoundtripKind, out var date)) ListsUpdated = date;
            var lists = Lists();
            using var hash = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
            hash.AppendData(File.ReadAllBytes(Path.Combine(Assets, "compiler.mjs")));
            hash.AppendData(File.ReadAllBytes(Path.Combine(Assets, "ublock", "manifest.json")));
            foreach (var exception in store.Preferences.BlockingExceptions.Order(StringComparer.Ordinal)) hash.AppendData(Encoding.UTF8.GetBytes(exception + "\n"));
            foreach (var list in lists) if (Source(list) is { } source) { hash.AppendData(Encoding.UTF8.GetBytes(list.Key)); hash.AppendData(File.ReadAllBytes(source)); }
            var fingerprint = Convert.ToHexString(hash.GetHashAndReset());
            var cache = Path.Combine(Folder, "compiled.json"); var key = Path.Combine(Folder, "fingerprint.txt");
            string result;
            if (File.Exists(cache) && File.Exists(key) && File.ReadAllText(key) == fingerprint) result = await File.ReadAllTextAsync(cache);
            else result = await Compile(lists);
            if (version != generation || !store.Preferences.Blocking) return;
            var parsed = await Task.Run(() => ParseCompiled(result));
            var rules = parsed.Rules;
            if (version != generation || !store.Preferences.Blocking) return;
            var exceptionsJSON = "[" + string.Join(',', store.Preferences.BlockingExceptions.Select(Tab.Json)) + "]";
            var cosmetic = parsed.Cosmetic;
            // The wrappers run in every frame; ancestorOrigins also respects an excluded top-level site in cross-origin frames.
            var prefix = "(()=>{const off=" + exceptionsJSON + ";const match=(h,d)=>h===d||h.endsWith('.'+d);const hosts=[location.hostname,...Array.from(location.ancestorOrigins||[],u=>{try{return new URL(u).hostname}catch{return ''}})];if(hosts.some(h=>off.some(d=>match(h,d))))return;";
            var css = "const rules=" + cosmetic + ";const host=hosts.at(-1)||location.hostname;const selectors=[];for(const r of rules){if(r.action.type!=='css-display-none')continue;const t=r.trigger;if(t['if-domain']&&!t['if-domain'].some(d=>match(host,d.replace(/^\\*/,''))))continue;if(t['unless-domain']&&t['unless-domain'].some(d=>match(host,d.replace(/^\\*/,''))))continue;selectors.push(r.action.selector)}if(selectors.length){const style=document.createElement('style');style.textContent=selectors.map(s=>s+'{display:none!important}').join('\\n');const attach=()=>{if(document.documentElement){document.documentElement.append(style);return true}return false};if(!attach()){const observer=new MutationObserver(()=>{if(attach())observer.disconnect()});observer.observe(document,{childList:true})}}";
            // WebView2's public document-created API uses the page world. Each upstream bundle keeps its own closure.
            var script = prefix + css + "\n" + parsed.Main + "\n" + parsed.Isolated + "\n})();";
            Mica.Core.Persistence.WriteBytes(Encoding.UTF8.GetBytes(result), cache);
            Mica.Core.Persistence.WriteBytes(Encoding.UTF8.GetBytes(fingerprint), key);
            Rules = rules; Script = script;
            Status = Summary;
            await RefreshTabs();
        }
        catch (Exception e) { if (version == generation) Status = store.Text("фильтры uBlock Origin не собраны: ", "Фильтры uBlock Origin не собраны: ") + e.Message; Diagnostics.Log.Error(e); }
        finally { Busy = false; work.Release(); Notify(); }
    }
    static (ContentRules Rules, string Cosmetic, string Main, string Isolated) ParseCompiled(string json)
    {
        var reader = new Utf8JsonReader(Encoding.UTF8.GetBytes(json));
        ContentRules? rules = null; string cosmetic = "[]", main = "", isolated = "";
        reader.Read();
        while (reader.Read() && reader.TokenType != JsonTokenType.EndObject) {
            var key = reader.GetString(); reader.Read();
            if (key == "windows") rules = new ContentRules(ref reader, File.ReadAllText(Path.Combine(Assets, "ublock", "assets", "thirdparties", "publicsuffix.org", "list", "effective_tld_names.dat")));
            else if (key == "main") main = reader.GetString() ?? "";
            else if (key == "isolated") isolated = reader.GetString() ?? "";
            else if (key == "cosmetic") { using var value = JsonDocument.ParseValue(ref reader); cosmetic = value.RootElement.GetRawText(); }
            else reader.Skip();
        }
        return (rules ?? throw new JsonException("No network rules"), cosmetic, main, isolated);
    }
    async Task RefreshTabs()
    {
        foreach (var window in store.Windows.ToArray()) foreach (var tab in window.Model.Tabs.ToArray()) await tab.RefreshUBlockAsync();
    }
    async Task<string> Compile(List<FilterList> lists)
    {
        var environment = store.Engine.Environment ?? throw new InvalidOperationException("WebView2 unavailable");
        var window = store.Windows.FirstOrDefault() ?? throw new InvalidOperationException("No window for filter compiler");
        var options = environment.CreateCoreWebView2ControllerOptions(); options.ProfileName = "mica-filter-compiler"; options.IsInPrivateModeEnabled = true;
        var controller = await environment.CreateCoreWebView2ControllerAsync(CoreWebView2ControllerWindowReference.CreateFromWindowHandle((ulong)Win32.Handle(window)), options);
        try
        {
            controller.IsVisible = false;
            var core = controller.CoreWebView2;
            core.Settings.IsWebMessageEnabled = true; core.Settings.AreDevToolsEnabled = false;
            core.Settings.AreDefaultScriptDialogsEnabled = false;
            core.PermissionRequested += (_, e) => e.State = CoreWebView2PermissionState.Deny;
            core.NewWindowRequested += (_, e) => e.Handled = true;
            core.SetVirtualHostNameToFolderMapping("mica.filters", Assets, CoreWebView2HostResourceAccessKind.DenyCors);
            core.NavigationStarting += (_, e) => { if (!e.Uri.StartsWith("https://mica.filters/", StringComparison.Ordinal)) e.Cancel = true; };
            core.AddWebResourceRequestedFilter("*", CoreWebView2WebResourceContext.All, CoreWebView2WebResourceRequestSourceKinds.All);
            core.WebResourceRequested += (_, e) =>
            {
                if (!Uri.TryCreate(e.Request.Uri, UriKind.Absolute, out var uri) || uri.Scheme != "https" || uri.Host is not ("mica.filters" or "mica.lists")) { e.Response = environment.CreateWebResourceResponse(null, 403, "Forbidden", ""); return; }
                if (uri.Host != "mica.lists") return;
                var key = uri.AbsolutePath[1..];
                var list = lists.FirstOrDefault(l => l.Key == key);
                if (list is null || Source(list) is not { } source) { e.Response = environment.CreateWebResourceResponse(null, 404, "Not found", ""); return; }
                e.Response = environment.CreateWebResourceResponse(new MemoryStream(File.ReadAllBytes(source)).AsRandomAccessStream(), 200, "OK", "Content-Type: text/plain; charset=utf-8\r\nAccess-Control-Allow-Origin: https://mica.filters");
            };
            var loaded = new TaskCompletionSource<bool>();
            core.NavigationCompleted += (_, e) => { if (e.IsSuccess) loaded.TrySetResult(true); else loaded.TrySetException(new IOException("Compiler navigation: " + e.WebErrorStatus)); };
            var completed = new TaskCompletionSource<string>();
            core.WebMessageReceived += (_, e) =>
            {
                if (!e.Source.StartsWith("https://mica.filters/", StringComparison.Ordinal)) return;
                var json = e.TryGetWebMessageAsString();
                if (json.StartsWith("{\"error\":", StringComparison.Ordinal)) {
                    using var message = JsonDocument.Parse(json);
                    completed.TrySetException(new InvalidDataException(message.RootElement.GetProperty("error").GetString()));
                } else completed.TrySetResult(json);
            };
            core.Navigate("https://mica.filters/index.html");
            await loaded.Task.WaitAsync(TimeSpan.FromSeconds(30));
            var keys = "[" + string.Join(',', lists.Where(l => Source(l) != null).Select(l => "{key:" + Tab.Json(l.Key) + ",trustedSource:" + (l.Trusted ? "true" : "false") + "}")) + "]";
            var exceptions = "[" + string.Join(',', store.Preferences.BlockingExceptions.Select(Tab.Json)) + "]";
            await core.ExecuteScriptAsync("(async()=>{try{const keys=" + keys + ";const lists=await Promise.all(keys.map(async k=>({name:k.key,trustedSource:k.trustedSource,text:await(await fetch('https://mica.lists/'+k.key)).text()})));const {build}=await import('/compiler.mjs');const probe=document.createElement('div');const validSelector=s=>{try{probe.querySelector(s);return true}catch{return false}};const output=await build(lists,{validSelector,exceptions:" + exceptions + "});delete output.network;chrome.webview.postMessage(JSON.stringify(output));}catch(e){chrome.webview.postMessage(JSON.stringify({error:String(e.stack||e)}))}})()");
            return await completed.Task.WaitAsync(TimeSpan.FromMinutes(2));
        }
        finally { controller.Close(); }
    }
    public async Task UpdateAsync()
    {
        if (Updating || !store.Preferences.Blocking) return;
        Updating = true; Notify();
        using var cancellation = new CancellationTokenSource(); updateRequest = cancellation;
        var token = cancellation.Token;
        try
        {
            Directory.CreateDirectory(ListFolder);
            using var handler = new HttpClientHandler { UseCookies = false };
            using var http = new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(30), MaxResponseContentBufferSize = 30_000_000 };
            var failed = new List<string>(); bool changed = false;
            foreach (var list in Lists())
            {
                token.ThrowIfCancellationRequested();
                bool done = false;
                foreach (var url in list.Remote)
                {
                    try
                    {
                        using var response = await http.GetAsync(url, token);
                        if (!response.IsSuccessStatusCode || response.RequestMessage?.RequestUri?.Scheme != "https") continue;
                        var data = await response.Content.ReadAsByteArrayAsync();
                        if (data.Length is < 500 or > 30_000_000 || data[0] == (byte)'<') continue;
                        var target = Path.Combine(ListFolder, list.Key + ".txt");
                        if (!File.Exists(target) || !File.ReadAllBytes(target).SequenceEqual(data)) { Mica.Core.Persistence.WriteBytes(data, target); changed = true; }
                        done = true; break;
                    }
                    catch (Exception e) when (e is HttpRequestException or TaskCanceledException) { if (token.IsCancellationRequested) throw; }
                }
                if (!done) failed.Add(list.Key);
            }
            if (failed.Count < Lists().Count) { ListsUpdated = DateTime.UtcNow; File.WriteAllText(Stamp, ListsUpdated.Value.ToString("O", System.Globalization.CultureInfo.InvariantCulture)); }
            if (changed) await RebuildAsync();
            if (failed.Count == 0) Status = Summary;
            if (failed.Count > 0) Status = store.Text("не обновлены: ", "Не обновлены: ") + string.Join(", ", failed);
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested) { }
        catch (Exception e) { Status = e.Message; Diagnostics.Log.Error(e); }
        finally { updateRequest = null; Updating = false; Notify(); }
    }
}
