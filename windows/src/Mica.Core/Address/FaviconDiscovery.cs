namespace Mica.Core;

public sealed record FaviconLink(string Href, string Sizes = "", string Type = "", bool Touch = false, string Media = "")
{
    public bool Dark => Media.Contains("prefers-color-scheme") && Media.Contains("dark");
}

/// <summary>Discovers icons without running a page or using a third-party icon service.</summary>
public static class FaviconDiscovery
{
    public static string? BundledFile(string page)
    {
        if (!Uri.TryCreate(page, UriKind.Absolute, out var url) || url.Scheme is not ("http" or "https") || !url.IsDefaultPort) return null;
        var host = url.IdnHost.ToLowerInvariant();
        if (host.StartsWith("www.", StringComparison.Ordinal)) host = host[4..];
        return FaviconCatalog.Files.GetValueOrDefault(host);
    }

    /// <summary>The provider receives only a public hostname, with no path, query, credentials or local address.</summary>
    public static string? RemoteURL(string page)
    {
        if (!Uri.TryCreate(page, UriKind.Absolute, out var url) || url.Scheme is not ("http" or "https") || !url.IsDefaultPort) return null;
        var host = url.IdnHost.ToLowerInvariant();
        if (!System.Text.RegularExpressions.Regex.IsMatch(host, @"^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z][a-z0-9-]*$")) return null;
        if (new[] { "local", "localhost", "internal", "lan", "home", "corp", "test", "invalid", "example", "onion" }.Contains(host.Split('.')[^1])) return null;
        return "https://icons.duckduckgo.com/ip3/" + host + ".ico";
    }

    public static List<FaviconLink> Links(string html, string page)
    {
        var index = 0; var @base = page; var hasBase = false;
        var links = new List<FaviconLink>();
        while (index < html.Length && links.Count < 24)
        {
            if (html.AsSpan(index).StartsWith("<!--"))
            {
                var close = html.IndexOf("-->", index + 4, StringComparison.Ordinal);
                index = close < 0 ? html.Length : close + 3; continue;
            }
            if (html[index] != '<' || index + 1 >= html.Length || !char.IsAsciiLetter(html[index + 1]) || SingleFilePage.ParseTag(html, index) is not { } tag) { index++; continue; }
            index = tag.End;
            if (tag.Name is "script" or "style" or "textarea" or "title")
            {
                var close = html.IndexOf("</" + tag.Name, index, StringComparison.OrdinalIgnoreCase);
                index = close < 0 ? html.Length : close; continue;
            }
            if (tag.Name == "base" && !hasBase && tag.Value(html, "href") is { } baseHref && WebAddress.Resolve(baseHref, page) is { } resolvedBase)
            { @base = resolvedBase; hasBase = true; }
            if (tag.Name != "link" || tag.Value(html, "href") is not { Length: > 0 } href) continue;
            var rel = (tag.Value(html, "rel") ?? "").ToLowerInvariant().Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).ToHashSet();
            var icon = rel.Contains("icon");
            if ((!icon && !rel.Contains("apple-touch-icon") && !rel.Contains("apple-touch-icon-precomposed")) || WebAddress.Resolve(href, @base) is not { } resolved) continue;
            links.Add(new(resolved, tag.Value(html, "sizes") ?? "", (tag.Value(html, "type") ?? "").ToLowerInvariant(), !icon, (tag.Value(html, "media") ?? "").ToLowerInvariant()));
        }
        return links;
    }

    public static List<string> Candidates(IEnumerable<FaviconLink> links, string page, bool fallback = true)
    {
        int Penalty(FaviconLink link)
        {
            var sizes = link.Sizes.ToLowerInvariant();
            var edge = sizes.Contains("any") ? 256 : sizes.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).Select(x => int.TryParse(x.Split('x')[0], out var n) ? (int?)n : null).Max() ?? (link.Touch ? 180 : 32);
            var vector = link.Type.Contains("svg") || link.Href.ToLowerInvariant().Split('?')[0].EndsWith(".svg") || link.Href.StartsWith("data:image/svg", StringComparison.OrdinalIgnoreCase);
            return (edge >= 32 ? edge - 32 : 1000 + 32 - edge) + (vector ? 60 : 0) + (link.Touch ? 20 : 0);
        }
        var result = links.OrderBy(Penalty).Where(l => Uri.TryCreate(l.Href, UriKind.Absolute, out var u) && u.Scheme is "http" or "https" or "data").Select(l => l.Href).Distinct(StringComparer.Ordinal).Take(4).ToList();
        if (fallback && WebAddress.Resolve("/favicon.ico", page) is { } resolved)
        {
            var icon = System.Text.RegularExpressions.Regex.Replace(resolved, @"^(https?://)[^/]*@", "$1");
            if (Uri.TryCreate(icon, UriKind.Absolute, out var uri) && uri.Scheme is "http" or "https" && !result.Contains(icon)) result.Add(icon);
        }
        return result;
    }
}
