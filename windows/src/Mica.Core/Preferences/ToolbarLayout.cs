namespace Mica.Core;

/// <summary>Controls the user can place in the top bar or at the bottom of the sidebar.</summary>
public enum ToolbarControl { Sidebar, Back, Forward, Reload, NewTab, Bookmarks, History, Downloads, Extensions, Incognito, Settings, Profile }

/// <summary>Zones of the top bar run from the window edge to the address field.</summary>
public enum ToolbarZone { Leading, LeadingInner, TrailingInner, Trailing, Sidebar, Hidden }

/// <summary>Top bar arrangement. The address field is always centred in the window; only its width is configurable.</summary>
public sealed class ToolbarLayout
{
    public static readonly ToolbarControl[] AllControls = Enum.GetValues<ToolbarControl>();
    static readonly HashSet<ToolbarControl> Legacy = [ToolbarControl.Sidebar, ToolbarControl.Back, ToolbarControl.Forward, ToolbarControl.Reload, ToolbarControl.NewTab, ToolbarControl.Bookmarks, ToolbarControl.History, ToolbarControl.Downloads, ToolbarControl.Extensions, ToolbarControl.Settings];
    public const double AddressMin = 320, AddressMax = 820;

    public List<ToolbarControl> Leading { get; set; } = [ToolbarControl.Sidebar, ToolbarControl.Back, ToolbarControl.Forward, ToolbarControl.Reload];
    public List<ToolbarControl> LeadingInner { get; set; } = [];
    public List<ToolbarControl> TrailingInner { get; set; } = [];
    public List<ToolbarControl> Trailing { get; set; } = [];
    public List<ToolbarControl> Sidebar { get; set; } = [ToolbarControl.Profile, ToolbarControl.Bookmarks, ToolbarControl.History, ToolbarControl.Downloads, ToolbarControl.Extensions, ToolbarControl.Incognito, ToolbarControl.Settings];
    public double AddressWidth { get; set; } = 560;
    /// <summary>Controls this layout already accounts for; a control added later appears in its default place once.</summary>
    public List<ToolbarControl>? Known { get; set; }

    /// <summary>Applied after reading saved JSON: places controls new to this layout, removes duplicates, clamps width.</summary>
    public ToolbarLayout Migrated()
    {
        var defaults = new ToolbarLayout();
        var seen = Known ?? [.. Legacy];
        foreach (var item in AllControls)
        {
            if (seen.Contains(item) || ZoneOf(item) != ToolbarZone.Hidden) continue;
            var target = defaults.ZoneOf(item);
            if (target == ToolbarZone.Hidden) continue;
            var list = defaults.Items(target);
            var follower = list.SkipWhile(x => x != item).Skip(1).Cast<ToolbarControl?>().FirstOrDefault(x => ZoneOf(x!.Value) == target);
            Insert(item, target, follower);
        }
        Known = [.. AllControls];
        return Sanitized();
    }

    public List<ToolbarControl> Items(ToolbarZone zone) => zone switch
    {
        ToolbarZone.Leading => Leading, ToolbarZone.LeadingInner => LeadingInner, ToolbarZone.TrailingInner => TrailingInner,
        ToolbarZone.Trailing => Trailing, ToolbarZone.Sidebar => Sidebar,
        _ => AllControls.Where(c => ZoneOf(c) == ToolbarZone.Hidden).ToList(),
    };

    public ToolbarZone ZoneOf(ToolbarControl item) =>
        Leading.Contains(item) ? ToolbarZone.Leading : LeadingInner.Contains(item) ? ToolbarZone.LeadingInner :
        TrailingInner.Contains(item) ? ToolbarZone.TrailingInner : Trailing.Contains(item) ? ToolbarZone.Trailing :
        Sidebar.Contains(item) ? ToolbarZone.Sidebar : ToolbarZone.Hidden;

    public void Place(ToolbarControl item, ToolbarZone zone) { if (ZoneOf(item) != zone) Insert(item, zone); }

    /// <summary>Drag and drop: puts an item in a zone before another item of that zone, or at its end.</summary>
    public void Insert(ToolbarControl item, ToolbarZone zone, ToolbarControl? before = null)
    {
        if (item == before) return;
        foreach (var list in new[] { Leading, LeadingInner, TrailingInner, Trailing, Sidebar }) list.Remove(item);
        if (zone == ToolbarZone.Hidden) return;
        var target = Items(zone);
        var index = before is { } b ? target.IndexOf(b) : -1;
        if (index >= 0) target.Insert(index, item); else target.Add(item);
    }

    public void Shift(ToolbarControl item, int offset)
    {
        var zone = ZoneOf(item);
        if (zone == ToolbarZone.Hidden) return;
        var list = Items(zone);
        var index = list.IndexOf(item);
        var target = Math.Clamp(index + offset, 0, list.Count - 1);
        if (target == index) return;
        list.RemoveAt(index); list.Insert(target, item);
    }

    public ToolbarLayout Sanitized()
    {
        var seen = new HashSet<ToolbarControl>();
        Leading = Leading.Where(seen.Add).ToList();
        LeadingInner = LeadingInner.Where(seen.Add).ToList();
        TrailingInner = TrailingInner.Where(seen.Add).ToList();
        Trailing = Trailing.Where(seen.Add).ToList();
        Sidebar = Sidebar.Where(seen.Add).ToList();
        AddressWidth = Math.Clamp(AddressWidth, AddressMin, AddressMax);
        Known ??= [.. AllControls];
        return this;
    }

    public ToolbarLayout Clone() => new()
    {
        Leading = [.. Leading], LeadingInner = [.. LeadingInner], TrailingInner = [.. TrailingInner], Trailing = [.. Trailing],
        Sidebar = [.. Sidebar], AddressWidth = AddressWidth, Known = Known is null ? null : [.. Known],
    };

    public sealed record Resolved(List<ToolbarControl> Leading, List<ToolbarControl> LeadingInner, List<ToolbarControl> TrailingInner, List<ToolbarControl> Trailing, List<ToolbarControl> Sidebar)
    {
        public List<ToolbarControl> Items(ToolbarZone zone) => zone switch
        {
            ToolbarZone.Leading => Leading, ToolbarZone.LeadingInner => LeadingInner, ToolbarZone.TrailingInner => TrailingInner,
            ToolbarZone.Trailing => Trailing, ToolbarZone.Sidebar => Sidebar, _ => [],
        };
    }

    /// <summary>Without a sidebar its items move to the right side of the bar, and the sidebar toggle has nothing to act on.</summary>
    public Resolved Resolve(bool sidebarAvailable)
    {
        if (sidebarAvailable) return new([.. Leading], [.. LeadingInner], [.. TrailingInner], [.. Trailing], [.. Sidebar]);
        List<ToolbarControl> Drop(IEnumerable<ToolbarControl> list) => list.Where(c => c != ToolbarControl.Sidebar).ToList();
        return new(Drop(Leading), Drop(LeadingInner), Drop(TrailingInner), Drop(Trailing.Concat(Sidebar)), []);
    }
}
