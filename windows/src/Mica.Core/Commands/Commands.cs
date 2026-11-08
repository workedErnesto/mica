using System.Text.Json;

namespace Mica.Core;

public sealed class KeymapFile
{
    public Dictionary<string, KeymapEntry> Commands { get; set; } = [];
}

public sealed class KeymapEntry
{
    public List<string> Macos { get; set; } = [];
    public List<string> Windows { get; set; } = [];
}

/// <summary>A parsed accelerator such as Ctrl+Shift+T. Key is a VirtualKey name or a single character.</summary>
public sealed record Shortcut(bool Ctrl, bool Shift, bool Alt, bool Win, string Key)
{
    public static Shortcut? Parse(string text)
    {
        var parts = text.Split('+');
        if (parts.Length == 0) return null;
        // "Ctrl+=" and "Ctrl+-" end in the key itself; "Ctrl++" would split into an empty part, so it is not allowed.
        var key = parts[^1];
        if (key.Length == 0) return null;
        bool ctrl = false, shift = false, alt = false, win = false;
        foreach (var modifier in parts[..^1])
        {
            switch (modifier)
            {
                case "Ctrl": ctrl = true; break;
                case "Shift": shift = true; break;
                case "Alt": alt = true; break;
                case "Win": win = true; break;
                default: return null;
            }
        }
        return new Shortcut(ctrl, shift, alt, win, key);
    }

    /// <summary>Label for menus, in Windows spelling.</summary>
    public string Label => string.Join("+", new[] { Ctrl ? "Ctrl" : null, Shift ? "Shift" : null, Alt ? "Alt" : null, Win ? "Win" : null, Key switch
    {
        "Left" => "←", "Right" => "→", "Delete" => "Del", "PageUp" => "PgUp", "PageDown" => "PgDn", "Add" => "+", "Subtract" => "−", _ => Key,
    } }.Where(p => p is not null));
}

/// <summary>Keyboard commands from shared/keymap.json.</summary>
public static class Keymap
{
    public static readonly IReadOnlyDictionary<string, List<Shortcut>> Windows = Load();

    static Dictionary<string, List<Shortcut>> Load()
    {
        using var stream = typeof(Keymap).Assembly.GetManifestResourceStream("mica.keymap.json")!;
        var file = JsonSerializer.Deserialize(stream, MicaJson.Info<KeymapFile>())!;
        return file.Commands.ToDictionary(c => c.Key, c => c.Value.Windows.Select(Shortcut.Parse).OfType<Shortcut>().ToList());
    }

    public static string? Label(string command) => Windows.TryGetValue(command, out var list) && list.Count > 0 ? list[0].Label : null;
}

public sealed class GlyphFile
{
    public Dictionary<string, string> Glyphs { get; set; } = [];
}

/// <summary>SF Symbol names used by the shared interface code, mapped to Segoe Fluent Icons characters.</summary>
public static class Glyphs
{
    static readonly Dictionary<string, string> Map = Load();

    static Dictionary<string, string> Load()
    {
        using var stream = typeof(Glyphs).Assembly.GetManifestResourceStream("mica.glyphs.json")!;
        return JsonSerializer.Deserialize(stream, MicaJson.Info<GlyphFile>())!.Glyphs;
    }

    public static string For(string symbol) =>
        Map.TryGetValue(symbol, out var code) ? char.ConvertFromUtf32(Convert.ToInt32(code, 16)) : char.ConvertFromUtf32(0xE774);

    public static bool Known(string symbol) => Map.ContainsKey(symbol);
}

/// <summary>The bundled Peter Lowe list, shared with macOS.</summary>
public static class Blocklist
{
    public static string Bundled()
    {
        using var stream = typeof(Blocklist).Assembly.GetManifestResourceStream("mica.blocklist.txt")!;
        using var reader = new StreamReader(stream);
        return reader.ReadToEnd();
    }
}
