using System.IO.Compression;
using System.Security.Cryptography;
using System.Text.Json;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.Web.WebView2.Core;
using Mica.Core;
using Mica.Design;
using Windows.Storage.Pickers;

namespace Mica.App.Extensions;

/// <summary>Extensions on WebView2 (macOS uses WKWebExtensionController). Chrome Web Store packages are downloaded
/// from the same update address Chrome uses, the CRX3 signature and ID are verified in Mica.Core, and the archive is
/// unpacked into mica's profile and added to the normal WebView2 profile. WebView2 runs extensions with a limited
/// API set and shows no toolbar popups, so mica has no extension buttons on Windows; the panel manages them.
/// Firefox Add-ons are not offered: their packages target Gecko. Incognito windows never get extensions.</summary>
public sealed partial class ExtensionManager(Store store)
{
    public List<ExtensionRecord> Records { get; private set; } = [];
    public Dictionary<Guid, string> Errors { get; } = [];
    public string ChromeStatus { get; private set; } = "";
    public bool Busy { get; private set; }
    public event Action? Changed;
    string Folder => Path.Combine(store.Root, "Extensions");
    string FileName => "extensions.json";

    public List<ExtensionRecord> Actionable(bool privateWindow) => [];

    public async Task RestoreAsync()
    {
        try { Records = File.Exists(Path.Combine(store.Root, FileName)) ? Persistence.Read<List<ExtensionRecord>>(Path.Combine(store.Root, FileName)) : []; }
        catch (Exception e) when (e is IOException or JsonException) { Records = []; store.Issue = store.Text("список расширений повреждён: ", "Список расширений повреждён: ") + e.Message; }
        await Task.CompletedTask;
        Changed?.Invoke();
    }

    /// <summary>Called once the normal profile exists (first normal tab); keeps WebView2's list in step with mica's.</summary>
    public async Task SyncAsync(CoreWebView2Profile profile)
    {
        var installed = await profile.GetBrowserExtensionsAsync();
        foreach (var record in Records)
        {
            var folder = Path.Combine(Folder, record.Id.ToString("N"));
            var engine = installed.FirstOrDefault(e => e.Id == record.EngineId);
            try
            {
                if (engine is null && Directory.Exists(folder)) { engine = await profile.AddBrowserExtensionAsync(folder); record.EngineId = engine.Id; }
                if (engine is not null && engine.IsEnabled != record.Enabled) await engine.EnableAsync(record.Enabled);
                Errors.Remove(record.Id);
            }
            catch (Exception e) { Errors[record.Id] = e.Message; }
        }
        Save();
    }

    void Save() { store.Save(Records, FileName); Changed?.Invoke(); }

    async Task<CoreWebView2Profile?> Profile()
    {
        if (store.Engine.NormalProfile is { } profile) return profile;
        ChromeStatus = store.Text("откройте любую страницу в обычном окне и повторите: профиль WebView2 ещё не создан", "Откройте любую страницу в обычном окне и повторите: профиль WebView2 ещё не создан");
        Changed?.Invoke();
        await Task.CompletedTask;
        return null;
    }

    public async Task InstallFromChromeStoreAsync(string input)
    {
        if (ChromeStore.ExtensionId(input) is not { } id) { ChromeStatus = store.Text("нужна ссылка на расширение в Chrome Web Store или его ID", "Нужна ссылка на расширение в Chrome Web Store или его ID"); Changed?.Invoke(); return; }
        if (await Profile() is not { } profile || Busy) return;
        Busy = true; ChromeStatus = store.Text("загрузка и проверка…", "Загрузка и проверка…"); Changed?.Invoke();
        try
        {
            using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(60) };
            http.DefaultRequestHeaders.UserAgent.ParseAdd($"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/{ChromeStore.ProductVersion} Safari/537.36");
            var bytes = await http.GetByteArrayAsync(ChromeStore.DownloadUrl(id));
            if (bytes.Length > 64 * 1024 * 1024) throw new CrxException("package too large");
            var package = new CrxPackage(bytes);
            package.Verify(id);
            await AddArchiveAsync(profile, package.Archive, "cws:" + id, Records.FirstOrDefault(r => r.Source == "cws:" + id));
            ChromeStatus = store.Text("установлено", "Установлено");
        }
        catch (Exception e) when (e is HttpRequestException or TaskCanceledException or CrxException or InvalidDataException or IOException or JsonException)
        {
            ChromeStatus = store.Text("не установлено: ", "Не установлено: ") + e.Message;
        }
        finally { Busy = false; Changed?.Invoke(); }
    }

    public async void ChooseImport(nint window)
    {
        var picker = new FileOpenPicker();
        picker.FileTypeFilter.Add(".zip"); picker.FileTypeFilter.Add(".crx");
        WinRT.Interop.InitializeWithWindow.Initialize(picker, window);
        var file = await picker.PickSingleFileAsync();
        if (file is null || await Profile() is not { } profile) return;
        try
        {
            var bytes = await File.ReadAllBytesAsync(file.Path);
            var archive = bytes.Length > 4 && bytes[0] == 0x43 && bytes[1] == 0x72 ? new CrxPackage(bytes).Archive : bytes;
            await AddArchiveAsync(profile, archive, "file:" + file.Name, null);
        }
        catch (Exception e) { ChromeStatus = store.Text("не установлено: ", "Не установлено: ") + e.Message; Changed?.Invoke(); }
    }

    /// <summary>Unpacks with path checks, shows the requested permissions before any code runs, then adds it.</summary>
    async Task AddArchiveAsync(CoreWebView2Profile profile, byte[] archive, string source, ExtensionRecord? replacing)
    {
        var record = replacing ?? new ExtensionRecord { Source = source };
        var folder = Path.Combine(Folder, record.Id.ToString("N"));
        var staging = folder + ".staging";
        if (Directory.Exists(staging)) Directory.Delete(staging, true);
        Directory.CreateDirectory(staging);
        using (var zip = new ZipArchive(new MemoryStream(archive)))
        {
            long total = 0;
            foreach (var entry in zip.Entries)
            {
                if (!PackageSafety.SafeEntry(entry.FullName)) throw new InvalidDataException("unsafe path " + entry.FullName);
                total += entry.Length;
                if (total > 256L * 1024 * 1024) throw new InvalidDataException("archive too large");
                var target = Path.GetFullPath(Path.Combine(staging, entry.FullName));
                if (!target.StartsWith(Path.GetFullPath(staging) + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("unsafe path " + entry.FullName);
                if (entry.FullName.EndsWith('/')) { Directory.CreateDirectory(target); continue; }
                Directory.CreateDirectory(Path.GetDirectoryName(target)!);
                entry.ExtractToFile(target, overwrite: true);
            }
        }
        var manifestPath = Path.Combine(staging, "manifest.json");
        if (!File.Exists(manifestPath)) throw new InvalidDataException("manifest.json is missing");
        using var manifest = JsonDocument.Parse(await File.ReadAllBytesAsync(manifestPath));
        var root = manifest.RootElement;
        string Text(string key) => root.TryGetProperty(key, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString()! : "";
        var permissions = new List<string>(); var hosts = new List<string>();
        foreach (var key in new[] { "permissions", "optional_permissions" })
            if (root.TryGetProperty(key, out var list) && list.ValueKind == JsonValueKind.Array)
                foreach (var item in list.EnumerateArray()) if (item.GetString() is { } p) (p.Contains("://") || p == "<all_urls>" ? hosts : permissions).Add(p);
        if (root.TryGetProperty("host_permissions", out var hostList) && hostList.ValueKind == JsonValueKind.Array) foreach (var item in hostList.EnumerateArray()) if (item.GetString() is { } h) hosts.Add(h);
        var name = Text("name"); if (name.StartsWith("__MSG_", StringComparison.Ordinal)) name = source.Split(':').Last();
        var answer = await Dialogs.Ask(store.Active?.Window, store.Text("установить расширение?", "Установить расширение?") + " " + name,
            "API: " + (permissions.Count == 0 ? "-" : string.Join(", ", permissions)) + "\n" + store.Text("сайты: ", "Сайты: ") + (hosts.Count == 0 ? store.Text("доступ не запрошен", "доступ не запрошен") : string.Join(", ", hosts)) + "\n\n" + store.Text("WebView2 поддерживает часть API расширений Chrome. кнопки и всплывающие окна расширений на панели не показываются.", "WebView2 поддерживает часть API расширений Chrome. Кнопки и всплывающие окна расширений на панели не показываются."),
            [store.Text("отмена", "Отмена"), store.Text("установить", "Установить")]);
        if (answer != 1) { Directory.Delete(staging, true); return; }
        if (replacing?.EngineId is { } old) { foreach (var e in await profile.GetBrowserExtensionsAsync()) if (e.Id == old) await e.RemoveAsync(); }
        if (Directory.Exists(folder)) Directory.Delete(folder, true);
        Directory.Move(staging, folder);
        var engine = await profile.AddBrowserExtensionAsync(folder);
        record.Name = name; record.Version = Text("version"); record.Enabled = true; record.EngineId = engine.Id;
        record.Permissions = permissions; record.Hosts = hosts;
        record.Digest = Convert.ToHexString(SHA256.HashData(archive)).ToLowerInvariant();
        if (replacing is null) Records.Add(record);
        Save();
    }

    public async Task ToggleAsync(ExtensionRecord record)
    {
        if (await Profile() is not { } profile) return;
        record.Enabled = !record.Enabled;
        foreach (var e in await profile.GetBrowserExtensionsAsync()) if (e.Id == record.EngineId) await e.EnableAsync(record.Enabled);
        Save();
    }

    public async Task RemoveAsync(ExtensionRecord record)
    {
        if (await Profile() is { } profile) foreach (var e in await profile.GetBrowserExtensionsAsync()) if (e.Id == record.EngineId) await e.RemoveAsync();
        try { Directory.Delete(Path.Combine(Folder, record.Id.ToString("N")), true); } catch (IOException) { }
        Records.Remove(record);
        Save();
    }
}
