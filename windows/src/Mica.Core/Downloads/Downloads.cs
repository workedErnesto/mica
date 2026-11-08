namespace Mica.Core;

public enum DownloadState { Choosing, Running, Paused, Complete, Failed, Cancelled }

/// <summary>Durable metadata. Downloaded files stay at their user-selected destinations.</summary>
public sealed class DownloadRecord
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Name { get; set; } = "";
    public string State { get; set; } = "complete";
    public string? Destination { get; set; }
    public string? Source { get; set; }
    public long Bytes { get; set; }
    public long Total { get; set; }
}

public static class DownloadSafety
{
    static readonly HashSet<string> Reserved = new(StringComparer.OrdinalIgnoreCase) { "CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9" };

    /// <summary>Same rules as macOS (last path part, no control characters, colon or slash, 200 characters), plus what
    /// Windows forbids in file names: backslash, &lt;&gt;"|?*, trailing dots and spaces, device names.</summary>
    public static string Filename(string proposed, bool windows = true)
    {
        var last = proposed.Split('/').Last();
        if (windows) last = last.Split('\\').Last();
        var forbidden = windows ? ":/\\<>\"|?*" : ":/";
        var name = new string(last.Where(c => !char.IsControl(c) && !forbidden.Contains(c)).ToArray()).Trim();
        if (windows) name = name.TrimEnd('.', ' ');
        if (name.Length == 0 || name == "." || name == "..") return "download";
        if (windows && Reserved.Contains(name.Split('.')[0])) name = "_" + name;
        return name.Length > 200 ? name[..200] : name;
    }
}
