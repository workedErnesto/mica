using System.Text;

namespace Mica.Core;

/// <summary>A file the page loaded: an image, a stylesheet, a font. Windows takes them from the DevTools resource
/// tree, macOS from WebKit's web archive.</summary>
public sealed record PageResource(string Url, string Mime, byte[] Data);

/// <summary>Turns a serialised page into one HTML file that opens in any browser without the network (macOS
/// SingleFilePage): stylesheets become <c>&lt;style&gt;</c> blocks, images, fonts and icons become <c>data:</c>
/// addresses. Scripts, event handlers, <c>&lt;base&gt;</c>, content security policies and preload hints are removed.
/// A file the page never loaded keeps its absolute address. All work is on ASCII delimiters, which keeps both
/// platforms equal character for character (vectors <c>singleFilePage</c>).</summary>
public static class SingleFilePage
{
    /// <summary>Larger files (videos, mostly) stay as links: inlined they would make the page too heavy to open.</summary>
    public const int MaxInlineBytes = 32 * 1024 * 1024;

    public static string Build(string html, string @base, IEnumerable<PageResource> resources)
    {
        var map = new Dictionary<string, PageResource>(StringComparer.Ordinal);
        foreach (var resource in resources) map.TryAdd(Key(resource.Url), resource);
        return new Builder(map, @base).Run(html);
    }

    static string Key(string url) { var hash = url.IndexOf('#'); return hash < 0 ? url : url[..hash]; }

    sealed class Attribute
    {
        public required string Name;
        public required int RawStart, RawEnd;
        public int ValueStart = -1, ValueEnd = -1;
        public bool Replaced;
        public string? Replacement;
    }

    sealed class Tag
    {
        public required string Name;
        public required int NameStart, NameEnd;
        public List<Attribute> Attributes = [];
        public bool SelfClosing, Changed;
        public int End;
        public string? Value(string s, string name)
        {
            var a = Attributes.FirstOrDefault(x => x.Name == name);
            return a is null || a.ValueStart < 0 ? null : Decode(s[a.ValueStart..a.ValueEnd]);
        }
        public bool Has(string name) => Attributes.Any(x => x.Name == name);
        public void SetIfChanged(string s, string name, string value)
        {
            var a = Attributes.FirstOrDefault(x => x.Name == name);
            if (a is null || Value(s, name) == value) return;
            a.Replaced = true; a.Replacement = value; Changed = true;
        }
    }

    sealed class Builder(Dictionary<string, PageResource> map, string @base)
    {
        readonly StringBuilder output = new();
        bool charset;

        public string Run(string s)
        {
            var n = s.Length;
            var i = 0;
            while (i < n)
            {
                if (string.CompareOrdinal(s, i, "<!--", 0, 4) == 0)
                {
                    var close = s.IndexOf("-->", i + 4, StringComparison.Ordinal);
                    var end = close < 0 ? n : close + 3;
                    output.Append(s, i, end - i); i = end; continue;
                }
                if (s[i] == '<' && i + 1 < n)
                {
                    var next = s[i + 1];
                    if (next is '!' or '?' or '/')
                    {
                        // Doctype, processing instruction or closing tag: copied as they are.
                        var gt = s.IndexOf('>', i);
                        var end = gt < 0 ? n : gt + 1;
                        output.Append(s, i, end - i); i = end; continue;
                    }
                    if (IsLetter(next) && ParseTag(s, i) is { } tag) { i = Handle(tag, s, i); continue; }
                }
                output.Append(s[i]); i++;
            }
            if (!charset)
            {
                const string meta = "<meta charset=\"utf-8\">";
                var text = output.ToString();
                if (text.StartsWith("<!DOCTYPE", StringComparison.Ordinal) || text.StartsWith("<!doctype", StringComparison.Ordinal))
                {
                    var close = text.IndexOf('>');
                    if (close >= 0) return text.Insert(close + 1, meta);
                }
                return meta + text;
            }
            return output.ToString();
        }

        /// <summary>Writes the tag (and for script and style, their content) and returns where scanning continues.</summary>
        int Handle(Tag tag, string s, int start)
        {
            switch (tag.Name)
            {
                case "script":
                    if (tag.SelfClosing) return tag.End;
                    var close = FindInsensitive(s, "</script", tag.End);
                    if (close < 0) return s.Length;
                    var gt = s.IndexOf('>', close);
                    return gt < 0 ? s.Length : gt + 1;
                case "base":
                    return tag.End;
                case "meta":
                    var equiv = tag.Value(s, "http-equiv")?.ToLowerInvariant();
                    if (tag.Has("charset") || equiv == "content-security-policy" || equiv == "content-type") return tag.End;
                    break;
                case "link":
                    var rel = (tag.Value(s, "rel") ?? "").ToLowerInvariant().Split([' ', '\t', '\n'], StringSplitOptions.RemoveEmptyEntries).ToHashSet();
                    if (rel.Overlaps(["preload", "prefetch", "modulepreload", "preconnect", "dns-prefetch", "prerender", "manifest"])) return tag.End;
                    var href = tag.Value(s, "href");
                    if (rel.Contains("stylesheet") && !rel.Contains("alternate") && href is not null && Resolve(href) is { } target && map.TryGetValue(Key(target), out var sheet))
                    {
                        var css = EscapeStyleEnd(StyleSheet(sheet, 0, [Key(target)]));
                        output.Append("<style");
                        if (tag.Attributes.FirstOrDefault(a => a.Name == "media") is { } media) output.Append(' ').Append(s, media.RawStart, media.RawEnd - media.RawStart);
                        output.Append('>').Append(css).Append("</style>");
                        return tag.End;
                    }
                    if (href is not null)
                    {
                        var icon = rel.Contains("icon") || rel.Contains("apple-touch-icon") || rel.Contains("mask-icon");
                        tag.SetIfChanged(s, "href", icon ? Media(href) : Link(href));
                    }
                    break;
            }
            RewriteAttributes(tag, s);
            Write(tag, s, start);
            if (tag.Name == "head" && !charset) { output.Append("<meta charset=\"utf-8\">"); charset = true; }
            if (tag.Name == "style" && !tag.SelfClosing)
            {
                var close = FindInsensitive(s, "</style", tag.End);
                if (close < 0) close = s.Length;
                output.Append(EscapeStyleEnd(RewriteCss(s[tag.End..close], @base, 0, [])));
                return close;
            }
            return tag.End;
        }

        void RewriteAttributes(Tag tag, string s)
        {
            var name = tag.Name;
            var hasSource = tag.Has("src");
            foreach (var attribute in tag.Attributes)
            {
                if (attribute.Replaced) continue;
                var key = attribute.Name;
                if (key.Length > 2 && key.StartsWith("on", StringComparison.Ordinal)) { attribute.Replaced = true; attribute.Replacement = null; tag.Changed = true; continue; }
                if (attribute.ValueStart < 0) continue;
                var value = Decode(s[attribute.ValueStart..attribute.ValueEnd]);
                string? next = null;
                switch (key)
                {
                    case "style": next = RewriteCss(value, @base, 0, []); break;
                    case "src": next = name is "iframe" or "frame" ? Link(value) : Media(value); break;
                    case "poster" or "data" or "background" or "xlink:href": next = Media(value); break;
                    case "href": next = name is "image" or "use" or "feimage" ? Media(value) : Link(value); break;
                    case "action" or "cite" or "formaction": next = Link(value); break;
                    case "srcset" or "sizes":
                        if (hasSource) { attribute.Replaced = true; attribute.Replacement = null; tag.Changed = true; continue; }
                        if (key == "srcset") next = Srcset(value);
                        break;
                }
                if (next is not null && next != value) { attribute.Replaced = true; attribute.Replacement = next; tag.Changed = true; }
            }
        }

        void Write(Tag tag, string s, int start)
        {
            if (!tag.Changed) { output.Append(s, start, tag.End - start); return; }
            output.Append('<').Append(s, tag.NameStart, tag.NameEnd - tag.NameStart);
            foreach (var attribute in tag.Attributes)
            {
                if (!attribute.Replaced) { output.Append(' ').Append(s, attribute.RawStart, attribute.RawEnd - attribute.RawStart); continue; }
                if (attribute.Replacement is not { } value) continue;
                output.Append(' ').Append(attribute.Name).Append("=\"").Append(Encode(value)).Append('"');
            }
            output.Append(tag.SelfClosing ? "/>" : ">");
        }

        string? Resolve(string value) => WebAddress.Resolve(value, @base);

        /// <summary>A link keeps working after saving: absolute, except an anchor inside the page.</summary>
        string Link(string value)
        {
            var trimmed = Trim(value);
            if (trimmed.Length == 0 || trimmed.StartsWith('#')) return value;
            return Resolve(trimmed) ?? value;
        }

        /// <summary>A file the page shows: inside the file when the page loaded it, otherwise its absolute address.</summary>
        string Media(string value, string? other = null)
        {
            var trimmed = Trim(value);
            if (trimmed.Length == 0 || trimmed.StartsWith('#')) return value;
            foreach (var scheme in new[] { "data:", "blob:", "javascript:", "about:" })
                if (trimmed.StartsWith(scheme, StringComparison.OrdinalIgnoreCase)) return value;
            if (WebAddress.Resolve(trimmed, other ?? @base) is not { } target) return value;
            if (map.TryGetValue(Key(target), out var resource) && resource.Data.Length <= MaxInlineBytes) return DataAddress(resource);
            return target;
        }

        string Srcset(string value)
        {
            if (value.Contains("data:", StringComparison.OrdinalIgnoreCase)) return value;
            return string.Join(", ", value.Split(',').Select(candidate =>
            {
                var parts = Trim(candidate).Split(' ', 2);
                if (parts[0].Length == 0 && parts.Length == 1) return candidate;
                return string.Join(" ", new[] { Media(parts[0]) }.Concat(parts.Skip(1)));
            }));
        }

        string StyleSheet(PageResource sheet, int depth, HashSet<string> seen)
        {
            var text = Encoding.UTF8.GetString(sheet.Data);
            if (text.StartsWith('﻿')) text = text[1..];
            return RewriteCss(text, sheet.Url, depth, seen);
        }

        /// <summary>Rewrites <c>url()</c> and <c>@import</c> of a stylesheet whose relative addresses count from
        /// <paramref name="from"/>.</summary>
        string RewriteCss(string css, string from, int depth, HashSet<string> seen)
        {
            var b = css; var n = b.Length;
            var result = new StringBuilder(n);
            var i = 0;
            while (i < n)
            {
                var c = b[i];
                if (c == '/' && i + 1 < n && b[i + 1] == '*')
                {
                    var close = b.IndexOf("*/", i + 2, StringComparison.Ordinal);
                    var end = close < 0 ? n : close + 2;
                    result.Append(b, i, end - i); i = end; continue;
                }
                if (c == '@' && StartsInsensitive(b, i, "@import") && ParseImport(b, i + 7) is { } import)
                {
                    result.Append(ImportRule(import.Reference, import.Media, from, depth, seen));
                    i = import.End; continue;
                }
                if ((c == 'u' || c == 'U') && StartsInsensitive(b, i, "url(") && (i == 0 || !IsIdent(b[i - 1])) && ParseUrl(b, i + 4) is { } url)
                {
                    var trimmed = Trim(url.Value);
                    if (trimmed.Length == 0 || trimmed.StartsWith('#') || trimmed.StartsWith("data:", StringComparison.OrdinalIgnoreCase)) result.Append(b, i, url.End - i);
                    else result.Append("url(\"").Append(CssQuote(Media(trimmed, from))).Append("\")");
                    i = url.End; continue;
                }
                if (c is '"' or '\'')
                {
                    var end = StringEnd(b, i);
                    result.Append(b, i, end - i); i = end; continue;
                }
                result.Append(c); i++;
            }
            return result.ToString();
        }

        string ImportRule(string reference, string media, string from, int depth, HashSet<string> seen)
        {
            var target = WebAddress.Resolve(Trim(reference), from);
            var lower = media.ToLowerInvariant();
            var conditional = lower.StartsWith("layer", StringComparison.Ordinal) || lower.StartsWith("supports", StringComparison.Ordinal);
            if (target is not null && depth < 4 && !conditional && !seen.Contains(Key(target)) && map.TryGetValue(Key(target), out var sheet))
            {
                var inner = StyleSheet(sheet, depth + 1, [.. seen, Key(target)]);
                return media.Length == 0 ? inner : "@media " + media + " {\n" + inner + "\n}";
            }
            return "@import url(\"" + CssQuote(target ?? reference) + "\")" + (media.Length == 0 ? "" : " " + media) + ";";
        }

        string DataAddress(PageResource resource)
        {
            var mime = Trim(resource.Mime.Split(';')[0]).ToLowerInvariant();
            if (mime.Length == 0) mime = "application/octet-stream";
            return "data:" + mime + ";base64," + Convert.ToBase64String(resource.Data);
        }
    }

    /// <summary>After <c>url(</c>: the address and the index after <c>)</c>.</summary>
    static (string Value, int End)? ParseUrl(string b, int from)
    {
        var j = from;
        while (j < b.Length && IsSpace(b[j])) j++;
        if (j >= b.Length) return null;
        if (b[j] is '"' or '\'')
        {
            var end = StringEnd(b, j);
            var value = b[(j + 1)..Math.Max(j + 1, end - 1)];
            var k = end;
            while (k < b.Length && IsSpace(b[k])) k++;
            if (k >= b.Length || b[k] != ')') return null;
            return (value, k + 1);
        }
        var close = b.IndexOf(')', j);
        return close < 0 ? null : (b[j..close], close + 1);
    }

    /// <summary>After <c>@import</c>: the address, the media list and the index after <c>;</c>.</summary>
    static (string Reference, string Media, int End)? ParseImport(string b, int from)
    {
        var j = from;
        while (j < b.Length && IsSpace(b[j])) j++;
        if (j >= b.Length) return null;
        string reference;
        if (StartsInsensitive(b, j, "url(") && ParseUrl(b, j + 4) is { } url) { reference = url.Value; j = url.End; }
        else if (b[j] is '"' or '\'') { var end = StringEnd(b, j); reference = b[(j + 1)..Math.Max(j + 1, end - 1)]; j = end; }
        else return null;
        var semicolon = b.IndexOf(';', j);
        if (semicolon < 0) semicolon = b.Length;
        return (Trim(reference), Trim(b[j..semicolon]), Math.Min(b.Length, semicolon + 1));
    }

    static Tag? ParseTag(string b, int start)
    {
        var n = b.Length;
        var j = start + 1;
        while (j < n && (IsLetter(b[j]) || IsDigit(b[j]) || b[j] is '-' or ':' or '_')) j++;
        var tag = new Tag { Name = b[(start + 1)..j].ToLowerInvariant(), NameStart = start + 1, NameEnd = j, End = n };
        while (true)
        {
            while (j < n && IsSpace(b[j])) j++;
            if (j >= n) return null;
            if (b[j] == '>') { tag.End = j + 1; return tag; }
            if (b[j] == '/')
            {
                if (j + 1 < n && b[j + 1] == '>') { tag.SelfClosing = true; tag.End = j + 2; return tag; }
                j++; continue;
            }
            var begin = j;
            j++;
            while (j < n && !IsSpace(b[j]) && b[j] != '=' && b[j] != '>' && !(b[j] == '/' && j + 1 < n && b[j + 1] == '>')) j++;
            var attribute = new Attribute { Name = b[begin..j].ToLowerInvariant(), RawStart = begin, RawEnd = j };
            var k = j;
            while (k < n && IsSpace(b[k])) k++;
            if (k < n && b[k] == '=')
            {
                k++;
                while (k < n && IsSpace(b[k])) k++;
                if (k >= n) return null;
                if (b[k] is '"' or '\'')
                {
                    var close = b.IndexOf(b[k], k + 1);
                    if (close < 0) return null;
                    attribute.ValueStart = k + 1; attribute.ValueEnd = close; j = close + 1;
                }
                else
                {
                    var e = k;
                    while (e < n && !IsSpace(b[e]) && b[e] != '>') e++;
                    attribute.ValueStart = k; attribute.ValueEnd = e; j = e;
                }
                attribute.RawEnd = j;
            }
            tag.Attributes.Add(attribute);
        }
    }

    static string Decode(string text)
    {
        if (!text.Contains('&')) return text;
        var result = new StringBuilder();
        var i = 0;
        while (i < text.Length)
        {
            var amp = text.IndexOf('&', i);
            if (amp < 0) { result.Append(text, i, text.Length - i); break; }
            result.Append(text, i, amp - i);
            var limit = Math.Min(text.Length, amp + 12);
            var semi = text.IndexOf(';', amp, limit - amp);
            if (semi < 0) { result.Append('&'); i = amp + 1; continue; }
            var entity = text[(amp + 1)..semi];
            int? scalar = entity switch { "amp" => '&', "quot" => '"', "apos" => '\'', "lt" => '<', "gt" => '>', "nbsp" => 0xA0, _ => null };
            if (scalar is null && entity.Length > 1 && entity[0] == '#')
            {
                var hex = entity[1] is 'x' or 'X';
                var digits = hex ? entity[2..] : entity[1..];
                if (digits.Length > 0 && digits.All(d => hex ? Uri.IsHexDigit(d) : char.IsAsciiDigit(d)) && uint.TryParse(digits, hex ? System.Globalization.NumberStyles.HexNumber : System.Globalization.NumberStyles.None, null, out var v) && Rune.IsValid(v))
                    scalar = (int)v;
            }
            if (scalar is { } value) { result.Append(new Rune(value).ToString()); i = semi + 1; }
            else { result.Append('&'); i = amp + 1; }
        }
        return result.ToString();
    }

    static string Encode(string value)
    {
        var result = new StringBuilder(value.Length);
        foreach (var c in value) result.Append(c switch { '&' => "&amp;", '"' => "&quot;", ' ' => "&nbsp;", _ => c.ToString() });
        return result.ToString();
    }

    static string CssQuote(string value) => value.Replace("\\", "%5C").Replace("\"", "%22").Replace("\n", "").Replace("\r", "");

    static string EscapeStyleEnd(string css)
    {
        if (FindInsensitive(css, "</style", 0) < 0) return css;
        var result = new StringBuilder();
        var i = 0;
        while (i < css.Length)
        {
            if (StartsInsensitive(css, i, "</style")) { result.Append("<\\/style"); i += 7; continue; }
            result.Append(css[i]); i++;
        }
        return result.ToString();
    }

    /// <summary>Index after a CSS string starting at <paramref name="start"/> (its quote), honouring backslash
    /// escapes; a newline ends it.</summary>
    static int StringEnd(string b, int start)
    {
        var quote = b[start];
        var j = start + 1;
        while (j < b.Length)
        {
            if (b[j] == '\\') { j += 2; continue; }
            if (b[j] == quote) return j + 1;
            if (b[j] == '\n') return j;
            j++;
        }
        return b.Length;
    }

    internal static string Trim(string s) => s.Trim(' ', '\t', '\n', '\r', '\f');

    static bool IsSpace(char c) => c is ' ' or '\t' or '\n' or '\r' or '\f';
    static bool IsLetter(char c) => c is >= 'A' and <= 'Z' or >= 'a' and <= 'z';
    static bool IsDigit(char c) => c is >= '0' and <= '9';
    static bool IsIdent(char c) => IsLetter(c) || IsDigit(c) || c is '-' or '_' || c >= 0x80;

    static bool StartsInsensitive(string b, int i, string text) => i + text.Length <= b.Length && string.Compare(b, i, text, 0, text.Length, StringComparison.OrdinalIgnoreCase) == 0;

    static int FindInsensitive(string b, string text, int from) => from > b.Length ? -1 : b.IndexOf(text, from, StringComparison.OrdinalIgnoreCase);
}
