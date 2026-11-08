using System.Globalization;

namespace Mica.Core;

public sealed class Visit
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Url { get; set; } = "";
    public string Title { get; set; } = "";
    public DateTimeOffset Date { get; set; } = DateTimeOffset.Now;
    public Visit() { }
    public Visit(string url, string title) { Url = url; Title = title; }
    public string? Host => AddressParser.Host(Url);
}

/// <summary>Time range for clearing browsing data, counted back from the moment of clearing.</summary>
public enum ClearPeriod { Hour, Day, Week, Month, All }

public static class ClearPeriods
{
    /// <summary>Oldest moment that is still cleared. Month is four weeks, as a calendar month has no fixed length.</summary>
    public static DateTimeOffset Start(this ClearPeriod period, DateTimeOffset now) => period switch
    {
        ClearPeriod.Hour => now.AddSeconds(-3600),
        ClearPeriod.Day => now.AddSeconds(-86_400),
        ClearPeriod.Week => now.AddSeconds(-7 * 86_400),
        ClearPeriod.Month => now.AddSeconds(-28 * 86_400),
        _ => DateTimeOffset.MinValue,
    };
}

/// <summary>What the clear-data panel removes. The last choice is remembered in preferences.</summary>
public sealed class ClearChoice
{
    public ClearPeriod Period { get; set; } = ClearPeriod.Hour;
    public bool History { get; set; } = true;
    /// <summary>Cookies, local storage, IndexedDB and service workers: sites sign out.</summary>
    public bool SiteData { get; set; }
    public bool Cache { get; set; } = true;
    /// <summary>Saved site decisions carry no date, so they are cleared for all time.</summary>
    public bool Permissions { get; set; }
    public bool IsEmpty => !History && !SiteData && !Cache && !Permissions;
    public ClearChoice Copy() => (ClearChoice)MemberwiseClone();
}

public static class HistoryOps
{
    public static List<Visit> Removing(IEnumerable<Visit> visits, DateTimeOffset since) => visits.Where(v => v.Date < since).ToList();
    public static int Count(IEnumerable<Visit> visits, DateTimeOffset since) => visits.Count(v => v.Date >= since);

    /// <summary>Visits grouped by calendar day, newest day first, keeping the order inside each day.</summary>
    public static List<(DateTime Day, List<Visit> Visits)> Days(IEnumerable<Visit> visits)
    {
        var result = new List<(DateTime Day, List<Visit> Visits)>();
        foreach (var visit in visits.OrderByDescending(v => v.Date))
        {
            var day = visit.Date.LocalDateTime.Date;
            if (result.Count > 0 && result[^1].Day == day) result[^1].Visits.Add(visit);
            else result.Add((day, [visit]));
        }
        return result;
    }

    /// <summary>Every visit to a host, www. included, so "delete all from this site" catches both spellings.</summary>
    public static List<Visit> RemovingHost(IEnumerable<Visit> visits, string host)
    {
        static string Bare(string h) => h.StartsWith("www.", StringComparison.Ordinal) ? h[4..] : h;
        var bare = Bare(host);
        return visits.Where(v => v.Host is not { } h || Bare(h) != bare).ToList();
    }

    public static string DayTitle(DateTime day, CultureInfo culture) => day.ToString("D", culture);
}
