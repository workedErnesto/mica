using System.Text.Json;
using System.Text.RegularExpressions;

namespace Mica.App;

/// <summary>WebView2 adapter for the shared compiler's WebKit-compatible network subset.
/// Rules are immutable and indexed by request host. An exception wins over a block, like the two ordered WK lists.</summary>
public sealed class ContentRules
{
    sealed class Rule
    {
        public required string Expression;
        public RegexOptions Options;
        public string Literal = "";
        Regex? urlRegex;
        public string[] Include = [], Exclude = [], Parties = [], Contexts = [];
        public int Types;
        public bool Allow;
        public bool Matches(string url, string top, string type, bool thirdParty, bool mainFrame)
        {
            if (Literal.Length > 0 && url.IndexOf(Literal, Options.HasFlag(RegexOptions.IgnoreCase) ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal) < 0) return false;
            if (Types != 0 && (Types & TypeBit(type)) == 0) return false;
            if (Contexts.Contains("child-frame") && mainFrame) return false;
            if (Parties.Contains("third-party") && !thirdParty || Parties.Contains("first-party") && thirdParty) return false;
            if (Include.Length > 0 && !Include.Any(d => Domain(top, d))) return false;
            if (Exclude.Any(d => Domain(top, d))) return false;
            try { return (urlRegex ??= new Regex(Expression, Options, TimeSpan.FromMilliseconds(20))).IsMatch(url); } catch (RegexMatchTimeoutException) { return false; }
        }
    }
    // Only a mandatory top-level literal is safe as a prefilter. Groups, classes and optional atoms break a run;
    // alternatives disable the optimization entirely. This avoids retaining thousands of unused regex interpreters.
    static string RequiredLiteral(string expression)
    {
        if (expression.Contains('|')) return "";
        var run = new System.Text.StringBuilder(); string best = ""; int depth = 0; bool characterClass = false;
        void Flush() { if (run.Length > best.Length) best = run.ToString(); run.Clear(); }
        for (int i = 0; i < expression.Length; i++)
        {
            char c = expression[i];
            if (c == '\\' && i + 1 < expression.Length) {
                char next = expression[++i];
                if (depth == 0 && !characterClass && !char.IsLetterOrDigit(next)) run.Append(next); else Flush();
                continue;
            }
            if (characterClass) { if (c == ']') characterClass = false; continue; }
            if (c == '[') { Flush(); characterClass = true; continue; }
            if (c == '(') { Flush(); depth++; continue; }
            if (c == ')') { depth--; continue; }
            if (depth > 0) continue;
            if (c is '*' or '?' or '+' or '{') { if (run.Length > 0) run.Length--; Flush(); continue; }
            if (c is '.' or '^' or '$' or '}') { Flush(); continue; }
            run.Append(c);
        }
        Flush(); return best.Length >= 3 ? best : "";
    }
    readonly Dictionary<string, List<Rule>> byHost = new(StringComparer.OrdinalIgnoreCase);
    readonly List<Rule> general = [];
    readonly HashSet<string> suffixes = new(StringComparer.OrdinalIgnoreCase);
    readonly HashSet<string> wildcardSuffixes = new(StringComparer.OrdinalIgnoreCase);
    readonly HashSet<string> suffixExceptions = new(StringComparer.OrdinalIgnoreCase);
    public int Count { get; private set; }
    static int TypeBit(string type) => type switch {
        "document" => 1, "script" => 2, "image" => 4, "style-sheet" => 8, "font" => 16, "media" => 32,
        "fetch" => 64, "websocket" => 128, "ping" => 256, "other" => 512, "raw" => 1024, "svg-document" => 2048, _ => 4096
    };
    static string[] Strings(JsonElement value, string key) => value.TryGetProperty(key, out var a) ? a.EnumerateArray().Select(e => e.GetString()!).ToArray() : [];
    public static bool Domain(string host, string pattern)
    {
        var domain = pattern.TrimStart('*');
        return host.Equals(domain, StringComparison.OrdinalIgnoreCase) || host.EndsWith("." + domain, StringComparison.OrdinalIgnoreCase);
    }
    ContentRules(string publicSuffixList)
    {
        foreach (var raw in publicSuffixList.Split('\n'))
        {
            var line = raw.Trim();
            if (line.Length == 0 || line.StartsWith("//")) continue;
            if (line.StartsWith('!')) suffixExceptions.Add(line[1..]);
            else if (line.StartsWith("*.")) wildcardSuffixes.Add(line[2..]);
            else suffixes.Add(line);
        }
    }
    public ContentRules(JsonElement rules, string publicSuffixList) : this(publicSuffixList)
    {
        foreach (var item in rules.EnumerateArray()) Add(item);
    }
    public ContentRules(ref Utf8JsonReader reader, string publicSuffixList) : this(publicSuffixList)
    {
        if (reader.TokenType != JsonTokenType.StartArray) throw new JsonException("Expected network rule array");
        while (reader.Read() && reader.TokenType != JsonTokenType.EndArray) {
            using var item = JsonDocument.ParseValue(ref reader);
            Add(item.RootElement);
        }
    }
    void Add(JsonElement item)
    {
            var t = item.GetProperty("trigger");
            var regex = t.GetProperty("url-filter").GetString()!;
            var rule = new Rule {
                Expression = regex, Literal = RequiredLiteral(regex), Options = t.TryGetProperty("url-filter-is-case-sensitive", out var sensitive) && sensitive.GetBoolean() ? RegexOptions.CultureInvariant : RegexOptions.IgnoreCase | RegexOptions.CultureInvariant,
                Include = Strings(t, "if-domain"), Exclude = Strings(t, "unless-domain"), Types = Strings(t, "resource-type").Aggregate(0, (mask, type) => mask | TypeBit(type)),
                Parties = Strings(t, "load-type"), Contexts = Strings(t, "load-context"),
                Allow = item.GetProperty("action").GetProperty("type").GetString() == "ignore-previous-rules"
            };
            if (item.TryGetProperty("host", out var h) && h.GetString() is { Length: > 0 } host)
            {
                if (!byHost.TryGetValue(host, out var group)) byHost[host] = group = [];
                group.Add(rule);
            }
            else general.Add(rule);
            Count++;
    }

    string Site(string host)
    {
        if (System.Net.IPAddress.TryParse(host, out _)) return host;
        var labels = host.Split('.');
        var length = 1;
        for (var i = 0; i < labels.Length; i++)
        {
            var suffix = string.Join('.', labels.Skip(i));
            if (suffixExceptions.Contains(suffix)) { length = labels.Length - i - 1; break; }
            if (suffixes.Contains(suffix)) length = Math.Max(length, labels.Length - i);
            if (i > 0 && wildcardSuffixes.Contains(suffix)) length = Math.Max(length, labels.Length - i + 1);
        }
        return string.Join('.', labels.Skip(Math.Max(0, labels.Length - length - 1)));
    }
    public bool ShouldBlock(string address, string topAddress, string type, bool mainFrame, IEnumerable<string> exceptions)
    {
        if (!Uri.TryCreate(address, UriKind.Absolute, out var request) || !Uri.TryCreate(topAddress, UriKind.Absolute, out var top)) return false;
        if (request.Scheme is not ("http" or "https" or "ws" or "wss")) return false;
        if (exceptions.Any(d => Domain(top.IdnHost, d))) return false;
        var thirdParty = !Site(request.IdnHost).Equals(Site(top.IdnHost), StringComparison.OrdinalIgnoreCase);
        bool blocked = false;
        bool Visit(IEnumerable<Rule> rules)
        {
            foreach (var rule in rules)
                if (rule.Matches(address, top.IdnHost, type, thirdParty, mainFrame)) { if (rule.Allow) return true; blocked = true; }
            return false;
        }
        if (Visit(general)) return false;
        var host = request.IdnHost;
        while (true)
        {
            if (byHost.TryGetValue(host, out var group) && Visit(group)) return false;
            var dot = host.IndexOf('.'); if (dot < 0) break; host = host[(dot + 1)..];
        }
        return blocked;
    }
}
