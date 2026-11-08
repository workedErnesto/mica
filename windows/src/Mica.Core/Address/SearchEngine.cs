namespace Mica.Core;

public enum SearchEngine { DuckDuckGo, Google, Yandex, Kagi, Bing }

public static class SearchEngines
{
    public static readonly SearchEngine[] All = [SearchEngine.DuckDuckGo, SearchEngine.Google, SearchEngine.Yandex, SearchEngine.Kagi, SearchEngine.Bing];

    /// <summary>Stored value, the same spelling macOS writes.</summary>
    public static string RawValue(this SearchEngine engine) => engine.ToString();

    public static SearchEngine? Parse(string? raw) => raw switch
    {
        "DuckDuckGo" => SearchEngine.DuckDuckGo, "Google" => SearchEngine.Google, "Yandex" => SearchEngine.Yandex,
        "Kagi" => SearchEngine.Kagi, "Bing" => SearchEngine.Bing, _ => null,
    };

    /// <summary>Name shown in the Russian interface; brand spelling is kept.</summary>
    public static string Title(this SearchEngine engine, Language language) =>
        engine == SearchEngine.Yandex && language == Language.Ru ? "Яндекс" : engine.ToString();

    public static string Home(this SearchEngine engine) => engine switch
    {
        SearchEngine.DuckDuckGo => "https://duckduckgo.com/",
        SearchEngine.Google => "https://www.google.com/search",
        SearchEngine.Yandex => "https://yandex.ru/search/",
        SearchEngine.Kagi => "https://kagi.com/search",
        _ => "https://www.bing.com/search",
    };

    public static string Search(this SearchEngine engine, string query) =>
        engine.Home() + "?" + (engine == SearchEngine.Yandex ? "text" : "q") + "=" + UrlText.EncodeQueryValue(query);

    /// <summary>True when the URL is this engine's results page for exactly this query.</summary>
    public static bool IsSearch(this SearchEngine engine, string url, string query) => url == engine.Search(query);
}

/// <summary>Percent-encoding with the same allowed set as Foundation's URLComponents query items, so both
/// platforms build byte-identical search addresses (checked by shared/fixtures/core/vectors.json).</summary>
public static class UrlText
{
    // Query characters except the pair separators & and =, which Foundation escapes inside a value; + and ? stay as typed.
    const string Allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~!$'()*+,;:@/?";

    public static string EncodeQueryValue(string value)
    {
        var builder = new System.Text.StringBuilder(value.Length * 2);
        foreach (var b in System.Text.Encoding.UTF8.GetBytes(value))
        {
            var c = (char)b;
            if (b < 128 && Allowed.Contains(c)) builder.Append(c);
            else builder.Append('%').Append(b.ToString("X2"));
        }
        return builder.ToString();
    }
}
