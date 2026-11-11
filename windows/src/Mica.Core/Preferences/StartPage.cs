namespace Mica.Core;

public sealed class StartShortcut
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Title { get; set; } = "";
    public string Url { get; set; } = "";
}

public enum StartSection { Custom, Frequent, Bookmarks }

/// <summary>What the start page shows and in which order. Sections holds only the visible sections.</summary>
public sealed class StartPage
{
    public bool Wordmark { get; set; } = true;
    public List<StartSection> Sections { get; set; } = [StartSection.Custom, StartSection.Frequent];
    /// <summary>Tiles in a row of every start page section. Stored under its first meaning, the number of frequent sites.</summary>
    public int FrequentCount { get; set; } = 8;
    public List<StartShortcut> Shortcuts { get; set; } = [];
    public List<string> HiddenHosts { get; set; } = [];
    public static readonly int[] FrequentChoices = [4, 8, 12, 16];
    /// <summary>Frequent sites shown at most; custom sites and bookmarks are shown in full.</summary>
    public const int FrequentLimit = 16;

    public StartPage Sanitized()
    {
        Sections = Sections.Distinct().ToList();
        FrequentCount = Math.Clamp(FrequentCount, 4, 16);
        Shortcuts = Shortcuts.Where(s => AddressParser.Navigable(s.Url) && s.Url.StartsWith("http", StringComparison.Ordinal)).ToList();
        return this;
    }

    public void SetVisible(StartSection section, bool visible)
    {
        if (visible) { if (!Sections.Contains(section)) Sections.Add(section); }
        else Sections.Remove(section);
    }

    public void Shift(StartSection section, int offset)
    {
        var index = Sections.IndexOf(section);
        if (index < 0) return;
        var target = Math.Clamp(index + offset, 0, Sections.Count - 1);
        if (target == index) return;
        Sections.RemoveAt(index); Sections.Insert(target, section);
    }

    public void MoveShortcut(Guid id, Guid target)
    {
        if (id == target) return;
        var source = Shortcuts.FirstOrDefault(s => s.Id == id);
        if (source is null || !Shortcuts.Any(s => s.Id == target)) return;
        Shortcuts.Remove(source);
        Shortcuts.Insert(Shortcuts.FindIndex(s => s.Id == target), source);
    }

    public void ShiftShortcut(Guid id, int offset)
    {
        var index = Shortcuts.FindIndex(s => s.Id == id);
        if (index < 0) return;
        var target = Math.Clamp(index + offset, 0, Shortcuts.Count - 1);
        if (target == index) return;
        var item = Shortcuts[index]; Shortcuts.RemoveAt(index); Shortcuts.Insert(target, item);
    }

    /// <summary>A shortcut needs a web address; plain words would silently turn into a search, so they are rejected.</summary>
    public static string? ShortcutUrl(string input, SearchEngine engine)
    {
        var text = input.Trim();
        var target = AddressParser.Resolve(text, engine);
        return target.Kind == AddressKind.Web && !engine.IsSearch(target.Value, text) ? target.Value : null;
    }

    /// <summary>Sites by visit count, one tile per host, skipping hidden hosts, existing shortcuts and reserved test domains.</summary>
    public static List<Visit> Frequent(IEnumerable<Visit> history, ISet<string> excluding, int limit)
    {
        var counts = new Dictionary<string, (int Count, Visit Visit)>();
        foreach (var visit in history.Take(600))
        {
            var host = visit.Host?.ToLowerInvariant();
            if (host is null || excluding.Contains(host) || host.EndsWith(".invalid", StringComparison.Ordinal) || host.EndsWith(".test", StringComparison.Ordinal) || host == "localhost") continue;
            counts[host] = counts.TryGetValue(host, out var existing) ? (existing.Count + 1, existing.Visit) : (1, visit);
        }
        return counts.OrderByDescending(e => e.Value.Count).ThenBy(e => e.Key, StringComparer.Ordinal).Take(limit).Select(entry =>
        {
            var uri = new Uri(entry.Value.Visit.Url);
            return new Visit(uri.Scheme + "://" + uri.Host, "") { Id = entry.Value.Visit.Id };
        }).ToList();
    }
}
