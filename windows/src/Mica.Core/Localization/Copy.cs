using System.Globalization;
using System.Reflection;

namespace Mica.Core;

/// <summary>Interface language. Page content, URLs and user data are never translated.</summary>
public enum Language { Ru, En }

public static class LanguageInfo
{
    /// <summary>Russian when the system prefers it, English otherwise.</summary>
    public static Language Preferred(IEnumerable<string>? languages = null)
    {
        foreach (var code in languages ?? [CultureInfo.CurrentUICulture.Name])
        {
            if (code.StartsWith("ru", StringComparison.OrdinalIgnoreCase)) return Language.Ru;
            if (code.StartsWith("en", StringComparison.OrdinalIgnoreCase)) return Language.En;
        }
        return Language.En;
    }
    public static CultureInfo Culture(this Language language) => CultureInfo.GetCultureInfo(language == Language.Ru ? "ru-RU" : "en-US");
}

/// <summary>Explicit variants affect only authored UI, never dynamic content or whole strings.</summary>
public static class Copy
{
    public static string Text(string low, string regular, bool lowercase) => lowercase ? low : regular;

    /// <summary>Russian variants are written at the call site; English comes from shared/strings/en.txt keyed by the regular Russian text.</summary>
    public static string Text(string low, string regular, bool lowercase, Language language)
    {
        if (language != Language.En || !English.Table.TryGetValue(regular, out var english)) return lowercase ? low : regular;
        return lowercase ? english.Low : english.Regular;
    }
}

/// <summary>English interface text from shared/strings/en.txt, the same file macOS is generated from.</summary>
public static class English
{
    public static readonly IReadOnlyDictionary<string, (string Low, string Regular)> Table = Load();

    static Dictionary<string, (string Low, string Regular)> Load()
    {
        using var stream = typeof(English).Assembly.GetManifestResourceStream("mica.en.txt") ?? throw new InvalidOperationException("en.txt missing");
        using var reader = new StreamReader(stream);
        return Parse(reader.ReadToEnd());
    }

    public static Dictionary<string, (string Low, string Regular)> Parse(string source)
    {
        var result = new Dictionary<string, (string, string)>(StringComparer.Ordinal);
        foreach (var line in source.Split('\n'))
        {
            var parts = line.TrimEnd('\r').Split('⟩');
            if (parts.Length == 3) result[parts[0]] = (parts[1], parts[2]);
        }
        return result;
    }
}

/// <summary>Start page greeting. The name is user data and keeps its spelling; only the authored words follow the case style.</summary>
public static class Greeting
{
    public static List<(string Low, string Regular)> Phrases(int hour, Language language)
    {
        static bool In(int h, int a, int b) => h >= a && h < b;
        if (language == Language.Ru)
        {
            var time = In(hour, 5, 12) ? ("доброе утро, {name}", "Доброе утро, {name}") : In(hour, 12, 18) ? ("добрый день, {name}", "Добрый день, {name}") : In(hour, 18, 24) ? ("добрый вечер, {name}", "Добрый вечер, {name}") : ("не спится, {name}?", "Не спится, {name}?");
            return [time, ("привет, {name}", "Привет, {name}"), ("{name}, чем займёмся?", "{name}, чем займёмся?"), ("с возвращением, {name}", "С возвращением, {name}"), ("что ищем, {name}?", "Что ищем, {name}?"), ("куда сегодня, {name}?", "Куда сегодня, {name}?"), ("{name}, что откроем?", "{name}, что откроем?")];
        }
        var en = In(hour, 5, 12) ? ("good morning, {name}", "Good morning, {name}") : In(hour, 12, 18) ? ("good afternoon, {name}", "Good afternoon, {name}") : In(hour, 18, 24) ? ("good evening, {name}", "Good evening, {name}") : ("up late, {name}?", "Up late, {name}?");
        return [en, ("hi, {name}", "Hi, {name}"), ("{name}, what's next?", "{name}, what's next?"), ("welcome back, {name}", "Welcome back, {name}"), ("where to, {name}?", "Where to, {name}?"), ("what are we looking for, {name}?", "What are we looking for, {name}?"), ("{name}, what shall we open?", "{name}, what shall we open?")];
    }

    /// <summary>Null when there is no name or the user asked not to be addressed by it. Seed picks the phrase.</summary>
    public static string? Text(Preferences preferences, int hour, int seed)
    {
        var name = preferences.UserName.Trim();
        if (!preferences.GreetByName || name.Length == 0) return null;
        var list = Phrases(hour, preferences.Language);
        var phrase = list[((seed % list.Count) + list.Count) % list.Count];
        return (preferences.Lowercase ? phrase.Low : phrase.Regular).Replace("{name}", name);
    }
}
