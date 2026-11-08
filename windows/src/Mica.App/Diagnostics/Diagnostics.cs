using System.Diagnostics;
using System.Text.Json;
using Mica.Core;

namespace Mica.App.Diagnostics;

/// <summary>Local log for unexpected errors in %LOCALAPPDATA%\mica\logs; nothing leaves the computer.</summary>
public static class Log
{
    public static void Error(Exception e)
    {
        try
        {
            var folder = Path.Combine(Store.Shared.Root, "logs");
            Directory.CreateDirectory(folder);
            File.AppendAllText(Path.Combine(folder, "errors.log"), DateTimeOffset.Now.ToString("O") + " " + e + Environment.NewLine);
        }
        catch (IOException) { }
    }
}

/// <summary>Runs only with --qa: a smoke test of live tabs, private isolation, blocking and notifications state,
/// and with --benchmark=N the memory of the WebView2 process tree. Reports go to the QA profile folder.</summary>
public static class QA
{
    sealed record Check(string Name, bool Passed, string Detail = "", bool Skipped = false);

    public static async Task RunAsync(Store store)
    {
        if (Program.Arguments.FirstOrDefault(a => a.StartsWith("--benchmark=", StringComparison.Ordinal)) is { } bench && int.TryParse(bench[12..], out var count)) { await BenchmarkAsync(store, count); return; }
        if (!Program.Has("--smoke-test")) return;
        var results = new List<Check>();
        var browser = store.Active!;
        browser.ShowOnboarding = false;
        var started = Stopwatch.StartNew();
        async Task<bool> Wait(Func<bool> test, double seconds = 15)
        {
            var deadline = Stopwatch.StartNew();
            while (deadline.Elapsed.TotalSeconds < seconds) { if (test()) return true; await Task.Delay(100); }
            return false;
        }
        var first = browser.Selected!;
        first.Load("https://example.com/");
        var online = await Wait(() => first.Core is not null && !first.Loading && first.Error is null && first.Title.Length > 0, 25);
        results.Add(new("real HTTPS navigation", online, first.Error ?? $"title={first.Title}, core={first.Core is not null}, loading={first.Loading}, source={first.Core?.Source}"));
        if (online)
        {
            await first.EvaluateAsync("window.identity = crypto.randomUUID(); true");
            var identity = await first.EvaluateAsync("window.identity");
            var others = new List<Tab>();
            for (var i = 0; i < 9; i++) { var t = browser.Add(new SavedTab { Url = "https://example.com/?" + i }); others.Add(t); }
            await Wait(() => others.All(t => t.Core is not null && !t.Loading), 40);
            results.Add(new("ten genuinely live tabs", browser.Tabs.Count(t => t.Core is not null) >= 10));
            browser.Select(first);
            results.Add(new("switch preserves JS identity", await first.EvaluateAsync("window.identity") == identity));
            var blocked = await first.EvaluateAsync("fetch('https://www.google-analytics.com/analytics.js',{mode:'no-cors',cache:'no-store'}).then(()=>true).catch(()=>false)");
            results.Add(new("third-party blocker", blocked == "false", blocked ?? "null"));
            foreach (var t in others) browser.Close(t);
        }
        var privateWindow = store.NewWindow(privateMode: true);
        privateWindow.Selected!.Load("https://example.com/");
        await Wait(() => privateWindow.Selected?.Core is not null && !privateWindow.Selected.Loading, 25);
        if (privateWindow.Selected?.Core is { } core)
        {
            results.Add(new("private profile is in-private", core.Profile.IsInPrivateModeEnabled));
            results.Add(new("private profile differs from normal", core.Profile.ProfileName != store.Engine.NormalProfileName, core.Profile.ProfileName));
        }
        var historyCount = store.History.Count;
        store.Record(privateWindow.Selected!);
        results.Add(new("private navigation excluded from history", store.History.Count == historyCount));
        privateWindow.Window?.Close();
        results.Add(new("notification state for unknown origin is default", NotificationPolicy.State("https://example.com", false, store.Permissions) == NotificationState.Default));
        Report(store, results, started.Elapsed.TotalSeconds);
        if (Program.Has("--exit-after-smoke")) store.Quit();
    }

    static void Report(Store store, List<Check> results, double seconds)
    {
        var lines = new List<string> { "{", $"  \"generated\": \"{DateTimeOffset.Now:O}\",", $"  \"durationSeconds\": {seconds.ToString(System.Globalization.CultureInfo.InvariantCulture)},", $"  \"failed\": {results.Count(r => !r.Passed)},", "  \"tests\": [" };
        lines.AddRange(results.Select((r, i) => $"    {{\"name\": {Tab.Json(r.Name)}, \"passed\": {(r.Passed ? "true" : "false")}, \"skipped\": {(r.Skipped ? "true" : "false")}, \"detail\": {Tab.Json(r.Detail)}}}" + (i < results.Count - 1 ? "," : "")));
        lines.Add("  ]"); lines.Add("}");
        File.WriteAllLines(Path.Combine(store.Root, "smoke-report.json"), lines);
    }

    /// <summary>Opens N tabs, waits, and records the private working set of mica and its WebView2 processes.</summary>
    static async Task BenchmarkAsync(Store store, int count)
    {
        var browser = store.Active!;
        for (var i = 0; i < count; i++) browser.Add(new SavedTab { Url = "https://example.com/?" + i }, activate: i == 0);
        await Task.Delay(TimeSpan.FromSeconds(20));
        var processes = new List<(string Name, int Pid, long Private)>();
        var self = Process.GetCurrentProcess();
        processes.Add(("mica", self.Id, self.PrivateMemorySize64));
        if (browser.Selected?.Core is { } core)
        {
            var infos = await core.Environment.GetProcessExtendedInfosAsync();
            foreach (var info in infos)
            {
                try { var p = Process.GetProcessById(info.ProcessInfo.ProcessId); processes.Add((info.ProcessInfo.Kind.ToString(), p.Id, p.PrivateMemorySize64)); }
                catch (ArgumentException) { }
            }
        }
        var lines = processes.Select(p => $"{p.Name}\t{p.Pid}\t{p.Private}").Prepend($"tabs\t{count}\ttotal_private_bytes\t{processes.Sum(p => p.Private)}");
        File.WriteAllLines(Path.Combine(store.Root, $"benchmark-{count}.tsv"), lines);
        store.Quit();
    }
}
