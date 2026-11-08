using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.Data.Sqlite;

namespace Mica.Core;

/// <summary>Browser engine family: decides where profiles live and how their files are read.</summary>
public enum BrowserFamily { Chromium, Gecko }

public enum DataFolder { Local, Roaming }

/// <summary>A browser mica can read from on Windows. Safari and Orion exist only on macOS.</summary>
public sealed record ImportBrowser(string Id, string Name, BrowserFamily Family, DataFolder Base, string Folder)
{
    public static readonly ImportBrowser[] All =
    [
        new("chrome", "Google Chrome", BrowserFamily.Chromium, DataFolder.Local, @"Google\Chrome\User Data"),
        new("edge", "Microsoft Edge", BrowserFamily.Chromium, DataFolder.Local, @"Microsoft\Edge\User Data"),
        new("yandex", "Яндекс Браузер", BrowserFamily.Chromium, DataFolder.Local, @"Yandex\YandexBrowser\User Data"),
        new("arc", "Arc", BrowserFamily.Chromium, DataFolder.Local, @"Packages\TheBrowserCompany.Arc_*\LocalCache\Local\Arc\User Data"),
        new("brave", "Brave", BrowserFamily.Chromium, DataFolder.Local, @"BraveSoftware\Brave-Browser\User Data"),
        new("opera", "Opera", BrowserFamily.Chromium, DataFolder.Roaming, @"Opera Software\Opera Stable"),
        new("operagx", "Opera GX", BrowserFamily.Chromium, DataFolder.Roaming, @"Opera Software\Opera GX Stable"),
        new("vivaldi", "Vivaldi", BrowserFamily.Chromium, DataFolder.Local, @"Vivaldi\User Data"),
        new("chromium", "Chromium", BrowserFamily.Chromium, DataFolder.Local, @"Chromium\User Data"),
        new("firefox", "Firefox", BrowserFamily.Gecko, DataFolder.Roaming, @"Mozilla\Firefox"),
        new("zen", "Zen", BrowserFamily.Gecko, DataFolder.Roaming, "zen"),
    ];

    /// <summary>Brand names stay as written; only the Yandex one has an established English form.</summary>
    public string DisplayName(Language language) => Id == "yandex" && language == Language.En ? "Yandex Browser" : Name;

    /// <summary>Existing data folder, resolving a single * segment (packaged apps carry a publisher hash).</summary>
    public string? Root(string local, string roaming)
    {
        var start = Base == DataFolder.Local ? local : roaming;
        var current = new List<string> { start };
        foreach (var part in Folder.Split('\\'))
        {
            current = part.Contains('*')
                ? current.Where(Directory.Exists).SelectMany(c => Directory.EnumerateDirectories(c, part)).ToList()
                : current.Select(c => System.IO.Path.Combine(c, part)).ToList();
        }
        return current.FirstOrDefault(Directory.Exists);
    }
}

public sealed record ImportProfile(ImportBrowser Browser, string Name, string Path)
{
    public string Id => Browser.Id + ":" + Path;
}

public enum ImportKind { History, Bookmarks }

public sealed class ImportBundle
{
    public List<Visit> History { get; set; } = [];
    public List<Visit> Bookmarks { get; set; } = [];
}

public sealed class ImportException(ImportFailure failure, string detail) : Exception(detail)
{
    public ImportFailure Failure { get; } = failure;
}

public enum ImportFailure { NoAccess, Unreadable, Locked }

/// <summary>Read-only copy of another browser's SQLite database. The browser may hold the file open and keep recent
/// rows in the write-ahead log, so the file and its -wal are copied to a private temporary folder first.</summary>
public sealed class SQLiteSnapshot : IDisposable
{
    readonly SqliteConnection connection;
    readonly string folder;

    public SQLiteSnapshot(string source)
    {
        if (!File.Exists(source)) throw new ImportException(ImportFailure.Unreadable, System.IO.Path.GetFileName(source));
        folder = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "mica-import-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(folder);
        var copy = System.IO.Path.Combine(folder, "db.sqlite");
        try { CopyShared(source, copy); }
        catch (IOException) { Directory.Delete(folder, true); throw new ImportException(ImportFailure.Locked, source); }
        catch (UnauthorizedAccessException) { Directory.Delete(folder, true); throw new ImportException(ImportFailure.NoAccess, source); }
        if (File.Exists(source + "-wal")) { try { CopyShared(source + "-wal", copy + "-wal"); } catch (IOException) { } }
        connection = new SqliteConnection(new SqliteConnectionStringBuilder { DataSource = copy, Mode = SqliteOpenMode.ReadWrite, Pooling = false }.ToString());
        try { connection.Open(); }
        catch (SqliteException) { connection.Dispose(); Directory.Delete(folder, true); throw new ImportException(ImportFailure.Unreadable, System.IO.Path.GetFileName(source)); }
    }

    /// <summary>Opens with every share mode so a running browser that keeps the file open does not block the copy.</summary>
    static void CopyShared(string from, string to)
    {
        using var input = new FileStream(from, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
        using var output = new FileStream(to, FileMode.CreateNew, FileAccess.Write);
        input.CopyTo(output);
    }

    public List<object?[]> Rows(string sql, params long[] bindings)
    {
        using var command = connection.CreateCommand();
        command.CommandText = sql;
        for (var i = 0; i < bindings.Length; i++) command.Parameters.AddWithValue("$p" + (i + 1), bindings[i]);
        var result = new List<object?[]>();
        try
        {
            using var reader = command.ExecuteReader();
            while (reader.Read())
            {
                var row = new object?[reader.FieldCount];
                for (var c = 0; c < row.Length; c++) row[c] = reader.IsDBNull(c) ? null : reader.GetValue(c);
                result.Add(row);
            }
        }
        catch (SqliteException e) { throw new ImportException(ImportFailure.Unreadable, e.Message); }
        return result;
    }

    public void Dispose()
    {
        connection.Dispose();
        SqliteConnection.ClearAllPools();
        try { Directory.Delete(folder, true); } catch (IOException) { }
    }

    public static long? Int(object? value) => value switch { long l => l, double d => (long)d, string s when long.TryParse(s, out var l) => l, _ => null };
    public static string? Text(object? value) => value switch { string s => s, long l => l.ToString(), _ => null };
}

/// <summary>Chrome, Edge, Brave, Opera, Vivaldi, Yandex and Arc keep the same file layout.</summary>
public static class ChromiumReader
{
    const long EpochOffset = 11_644_473_600L * 1_000_000;

    public static DateTimeOffset? Date(long chromium) => chromium > EpochOffset ? DateTimeOffset.FromUnixTimeMilliseconds((chromium - EpochOffset) / 1000) : null;

    public static List<ImportProfile> Profiles(ImportBrowser browser, string root)
    {
        var names = new Dictionary<string, string>();
        try
        {
            using var json = JsonDocument.Parse(File.ReadAllBytes(System.IO.Path.Combine(root, "Local State")));
            if (json.RootElement.TryGetProperty("profile", out var profile) && profile.TryGetProperty("info_cache", out var cache))
                foreach (var entry in cache.EnumerateObject())
                    if (entry.Value.TryGetProperty("name", out var name) && name.GetString() is { } text) names[entry.Name] = text;
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException) { }
        var folders = Directory.Exists(root)
            ? Directory.EnumerateDirectories(root).Select(System.IO.Path.GetFileName).OfType<string>().Where(f => f == "Default" || f.StartsWith("Profile ", StringComparison.Ordinal))
                .OrderBy(f => f == "Default" ? 0 : 1).ThenBy(f => int.TryParse(f.Split(' ').Last(), out var n) ? n : int.MaxValue).ThenBy(f => f, StringComparer.Ordinal).ToList()
            : [];
        var result = folders.Select(folder => (folder, path: System.IO.Path.Combine(root, folder)))
            .Where(x => File.Exists(System.IO.Path.Combine(x.path, "History")) || File.Exists(System.IO.Path.Combine(x.path, "Bookmarks")))
            .Select(x => new ImportProfile(browser, names.GetValueOrDefault(x.folder, x.folder), x.path)).ToList();
        // Opera keeps its only profile in the data folder itself.
        if (result.Count == 0 && File.Exists(System.IO.Path.Combine(root, "History"))) result.Add(new ImportProfile(browser, "", root));
        return result;
    }

    public static List<Visit> History(string profile, int limit = 3000)
    {
        using var db = new SQLiteSnapshot(System.IO.Path.Combine(profile, "History"));
        return db.Rows("SELECT url, title, last_visit_time FROM urls WHERE hidden = 0 ORDER BY last_visit_time DESC LIMIT $p1", limit)
            .Select(row => SQLiteSnapshot.Text(row[0]) is { } url && SQLiteSnapshot.Int(row[2]) is { } time && Date(time) is { } date ? ImportMerge.Visit(url, SQLiteSnapshot.Text(row[1]), date) : null)
            .OfType<Visit>().ToList();
    }

    public static List<Visit> Bookmarks(string profile)
    {
        var file = System.IO.Path.Combine(profile, "Bookmarks");
        if (!File.Exists(file)) return [];
        byte[] data;
        try { data = File.ReadAllBytes(file); } catch (Exception e) when (e is IOException or UnauthorizedAccessException) { throw new ImportException(ImportFailure.NoAccess, file); }
        return Bookmarks(data);
    }

    /// <summary>Bookmark bar first, then other and mobile bookmarks, folders flattened in order.</summary>
    public static List<Visit> Bookmarks(byte[] json)
    {
        var result = new List<Visit>();
        JsonDocument document;
        try { document = JsonDocument.Parse(json); } catch (JsonException) { throw new ImportException(ImportFailure.Unreadable, "Bookmarks"); }
        using (document)
        {
            if (!document.RootElement.TryGetProperty("roots", out var roots)) throw new ImportException(ImportFailure.Unreadable, "Bookmarks");
            void Walk(JsonElement node)
            {
                if (node.TryGetProperty("type", out var type) && type.GetString() == "url" && node.TryGetProperty("url", out var url) && url.GetString() is { } link)
                {
                    var added = node.TryGetProperty("date_added", out var d) && long.TryParse(d.GetString(), out var raw) ? Date(raw) : null;
                    var title = node.TryGetProperty("name", out var n) ? n.GetString() : null;
                    if (ImportMerge.Visit(link, title, added ?? DateTimeOffset.Now) is { } visit) result.Add(visit);
                }
                if (node.TryGetProperty("children", out var children) && children.ValueKind == JsonValueKind.Array)
                    foreach (var child in children.EnumerateArray()) Walk(child);
            }
            foreach (var key in new[] { "bookmark_bar", "other", "synced" }) if (roots.TryGetProperty(key, out var root)) Walk(root);
        }
        return result;
    }
}

/// <summary>Firefox and browsers built on it (Zen).</summary>
public static class GeckoReader
{
    public static DateTimeOffset? Date(long microseconds) => microseconds > 0 ? DateTimeOffset.FromUnixTimeMilliseconds(microseconds / 1000) : null;

    public static List<ImportProfile> Profiles(ImportBrowser browser, string root)
    {
        string text;
        try { text = File.ReadAllText(System.IO.Path.Combine(root, "profiles.ini")); } catch (Exception e) when (e is IOException or UnauthorizedAccessException) { return []; }
        return ParseProfiles(text).Select(entry =>
        {
            var path = entry.Relative ? System.IO.Path.Combine(root, entry.Path.Replace('/', '\\')) : entry.Path;
            return File.Exists(System.IO.Path.Combine(path, "places.sqlite")) ? new ImportProfile(browser, entry.Name, path) : null;
        }).OfType<ImportProfile>().ToList();
    }

    /// <summary>Profile sections of profiles.ini, the default profile first.</summary>
    public static List<(string Name, string Path, bool Relative)> ParseProfiles(string text)
    {
        var sections = new List<Dictionary<string, string>>();
        Dictionary<string, string>? current = null;
        foreach (var raw in text.Split('\n'))
        {
            var line = raw.Trim();
            if (line.StartsWith('['))
            {
                if (current is not null) sections.Add(current);
                current = line.StartsWith("[Profile", StringComparison.Ordinal) ? [] : null;
            }
            else if (current is not null && line.IndexOf('=') is var eq and > 0) current[line[..eq]] = line[(eq + 1)..];
        }
        if (current is not null) sections.Add(current);
        var found = sections.Where(s => s.ContainsKey("Path")).ToList();
        var ordered = found.Where(s => s.GetValueOrDefault("Default") == "1").Concat(found.Where(s => s.GetValueOrDefault("Default") != "1"));
        return ordered.Select(s => (s.GetValueOrDefault("Name") ?? s["Path"], s["Path"], s.GetValueOrDefault("IsRelative") != "0")).ToList();
    }

    public static List<Visit> History(string profile, int limit = 3000)
    {
        using var db = new SQLiteSnapshot(System.IO.Path.Combine(profile, "places.sqlite"));
        return db.Rows("SELECT url, title, last_visit_date FROM moz_places WHERE last_visit_date IS NOT NULL AND hidden = 0 ORDER BY last_visit_date DESC LIMIT $p1", limit)
            .Select(row => SQLiteSnapshot.Text(row[0]) is { } url && SQLiteSnapshot.Int(row[2]) is { } time && Date(time) is { } date ? ImportMerge.Visit(url, SQLiteSnapshot.Text(row[1]), date) : null)
            .OfType<Visit>().ToList();
    }

    public static List<Visit> Bookmarks(string profile)
    {
        using var db = new SQLiteSnapshot(System.IO.Path.Combine(profile, "places.sqlite"));
        return db.Rows("SELECT p.url, b.title, b.dateAdded FROM moz_bookmarks b JOIN moz_places p ON p.id = b.fk WHERE b.type = 1 ORDER BY b.parent, b.position")
            .Select(row => SQLiteSnapshot.Text(row[0]) is { } url ? ImportMerge.Visit(url, SQLiteSnapshot.Text(row[1]), SQLiteSnapshot.Int(row[2]) is { } t && Date(t) is { } d ? d : DateTimeOffset.Now) : null)
            .OfType<Visit>().ToList();
    }
}

/// <summary>Exported files: Netscape bookmark HTML (every browser exports it) and Safari-style History.json.</summary>
public static partial class ExportReader
{
    [GeneratedRegex("<A\\s+([^>]*)>(.*?)</A>", RegexOptions.IgnoreCase | RegexOptions.Singleline)] private static partial Regex Anchor();
    [GeneratedRegex("HREF=\"([^\"]*)\"", RegexOptions.IgnoreCase)] private static partial Regex Href();
    [GeneratedRegex("ADD_DATE=\"(\\d+)\"", RegexOptions.IgnoreCase)] private static partial Regex Added();
    [GeneratedRegex("<[^>]+>")] private static partial Regex Tag();

    public static List<Visit> Bookmarks(string html) => Anchor().Matches(html).Select(match =>
    {
        var attributes = match.Groups[1].Value;
        var link = Href().Match(attributes);
        if (!link.Success) return null;
        var added = Added().Match(attributes);
        var date = added.Success && long.TryParse(added.Groups[1].Value, out var seconds) ? DateTimeOffset.FromUnixTimeSeconds(seconds) : DateTimeOffset.Now;
        return ImportMerge.Visit(Unescape(link.Groups[1].Value), Unescape(match.Groups[2].Value), date);
    }).OfType<Visit>().ToList();

    public static List<Visit> History(byte[] json)
    {
        try
        {
            using var document = JsonDocument.Parse(json);
            if (!document.RootElement.TryGetProperty("history", out var items)) throw new ImportException(ImportFailure.Unreadable, "History.json");
            return items.EnumerateArray().Select(item =>
            {
                if (!item.TryGetProperty("url", out var url) || url.GetString() is not { } link) return null;
                var usec = item.TryGetProperty("time_usec", out var t) && t.TryGetInt64(out var v) ? v : 0;
                var title = item.TryGetProperty("title", out var n) ? n.GetString() : null;
                return ImportMerge.Visit(link, title, usec > 0 ? DateTimeOffset.FromUnixTimeMilliseconds(usec / 1000) : DateTimeOffset.Now);
            }).OfType<Visit>().ToList();
        }
        catch (JsonException) { throw new ImportException(ImportFailure.Unreadable, "History.json"); }
    }

    static string Unescape(string text)
    {
        var result = Tag().Replace(text, "");
        foreach (var (entity, plain) in new[] { ("&quot;", "\""), ("&#39;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&") }) result = result.Replace(entity, plain);
        return result.Trim();
    }

    /// <summary>Reads an unpacked export folder or a single exported file.</summary>
    public static ImportBundle Read(string path)
    {
        var bundle = new ImportBundle();
        var files = Directory.Exists(path) ? Directory.EnumerateFiles(path, "*", SearchOption.AllDirectories) : [path];
        foreach (var file in files)
        {
            var name = System.IO.Path.GetFileName(file).ToLowerInvariant();
            if (name.EndsWith(".html") || name.EndsWith(".htm"))
            {
                var text = File.ReadAllText(file);
                if (text.Contains("NETSCAPE-Bookmark-file", StringComparison.OrdinalIgnoreCase)) bundle.Bookmarks.AddRange(Bookmarks(text));
            }
            else if (name.EndsWith(".json") && name.Contains("history"))
            {
                try { bundle.History.AddRange(History(File.ReadAllBytes(file))); } catch (ImportException) { }
            }
        }
        if (bundle.Bookmarks.Count == 0 && bundle.History.Count == 0) throw new ImportException(ImportFailure.Unreadable, System.IO.Path.GetFileName(path));
        return bundle;
    }
}

public static class ImportReader
{
    /// <summary>A kind that fails is skipped and reported, so one locked file does not cancel the rest.</summary>
    public static (ImportBundle Bundle, Dictionary<ImportKind, ImportException> Failures) Read(ImportProfile profile, ISet<ImportKind> kinds)
    {
        var bundle = new ImportBundle();
        var failures = new Dictionary<ImportKind, ImportException>();
        void Attempt(ImportKind kind, Action work)
        {
            if (!kinds.Contains(kind)) return;
            try { work(); }
            catch (ImportException e) { failures[kind] = e; }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException or SqliteException or JsonException) { failures[kind] = new ImportException(ImportFailure.Unreadable, e.Message); }
        }
        if (profile.Browser.Family == BrowserFamily.Chromium)
        {
            Attempt(ImportKind.History, () => bundle.History = ChromiumReader.History(profile.Path));
            Attempt(ImportKind.Bookmarks, () => bundle.Bookmarks = ChromiumReader.Bookmarks(profile.Path));
        }
        else
        {
            Attempt(ImportKind.History, () => bundle.History = GeckoReader.History(profile.Path));
            Attempt(ImportKind.Bookmarks, () => bundle.Bookmarks = GeckoReader.Bookmarks(profile.Path));
        }
        return (bundle, failures);
    }
}

public static class ImportDiscovery
{
    public static string LocalAppData => Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
    public static string RoamingAppData => Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);

    /// <summary>Profiles with readable data, in the order of <see cref="ImportBrowser.All"/>.</summary>
    public static List<ImportProfile> Profiles(string? local = null, string? roaming = null)
    {
        var result = new List<ImportProfile>();
        foreach (var browser in ImportBrowser.All)
        {
            if (browser.Root(local ?? LocalAppData, roaming ?? RoamingAppData) is not { } root) continue;
            result.AddRange(browser.Family == BrowserFamily.Chromium ? ChromiumReader.Profiles(browser, root) : GeckoReader.Profiles(browser, root));
        }
        return result;
    }

    /// <summary>Discovers profiles in a folder the user picked: a data folder, one profile folder, or a Firefox profile.</summary>
    public static List<ImportProfile> ProfilesIn(string folder, string? local = null, string? roaming = null)
    {
        bool Has(string name) => File.Exists(System.IO.Path.Combine(folder, name));
        var full = System.IO.Path.GetFullPath(folder).TrimEnd('\\', '/');
        var known = ImportBrowser.All.Select(b => (b, root: b.Root(local ?? LocalAppData, roaming ?? RoamingAppData)))
            .Where(x => x.root is not null && (full.Equals(x.root, StringComparison.OrdinalIgnoreCase) || full.StartsWith(x.root + "\\", StringComparison.OrdinalIgnoreCase)))
            .OrderByDescending(x => x.root!.Length).Select(x => x.b).FirstOrDefault();
        var family = known?.Family ?? (Has("places.sqlite") || Has("profiles.ini") ? BrowserFamily.Gecko : BrowserFamily.Chromium);
        var browser = known ?? ImportBrowser.All.First(b => b.Id == (family == BrowserFamily.Chromium ? "chromium" : "firefox"));
        if (family == BrowserFamily.Gecko && !Has("places.sqlite")) return GeckoReader.Profiles(browser, folder);
        if (family == BrowserFamily.Chromium && !Has("History") && !Has("Bookmarks")) return ChromiumReader.Profiles(browser, folder);
        return [new ImportProfile(browser, System.IO.Path.GetFileName(full), folder)];
    }
}

public static class ImportMerge
{
    public static (List<Visit> Merged, int Added) History(IEnumerable<Visit> existing, IEnumerable<Visit> imported, int limit = 3000)
    {
        var current = existing.ToList();
        var seen = new HashSet<string>(current.Select(v => v.Url));
        var fresh = imported.OrderByDescending(v => v.Date).Where(v => seen.Add(v.Url)).ToList();
        var merged = current.Concat(fresh).OrderByDescending(v => v.Date).Take(limit).ToList();
        var kept = merged.Select(v => v.Id).ToHashSet();
        return (merged, fresh.Count(v => kept.Contains(v.Id)));
    }

    public static (List<Visit> Merged, int Added) Bookmarks(IEnumerable<Visit> existing, IEnumerable<Visit> imported)
    {
        var current = existing.ToList();
        var seen = new HashSet<string>(current.Select(v => v.Url));
        var fresh = imported.Where(v => seen.Add(v.Url)).ToList();
        return ([.. current, .. fresh], fresh.Count);
    }

    public static string? WebUrl(string text) =>
        Uri.TryCreate(text, UriKind.Absolute, out var url) && (url.Scheme == "https" || url.Scheme == "http") && url.Host.Length > 0 ? text : null;

    public static Visit? Visit(string text, string? title, DateTimeOffset date)
    {
        if (WebUrl(text) is not { } url) return null;
        return new Visit(url, string.IsNullOrEmpty(title) ? AddressParser.Host(url) ?? text : title) { Date = date };
    }
}
