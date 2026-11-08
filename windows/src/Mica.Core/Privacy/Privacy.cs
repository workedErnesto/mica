using System.Text.RegularExpressions;

namespace Mica.Core;

public enum SiteCapability { Camera, Microphone, Notifications, Location }

public static class SiteCapabilities
{
    /// <summary>Shown in settings on Windows. Location exists only here: WebView2 asks for it, WebKit on macOS does not expose it.</summary>
    public static readonly SiteCapability[] Windows = [SiteCapability.Camera, SiteCapability.Microphone, SiteCapability.Notifications, SiteCapability.Location];
    /// <summary>Capabilities that capture devices and are stopped when access is revoked.</summary>
    public static bool Captures(this SiteCapability c) => c is SiteCapability.Camera or SiteCapability.Microphone;
}

public enum Decision { Ask, Allow, Deny }

public sealed class SitePermission
{
    public string Origin { get; set; } = "";
    public SiteCapability Capability { get; set; }
    public Decision Decision { get; set; }
    public string Id => Origin + ":" + Capability.ToString().ToLowerInvariant();
}

/// <summary>Third-party domain blocking. macOS compiles the same list into a WebKit content rule list; WebView2 has no
/// rule compiler, so requests are matched here against a suffix set (one hash lookup per label of the host).</summary>
public sealed partial class DomainBlocker
{
    public static readonly string[] Builtin = ["doubleclick.net", "googlesyndication.com", "google-analytics.com", "googletagmanager.com", "adservice.google.com", "adsystem.com", "amazon-adsystem.com", "adsrvr.org", "adnxs.com", "criteo.com", "criteo.net", "taboola.com", "outbrain.com", "scorecardresearch.com", "quantserve.com", "hotjar.com", "clarity.ms", "segment.io", "segment.com", "mixpanel.com", "amplitude.com", "connect.facebook.net", "analytics.tiktok.com", "bat.bing.com", "ads-twitter.com", "static.ads-twitter.com", "snap.licdn.com"];
    readonly HashSet<string> domains;
    readonly HashSet<string> exceptions;

    public DomainBlocker(IEnumerable<string> domains, IEnumerable<string> exceptions)
    {
        this.domains = new HashSet<string>(domains, StringComparer.OrdinalIgnoreCase);
        this.exceptions = new HashSet<string>(exceptions, StringComparer.OrdinalIgnoreCase);
    }

    public int Count => domains.Count;

    [GeneratedRegex(@"^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z](?:[a-z0-9-]{0,61}[a-z0-9])?$")] private static partial Regex DomainShape();

    /// <summary>Same validation as macOS: at most 20000 lines of plain domains, comments with #.</summary>
    public static List<string> ParseDomains(string text)
    {
        var lines = text.Split('\n').Select(l => l.Trim().ToLowerInvariant()).Where(l => l.Length > 0 && !l.StartsWith('#')).ToList();
        if (lines.Count > 20000 || lines.Any(l => l.Length > 253 || !DomainShape().IsMatch(l))) throw new FormatException("blocklist is damaged");
        return lines.Distinct().OrderBy(l => l, StringComparer.Ordinal).ToList();
    }

    /// <summary>Blocks a third-party request whose host is a listed domain or its subdomain, unless the page's host is an exception.</summary>
    public bool ShouldBlock(string requestUrl, string? topUrl)
    {
        if (!Uri.TryCreate(requestUrl, UriKind.Absolute, out var request) || (request.Scheme != "http" && request.Scheme != "https")) return false;
        var top = AddressParser.Host(topUrl)?.ToLowerInvariant();
        if (top is not null && exceptions.Contains(top)) return false;
        var host = request.Host.ToLowerInvariant();
        if (top is not null && SameSite(host, top)) return false;
        for (var label = host; ; )
        {
            if (domains.Contains(label)) return true;
            var dot = label.IndexOf('.');
            if (dot < 0) return false;
            label = label[(dot + 1)..];
        }
    }

    /// <summary>First-party check without a public suffix list: one host is the other or its subdomain, or both share the
    /// last two labels. WebKit's third-party rule uses the registrable domain; differences are documented in docs/PARITY.md.</summary>
    public static bool SameSite(string a, string b)
    {
        if (a == b || a.EndsWith("." + b, StringComparison.Ordinal) || b.EndsWith("." + a, StringComparison.Ordinal)) return true;
        static string Tail(string h) { var parts = h.Split('.'); return parts.Length <= 2 ? h : string.Join('.', parts[^2..]); }
        return Tail(a) == Tail(b);
    }
}

/// <summary>State reported to the page as Notification.permission.</summary>
public enum NotificationState { Granted, Denied, Default }

public static class NotificationPolicy
{
    public static NotificationState State(string? origin, bool privateMode, IEnumerable<SitePermission> permissions)
    {
        if (origin is null || !Origin.Secure(origin) || privateMode) return NotificationState.Denied;
        return permissions.FirstOrDefault(p => p.Origin == origin && p.Capability == SiteCapability.Notifications)?.Decision switch
        {
            Decision.Allow => NotificationState.Granted,
            Decision.Deny => NotificationState.Denied,
            _ => NotificationState.Default,
        };
    }

    public static bool MayAsk(string? origin, bool privateMode, bool selected, bool userGesture, bool requestsAllowed) =>
        origin is not null && Origin.Secure(origin) && !privateMode && selected && userGesture && requestsAllowed;
}

/// <summary>A notification a page asked to show, validated before it reaches the system.</summary>
public sealed record WebNotification(string Id, string Title, string Body = "", string Tag = "", bool Silent = false)
{
    public const int TitleLimit = 200, BodyLimit = 1000, TagLimit = 200;

    public static WebNotification? Parse(string? id, string? title, string? body, string? tag, bool silent)
    {
        if (id is null || id.Length == 0 || id.Length > 64 || !id.All(c => char.IsLetterOrDigit(c) || c == '-') || title is null) return null;
        var cleanTitle = Clean(title, TitleLimit);
        if (cleanTitle.Length == 0) return null;
        return new WebNotification(id, cleanTitle, Clean(body ?? "", BodyLimit), Clean(tag ?? "", TagLimit), silent);
    }

    public static string Clean(string text, int limit)
    {
        var kept = new string(text.Where(c => !char.IsControl(c) || c == '\n').ToArray()).Trim();
        var info = new System.Globalization.StringInfo(kept);
        return info.LengthInTextElements <= limit ? kept : info.SubstringByTextElements(0, limit);
    }

    /// <summary>Notifications with the same tag from one origin replace each other, as the standard asks.</summary>
    public static string Identifier(string origin, Guid tab, WebNotification n) =>
        n.Tag.Length == 0 ? $"{origin}|{tab:D}|{n.Id}" : $"{origin}|tag|{n.Tag}";
}
