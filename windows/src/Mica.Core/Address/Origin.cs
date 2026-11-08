namespace Mica.Core;

/// <summary>Scheme, host and non-default port of a web address, the key for site decisions.</summary>
public static class Origin
{
    public static string? Of(string? url) => Uri.TryCreate(url, UriKind.Absolute, out var uri) ? Of(uri) : null;

    public static string? Of(Uri? url)
    {
        if (url is null || !url.IsAbsoluteUri) return null;
        var scheme = url.Scheme.ToLowerInvariant();
        if (scheme != "https" && scheme != "http") return null;
        var host = url.IdnHost.ToLowerInvariant();
        if (host.Length == 0) return null;
        if (url.HostNameType == UriHostNameType.IPv6 && !host.StartsWith('[')) host = "[" + host + "]";
        var standard = scheme == "https" ? 443 : 80;
        return url.IsDefaultPort || url.Port == standard || url.Port < 0 ? $"{scheme}://{host}" : $"{scheme}://{host}:{url.Port}";
    }

    public static bool Secure(string origin) => origin.StartsWith("https://", StringComparison.Ordinal);
}
