using System.Text.RegularExpressions;

namespace Mica.Core;

public enum AddressKind { Web, External, Rejected }

/// <summary>Outcome of what the user typed. <see cref="Url"/> keeps the typed spelling, not a normalized form.</summary>
public readonly record struct AddressTarget(AddressKind Kind, string Value)
{
    public static AddressTarget Web(string url) => new(AddressKind.Web, url);
    public static AddressTarget External(string url) => new(AddressKind.External, url);
    public static AddressTarget Rejected(string reason) => new(AddressKind.Rejected, reason);
}

public static partial class AddressParser
{
    [GeneratedRegex(@"^[A-Za-z][A-Za-z0-9+.-]*:")] private static partial Regex SchemePrefix();
    [GeneratedRegex(@"^[\w.-]+:\d+(/|$)")] private static partial Regex HostPort();

    public static AddressTarget Resolve(string input, SearchEngine engine = SearchEngine.DuckDuckGo)
    {
        var text = input.Trim();
        if (text.Length == 0) return AddressTarget.Rejected("empty");
        if (SchemePrefix().IsMatch(text) && !text.StartsWith("localhost:", StringComparison.Ordinal) && !HostPort().IsMatch(text))
        {
            if (!Uri.TryCreate(text, UriKind.Absolute, out var u)) return AddressTarget.Rejected("invalid URL");
            var scheme = u.Scheme.ToLowerInvariant();
            if ((scheme == "https" || scheme == "http") && u.Host.Length > 0 && u.UserInfo.Length == 0) return AddressTarget.Web(text);
            if (scheme == "mailto" || scheme == "tel") return AddressTarget.External(text);
            return AddressTarget.Rejected("unsupported scheme");
        }
        if (!text.Any(char.IsWhiteSpace) && (text.Contains('.') || text.StartsWith("localhost", StringComparison.Ordinal) || text.StartsWith("[::1]", StringComparison.Ordinal)))
        {
            var local = text.StartsWith("localhost", StringComparison.Ordinal) || text.StartsWith("127.", StringComparison.Ordinal) || text.StartsWith("[::1]", StringComparison.Ordinal);
            var candidate = (local ? "http://" : "https://") + text;
            if (Uri.TryCreate(candidate, UriKind.Absolute, out var u) && u.Host.Length > 0 && ValidHost(text)) return AddressTarget.Web(candidate);
        }
        return AddressTarget.Web(engine.Search(text));
    }

    // Foundation refuses hosts with characters such as "<" or "{"; System.Uri accepts some of them.
    static bool ValidHost(string text)
    {
        var end = text.IndexOfAny(['/', '?', '#']);
        var authority = end < 0 ? text : text[..end];
        return !authority.Any(c => "<>{}|\\^`\"".Contains(c));
    }

    /// <summary>File types mica shows when the system hands it a file; the installer registers .html, .htm and .pdf.</summary>
    public static readonly IReadOnlySet<string> FileExtensions = new HashSet<string>(StringComparer.Ordinal) { "html", "htm", "xhtml", "xht", "pdf" };

    /// <summary>A local file the system opened in mica (Explorer, a file argument, a restored tab of such a file). Never
    /// part of <see cref="Navigable"/> and never produced by <see cref="Resolve"/>: typed text and web pages cannot reach
    /// local files. Network shares (a host other than localhost), queries and credentials are refused.</summary>
    public static bool OpenableFile(string? url)
    {
        if (url is null || !Uri.TryCreate(url, UriKind.Absolute, out var u) || !u.Scheme.Equals("file", StringComparison.OrdinalIgnoreCase)) return false;
        if (u.UserInfo.Length > 0 || u.Query.Length > 0) return false;
        if (u.Host.Length > 0 && !u.Host.Equals("localhost", StringComparison.OrdinalIgnoreCase)) return false;
        var path = u.AbsolutePath;
        if (path.Length == 0 || path.EndsWith('/')) return false;
        var extension = Path.GetExtension(Uri.UnescapeDataString(path)).TrimStart('.').ToLowerInvariant();
        return FileExtensions.Contains(extension);
    }

    public static bool Navigable(string? url, bool mainFrame = true)
    {
        if (url is null || !Uri.TryCreate(url, UriKind.Absolute, out var u)) return false;
        return u.Scheme.ToLowerInvariant() switch
        {
            "http" or "https" => u.Host.Length > 0 && u.UserInfo.Length == 0,
            "about" => url == "about:blank" || (!mainFrame && url == "about:srcdoc"),
            "blob" => true,
            _ => false,
        };
    }

    public static string? Host(string? url) => Uri.TryCreate(url, UriKind.Absolute, out var u) && u.Host.Length > 0 ? u.Host : null;
}
