using System.Text;

namespace Mica.Core;

/// <summary>Formats a page can be saved in (macOS PageFormat). PDF is paginated by the print engine with the page's
/// print styles; PNG and JPEG picture the whole page as on screen; HTML is one file with the page's images, styles
/// and fonts inside it.</summary>
public enum PageFormat { Pdf, Png, Jpeg, Html }

public static class PageFormats
{
    public static readonly PageFormat[] All = [PageFormat.Pdf, PageFormat.Png, PageFormat.Jpeg, PageFormat.Html];
    public static string Extension(this PageFormat format) => format switch { PageFormat.Pdf => "pdf", PageFormat.Png => "png", PageFormat.Jpeg => "jpg", _ => "html" };
    public static PageFormat? Parse(string? value) => value switch { "pdf" => PageFormat.Pdf, "png" => PageFormat.Png, "jpeg" => PageFormat.Jpeg, "html" => PageFormat.Html, _ => null };
}

/// <summary>Rules for saving a page shared with macOS (vectors <c>pageFileName</c>, <c>pageImage</c>).</summary>
public static class PageExport
{
    /// <summary>The longest side of a saved picture. Chromium cannot capture past 16384 px and a bitmap of that height
    /// already takes hundreds of megabytes, so both platforms stop there and scale a longer page down.</summary>
    public const double MaxImageSide = 16384;
    public const double MaxImagePixels = 64_000_000;

    /// <summary>Pixel size of a picture of a page <paramref name="width"/> by <paramref name="height"/> points at the
    /// screen's scale, reduced to fit the limits, or null for an empty page.</summary>
    public static (int Width, int Height)? ImagePixels(double width, double height, double scale)
    {
        if (width < 1 || height < 1 || scale <= 0) return null;
        var s = Math.Min(scale, Math.Min(MaxImageSide / width, MaxImageSide / height));
        if (width * height * s * s > MaxImagePixels) s = Math.Sqrt(MaxImagePixels / (width * height));
        return (Math.Max(1, (int)Math.Floor(width * s)), Math.Max(1, (int)Math.Floor(height * s)));
    }

    static readonly HashSet<string> Reserved = ["CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"];

    /// <summary>Proposed file name: the page title, else its host without <c>www.</c>, else "page". Slashes and bars
    /// become a dash, other characters macOS or Windows refuse in a name are dropped, runs of spaces become one space;
    /// the name is cut to 120 characters.</summary>
    public static string FileName(string title, string? url, PageFormat format)
    {
        var name = Clean(title);
        if (name.Length == 0 && url is not null) name = Clean(Host(url));
        if (name.Length == 0) name = "page";
        if (Reserved.Contains(name.Split('.')[0].ToUpperInvariant())) name = "_" + name;
        return name + "." + format.Extension();
    }

    /// <summary>The name itself when the folder has no such file, otherwise "name (2).ext", "name (3).ext" and so on.</summary>
    public static string AvailableName(string name, Func<string, bool> taken)
    {
        if (!taken(name)) return name;
        var dot = name.LastIndexOf('.');
        var @base = dot > 0 ? name[..dot] : name;
        var ext = dot > 0 ? name[dot..] : "";
        for (var number = 2; number <= 9999; number++)
        {
            var candidate = @base + " (" + number + ")" + ext;
            if (!taken(candidate)) return candidate;
        }
        return @base + " (" + Guid.NewGuid().ToString("N")[..8] + ")" + ext;
    }

    static string Clean(string text)
    {
        var runes = new List<Rune>();
        var space = false;
        foreach (var rune in text.EnumerateRunes())
        {
            var category = Rune.GetUnicodeCategory(rune);
            if (category == System.Globalization.UnicodeCategory.Control || (category == System.Globalization.UnicodeCategory.Format && rune.Value != 0x200D) || Rune.IsWhiteSpace(rune))
            {
                space = runes.Count > 0;
                continue;
            }
            if (rune.IsAscii && ":*?\"<>".Contains((char)rune.Value)) continue;
            if (space) { runes.Add(new Rune(' ')); space = false; }
            runes.Add(rune.IsAscii && "/\\|".Contains((char)rune.Value) ? new Rune('-') : rune);
        }
        var result = runes.Take(120).ToList();
        while (result.Count > 0 && (result[^1].Value == ' ' || result[^1].Value == '.')) result.RemoveAt(result.Count - 1);
        while (result.Count > 0 && (result[0].Value == ' ' || result[0].Value == '.')) result.RemoveAt(0);
        var builder = new StringBuilder();
        foreach (var rune in result) builder.Append(rune.ToString());
        return builder.ToString();
    }

    /// <summary>Host of an absolute address without user, port and <c>www.</c>; plain string work so both platforms
    /// agree.</summary>
    static string Host(string url)
    {
        var start = url.IndexOf("://", StringComparison.Ordinal);
        if (start < 0) return "";
        var rest = url[(start + 3)..];
        var end = rest.IndexOfAny(['/', '?', '#']);
        if (end >= 0) rest = rest[..end];
        var at = rest.LastIndexOf('@');
        if (at >= 0) rest = rest[(at + 1)..];
        if (rest.StartsWith('[')) { var close = rest.IndexOf(']'); if (close >= 0) rest = rest[..(close + 1)]; }
        else { var colon = rest.LastIndexOf(':'); if (colon >= 0) rest = rest[..colon]; }
        var host = rest.ToLowerInvariant();
        return host.StartsWith("www.", StringComparison.Ordinal) ? host[4..] : host;
    }

    /// <summary>Runs in the page before any capture (macOS PageExport.prepareScript): images marked lazy below the
    /// visible part are asked to load now, with a three-second limit. Windows wraps it in an async function and
    /// evaluates it through DevTools with awaitPromise.</summary>
    public const string PrepareScript = """
    const lazy = Array.from(document.images).filter(i => i.loading === 'lazy' || !i.complete);
    for (const image of lazy) image.loading = 'eager';
    await Promise.race([Promise.allSettled(lazy.map(i => i.decode())), new Promise(r => setTimeout(r, 3000))]);
    return lazy.length;
    """;

    /// <summary>Serialises the page for the HTML file (macOS PageExport.serializeScript): a copy of the current
    /// document with absolute addresses, the image each <c>img</c> actually shows, form values and canvas pictures.
    /// Returns <c>{html, base, title}</c>. The live page is not changed.</summary>
    public const string SerializeScript = """
    const root = document.documentElement, copy = root.cloneNode(true);
    const live = root.querySelectorAll('*'), cloned = copy.querySelectorAll('*');
    const count = Math.min(live.length, cloned.length);
    for (let k = 0; k < count; k++) {
      const a = live[k], b = cloned[k];
      if (a instanceof HTMLImageElement) {
        const src = a.currentSrc || a.src;
        if (src) b.setAttribute('src', src);
        b.removeAttribute('srcset'); b.removeAttribute('sizes'); b.removeAttribute('loading');
      } else if (a instanceof HTMLSourceElement && a.parentElement instanceof HTMLPictureElement) {
        b.remove(); continue;
      } else if (a instanceof HTMLCanvasElement) {
        try {
          const image = document.createElement('img');
          image.src = a.toDataURL();
          for (const name of ['class', 'style', 'width', 'height', 'id']) if (a.hasAttribute(name)) image.setAttribute(name, a.getAttribute(name));
          b.replaceWith(image); continue;
        } catch (e) {}
      } else if (a instanceof HTMLInputElement) {
        if (a.type === 'checkbox' || a.type === 'radio') { if (a.checked) b.setAttribute('checked', ''); else b.removeAttribute('checked'); }
        else if (a.type !== 'password' && a.type !== 'file') b.setAttribute('value', a.value);
      } else if (a instanceof HTMLTextAreaElement) {
        b.textContent = a.value;
      } else if (a instanceof HTMLSelectElement) {
        const options = b.querySelectorAll('option');
        Array.from(a.options).forEach((o, i) => { if (options[i]) { if (o.selected) options[i].setAttribute('selected', ''); else options[i].removeAttribute('selected'); } });
      }
      for (const name of ['src', 'href', 'poster', 'action']) {
        // An image already carries the source it shows (currentSrc), which its src property would undo.
        if (name === 'src' && a instanceof HTMLImageElement) continue;
        const value = b.getAttribute(name);
        if (value === null || value.startsWith('#') || typeof a[name] !== 'string' || !a[name]) continue;
        b.setAttribute(name, a[name]);
      }
    }
    const type = document.doctype;
    return { html: (type ? '<!DOCTYPE ' + type.name + '>' : '') + copy.outerHTML, base: document.baseURI, title: document.title };
    """;
}

/// <summary>Reference resolution of RFC 3986 (section 5.2) on plain strings (macOS WebAddress). System.Uri and
/// Foundation each canonicalise addresses their own way; saving a page needs the same answer on both platforms.</summary>
public static class WebAddress
{
    sealed class Parts { public string? Scheme, Authority, Query, Fragment; public string Path = ""; }

    public static string? Resolve(string reference, string @base)
    {
        var r = Parse(SingleFilePage.Trim(reference));
        var t = new Parts { Fragment = r.Fragment };
        if (r.Scheme is not null) { t.Scheme = r.Scheme; t.Authority = r.Authority; t.Path = RemoveDots(r.Path); t.Query = r.Query; }
        else
        {
            var b = Parse(@base);
            if (b.Scheme is null) return null;
            t.Scheme = b.Scheme;
            if (r.Authority is not null) { t.Authority = r.Authority; t.Path = RemoveDots(r.Path); t.Query = r.Query; }
            else
            {
                t.Authority = b.Authority;
                if (r.Path.Length == 0) { t.Path = b.Path; t.Query = r.Query ?? b.Query; }
                else
                {
                    if (r.Path.StartsWith('/')) t.Path = RemoveDots(r.Path);
                    else if (b.Authority is not null && b.Path.Length == 0) t.Path = RemoveDots("/" + r.Path);
                    else { var slash = b.Path.LastIndexOf('/'); t.Path = RemoveDots((slash >= 0 ? b.Path[..(slash + 1)] : "") + r.Path); }
                    t.Query = r.Query;
                }
            }
        }
        var result = new StringBuilder().Append(t.Scheme).Append(':');
        if (t.Authority is not null) result.Append("//").Append(t.Authority);
        result.Append(t.Path);
        if (t.Query is not null) result.Append('?').Append(t.Query);
        if (t.Fragment is not null) result.Append('#').Append(t.Fragment);
        return result.ToString();
    }

    static Parts Parse(string text)
    {
        var parts = new Parts();
        var rest = text;
        var hash = rest.IndexOf('#');
        if (hash >= 0) { parts.Fragment = rest[(hash + 1)..]; rest = rest[..hash]; }
        var mark = rest.IndexOf('?');
        if (mark >= 0) { parts.Query = rest[(mark + 1)..]; rest = rest[..mark]; }
        var colon = rest.IndexOf(':');
        if (colon > 0 && !rest[..colon].Contains('/'))
        {
            var name = rest[..colon];
            var valid = true;
            for (var i = 0; i < name.Length; i++)
            {
                var c = name[i];
                if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (i > 0 && ((c >= '0' && c <= '9') || c == '+' || c == '-' || c == '.')))) { valid = false; break; }
            }
            if (valid) { parts.Scheme = name.ToLowerInvariant(); rest = rest[(colon + 1)..]; }
        }
        if (rest.StartsWith("//", StringComparison.Ordinal))
        {
            rest = rest[2..];
            var end = rest.IndexOf('/');
            if (end < 0) end = rest.Length;
            parts.Authority = rest[..end]; rest = rest[end..];
        }
        parts.Path = rest;
        return parts;
    }

    static string RemoveDots(string path)
    {
        var input = path;
        var result = "";
        while (input.Length > 0)
        {
            if (input.StartsWith("../", StringComparison.Ordinal)) input = input[3..];
            else if (input.StartsWith("./", StringComparison.Ordinal)) input = input[2..];
            else if (input.StartsWith("/./", StringComparison.Ordinal)) input = input[2..];
            else if (input == "/.") input = "/";
            else if (input.StartsWith("/../", StringComparison.Ordinal)) { input = input[3..]; result = DropLastSegment(result); }
            else if (input == "/..") { input = "/"; result = DropLastSegment(result); }
            else if (input is "." or "..") input = "";
            else
            {
                var start = input.StartsWith('/') ? 1 : 0;
                var end = input.IndexOf('/', start);
                if (end < 0) end = input.Length;
                result += input[..end]; input = input[end..];
            }
        }
        return result;
    }

    static string DropLastSegment(string path) { var slash = path.LastIndexOf('/'); return slash < 0 ? "" : path[..slash]; }
}
