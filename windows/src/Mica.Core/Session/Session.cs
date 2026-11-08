namespace Mica.Core;

public sealed class SavedTab
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string? Url { get; set; }
    public string Title { get; set; } = "";
    public bool Pinned { get; set; }
    public SavedTab Copy() => new() { Id = Id, Url = Url, Title = Title, Pinned = Pinned };
}

public sealed class SavedWindow
{
    public List<SavedTab> Tabs { get; set; } = [];
    public Guid? Selected { get; set; }
}

public sealed class Session
{
    public int Version { get; set; } = 1;
    public List<SavedWindow> Windows { get; set; } = [];

    /// <summary>Drops unknown versions, unsafe addresses and repeated ids; pinned tabs first.</summary>
    public Session Validated()
    {
        if (Version != 1) return new Session();
        var ids = new HashSet<Guid>();
        var result = new Session();
        foreach (var window in Windows.Take(20))
        {
            var tabs = window.Tabs.Take(300).Where(tab =>
                (tab.Url is null || (IsWeb(tab.Url) && AddressParser.Navigable(tab.Url))) && ids.Add(tab.Id)).ToList();
            tabs = [.. tabs.Where(t => t.Pinned), .. tabs.Where(t => !t.Pinned)];
            result.Windows.Add(new SavedWindow { Tabs = tabs, Selected = tabs.Any(t => t.Id == window.Selected) ? window.Selected : tabs.FirstOrDefault()?.Id });
        }
        return result;
    }

    static bool IsWeb(string url) => Uri.TryCreate(url, UriKind.Absolute, out var u) && (u.Scheme == "http" || u.Scheme == "https");
}

public enum TabPhase { Fresh, Restored, Live, Terminated }

public static class TabPolicy
{
    public static bool ShouldLoadOnRestore(SavedTab tab, Guid? selected, Preferences preferences) =>
        tab.Id == selected || !preferences.LazyRestore || preferences.EagerHosts.Contains(AddressParser.Host(tab.Url)?.ToLowerInvariant() ?? "");

    public static List<SavedTab> Moving(IReadOnlyList<SavedTab> tabs, Guid id, Guid before)
    {
        var source = tabs.FirstOrDefault(t => t.Id == id);
        var destination = tabs.FirstOrDefault(t => t.Id == before);
        if (source is null || destination is null || source.Id == destination.Id || source.Pinned != destination.Pinned) return [.. tabs];
        var result = tabs.Where(t => t.Id != id).ToList();
        var index = result.FindIndex(t => t.Id == before);
        if (index >= 0) result.Insert(index, source);
        return result;
    }
}
