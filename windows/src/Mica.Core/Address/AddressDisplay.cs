using System.Globalization;
using System.Text;

namespace Mica.Core;

/// <summary>How the address field shows the page address (macOS AddressStyle). The default keeps the site name only,
/// every part in the same colour.</summary>
public sealed class AddressStyle
{
    /// <summary>The whole address instead of the site name.</summary>
    public bool Full { get; set; }
    /// <summary>Subdomains, www. among them, in the quieter colour.</summary>
    public bool DimSubdomain { get; set; }
    /// <summary>Path, query and fragment in the quieter colour. Only the full address shows them.</summary>
    public bool DimPath { get; set; }
    public AddressStyle Copy() => new() { Full = Full, DimSubdomain = DimSubdomain, DimPath = DimPath };
}

/// <summary>Splits an address into the pieces the address field draws (macOS AddressDisplay). The registrable domain
/// and the port always keep the main colour. Shared vectors <c>addressDisplay</c> keep both platforms equal.</summary>
public static class AddressDisplay
{
    public readonly record struct Part(string Text, bool Dim);

    public static IReadOnlyList<Part> Parts(string address, AddressStyle style)
    {
        var result = new List<Part>();
        void Add(string text, bool dim)
        {
            if (text.Length == 0) return;
            if (result.Count > 0 && result[^1].Dim == dim) result[^1] = result[^1] with { Text = result[^1].Text + text };
            else result.Add(new Part(text, dim));
        }
        var mark = address.IndexOf("://", StringComparison.Ordinal);
        if (mark <= 0 || !address[..mark].All(c => char.IsLetterOrDigit(c) || "+-.".Contains(c))) { Add(address, false); return result; }
        var scheme = address[..mark].ToLowerInvariant();
        var afterScheme = address[(mark + 3)..];
        var authorityEnd = afterScheme.IndexOfAny(['/', '?', '#']);
        if (authorityEnd < 0) authorityEnd = afterScheme.Length;
        var authority = afterScheme[..authorityEnd];
        var rest = afterScheme[authorityEnd..];
        if (scheme == "file")
        {
            var query = rest.IndexOf('?');
            var path = Uri.UnescapeDataString(query < 0 ? rest : rest[..query]);
            if (style.Full) Add(path.Length == 0 ? "/" : path, false);
            else
            {
                var trimmed = path.EndsWith('/') && path.Length > 1 ? path[..^1] : path;
                var name = trimmed.Split('/', StringSplitOptions.RemoveEmptyEntries).LastOrDefault();
                Add(name ?? "/", false);
            }
            return result;
        }
        var at = authority.LastIndexOf('@');
        var user = at < 0 ? "" : authority[..(at + 1)];
        var hostPort = authority[(at + 1)..];
        string host, port;
        var close = hostPort.IndexOf(']');
        if (hostPort.StartsWith('[') && close >= 0) { host = hostPort[..(close + 1)]; port = hostPort[(close + 1)..]; }
        else if (hostPort.IndexOf(':') is var colon and >= 0) { host = hostPort[..colon]; port = hostPort[colon..]; }
        else { host = hostPort; port = ""; }
        if (host.Length == 0) { Add(address, false); return result; }
        var split = RegistrableStart(host);
        var sub = host[..split]; var domain = host[split..];
        if (!style.Full)
        {
            if (sub.StartsWith("www.", StringComparison.Ordinal)) sub = sub[4..];
            if (domain.StartsWith('[') && domain.EndsWith(']')) domain = domain[1..^1];
            Add(sub, style.DimSubdomain);
            Add(domain, false);
            return result;
        }
        if (rest == "/") rest = "";
        // Web addresses start at the host: the lock already tells https from http, sign-in names before @ are not shown.
        if (scheme is not ("http" or "https")) Add(scheme + "://" + user, style.DimPath);
        Add(sub, style.DimSubdomain);
        Add(domain + port, false);
        Add(DecodedText(rest), style.DimPath);
        return result;
    }

    /// <summary>Second-level labels under a country code that are sold as one public suffix.</summary>
    static readonly HashSet<string> CountrySecondLevel = ["co", "com", "net", "org", "gov", "edu", "ac", "or", "ne", "go", "gob", "mil", "ltd", "plc", "sch", "nhs", "msk", "spb"];

    /// <summary>Where the registrable domain begins: the last two labels, or three under a two-letter country code with a
    /// known second level. IP addresses and single-label hosts are kept whole.</summary>
    static int RegistrableStart(string host)
    {
        if (host.StartsWith('[') || host.All(c => char.IsDigit(c) || c == '.')) return 0;
        var labels = host.Split('.');
        if (labels.Length <= 2) return 0;
        var keep = labels[^1].Length == 2 && CountrySecondLevel.Contains(labels[^2].ToLowerInvariant()) ? 3 : 2;
        if (labels.Length <= keep) return 0;
        return labels.Take(labels.Length - keep).Sum(l => l.Length + 1);
    }

    /// <summary>Percent escapes of non-ASCII text become readable letters, ASCII escapes stay as written. A run that is not
    /// valid UTF-8, or decodes to control, format or separator characters, stays encoded.</summary>
    static string DecodedText(string text)
    {
        static int Hex(char c) => c switch { >= '0' and <= '9' => c - '0', >= 'A' and <= 'F' => c - 'A' + 10, >= 'a' and <= 'f' => c - 'a' + 10, _ => -1 };
        int Escaped(int i) => i + 2 < text.Length && text[i] == '%' && Hex(text[i + 1]) is var h and >= 0 && Hex(text[i + 2]) is var l and >= 0 ? h << 4 | l : -1;
        var output = new StringBuilder();
        var strict = new UTF8Encoding(false, throwOnInvalidBytes: true);
        var index = 0;
        while (index < text.Length)
        {
            if (Escaped(index) is not (var first and >= 0x80)) { output.Append(text[index]); index++; continue; }
            var run = new List<byte>();
            var end = index;
            while (Escaped(end) is var value and >= 0x80) { run.Add((byte)value); end += 3; }
            string? decoded;
            try { decoded = strict.GetString([.. run]); } catch (ArgumentException) { decoded = null; }
            output.Append(decoded is not null && Readable(decoded) ? decoded : text[index..end]);
            index = end;
        }
        return output.ToString();
    }

    static bool Readable(string text)
    {
        for (var i = 0; i < text.Length; i++)
        {
            var category = char.GetUnicodeCategory(text, i);
            if (category is UnicodeCategory.Control or UnicodeCategory.Format or UnicodeCategory.SpaceSeparator or UnicodeCategory.LineSeparator
                or UnicodeCategory.ParagraphSeparator or UnicodeCategory.PrivateUse or UnicodeCategory.Surrogate or UnicodeCategory.OtherNotAssigned) return false;
            if (char.IsHighSurrogate(text[i])) i++;
        }
        return true;
    }
}
