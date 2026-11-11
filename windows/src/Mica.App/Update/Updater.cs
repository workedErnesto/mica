using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text.Json;
using Mica.Core;
using Mica.Design;

namespace Mica.App.Update;

/// <summary>Daily release check on GitHub (macOS Updater). The installer for this architecture is downloaded,
/// checked against the .sha256 file of the release, and started with the user's consent; it updates in place.</summary>
public sealed partial class Updater(Store store)
{
    CancellationTokenSource? schedule;
    bool checking;
    string StampPath => Path.Combine(store.Root, "last-release-check.txt");
    public static AppVersion? CurrentVersion => AppVersion.Parse(typeof(Updater).Assembly.GetName().Version is { } v ? $"{v.Major}.{v.Minor}.{v.Build}" : null);
    public static string Arch => RuntimeInformation.ProcessArchitecture == Architecture.Arm64 ? "arm64" : "x64";

    public void Start()
    {
        if (Program.QA) return;
        schedule?.Cancel();
        schedule = new CancellationTokenSource();
        var token = schedule.Token;
        _ = Task.Run(async () =>
        {
            while (!token.IsCancellationRequested)
            {
                DateTimeOffset? last = File.Exists(StampPath) && DateTimeOffset.TryParse(File.ReadAllText(StampPath), out var t) ? t : null;
                var delay = UpdatePolicy.DelaySinceLastCheck(last, DateTimeOffset.Now);
                try { if (delay > TimeSpan.Zero) await Task.Delay(delay, token); } catch (TaskCanceledException) { return; }
                if (store.Preferences.UpdateChecks) await CheckAsync();
                else try { await Task.Delay(UpdatePolicy.CheckInterval, token); } catch (TaskCanceledException) { return; }
            }
        }, token);
    }

    public void EnableChecks(bool enabled)
    {
        store.Change(p => { p.UpdateChecks = enabled; if (enabled) p.SkippedVersion = null; });
        if (enabled) { try { File.Delete(StampPath); } catch (IOException) { } Start(); }
    }

    async Task CheckAsync()
    {
        if (checking || CurrentVersion is not { } current) return;
        checking = true;
        try
        {
            File.WriteAllText(StampPath, DateTimeOffset.Now.ToString("O"));
            using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(30) };
            http.DefaultRequestHeaders.UserAgent.ParseAdd("mica");
            http.DefaultRequestHeaders.Accept.ParseAdd("application/vnd.github+json");
            var json = await http.GetStringAsync(UpdatePolicy.LatestUrl);
            if (json.Length > 1_000_000) return;
            var release = JsonSerializer.Deserialize(json, MicaJson.Info<Release>());
            if (release is null || !UpdatePolicy.Offer(release, current, store.Preferences, Arch) || release.Version is not { } version) return;
            MicaApplication.Current?.Dispatcher.TryEnqueue(async () =>
            {
                var answer = await Dialogs.Ask(store.Active?.Window, store.Text("доступна mica ", "Доступна mica ") + version,
                    store.Text("установщик будет проверен по SHA-256 и запущен. mica закроется и обновится, вкладки восстановятся.", "Установщик будет проверен по SHA-256 и запущен. mica закроется и обновится, вкладки восстановятся."),
                    [store.Text("позже", "Позже"), store.Text("не предлагать эту версию", "Не предлагать эту версию"), store.Text("установить", "Установить")]);
                if (answer == 2) await InstallAsync(release);
                else if (answer == 1) store.Change(p => p.SkippedVersion = version.ToString());
            });
        }
        catch (Exception e) when (e is HttpRequestException or TaskCanceledException or JsonException or IOException) { }
        finally { checking = false; }
    }

    async Task InstallAsync(Release release)
    {
        if (release.Installer(Arch) is not { } installer || release.Checksum(Arch) is not { } checksum) return;
        try
        {
            if (!Uri.TryCreate(installer.Url, UriKind.Absolute, out var a) || a.Host != "github.com" || a.Scheme != "https" || !Uri.TryCreate(checksum.Url, UriKind.Absolute, out var b) || b.Host != "github.com" || installer.Name != Path.GetFileName(installer.Name)) throw new InvalidDataException();
            using var http = new HttpClient { Timeout = TimeSpan.FromMinutes(10) };
            http.DefaultRequestHeaders.UserAgent.ParseAdd("mica");
            var expected = UpdatePolicy.ParseChecksum(await http.GetStringAsync(checksum.Url)) ?? throw new InvalidDataException();
            var folder = Path.Combine(Path.GetTempPath(), "mica-update");
            Directory.CreateDirectory(folder);
            var path = Path.Combine(folder, installer.Name);
            await using (var source = await http.GetStreamAsync(installer.Url))
            await using (var file = File.Create(path)) await source.CopyToAsync(file);
            await using (var check = File.OpenRead(path))
                if (Convert.ToHexString(await SHA256.HashDataAsync(check)).ToLowerInvariant() != expected) { File.Delete(path); throw new CryptographicException(); }
            System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(path, "--update") { UseShellExecute = true });
            store.Quit();
        }
        catch (Exception e)
        {
            var reason = e is CryptographicException ? store.Text("контрольная сумма не совпала. установщик не запущен", "Контрольная сумма не совпала. Установщик не запущен") : store.Text("не удалось скачать или запустить установщик. попробуйте позже", "Не удалось скачать или запустить установщик. Попробуйте позже");
            await Dialogs.Ask(store.Active?.Window, store.Text("обновление не установлено", "Обновление не установлено"), reason, [store.Text("понятно", "Понятно")]);
        }
    }
}
