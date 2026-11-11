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
    /// <summary>When the download started. Older records have none; the app fills it once from the file on disk.</summary>
    public DateTimeOffset? Date { get; set; }
}

public enum DownloadKind { Image, Video, Archive, Document, Other }

/// <summary>What a downloaded file is, by its extension: picks the icon of a finished download. Lists match macOS
/// exactly (shared vectors), so the same file shows the same kind on both platforms.</summary>
public static class DownloadKinds
{
    static readonly (DownloadKind Kind, HashSet<string> Extensions)[] Table =
    [
        (DownloadKind.Image, ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "avif", "bmp", "tif", "tiff", "svg", "ico", "raw", "dng", "cr2", "nef", "arw"]),
        (DownloadKind.Video, ["mp4", "m4v", "mov", "webm", "mkv", "avi", "wmv", "flv", "mpg", "mpeg", "3gp", "ts", "m2ts"]),
        (DownloadKind.Archive, ["zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "tbz", "xz", "txz", "zst", "lz", "lzma", "cab", "dmg", "iso", "pkg"]),
        (DownloadKind.Document, ["pdf", "doc", "docx", "odt", "rtf", "txt", "md", "pages", "xls", "xlsx", "ods", "csv", "numbers", "ppt", "pptx", "odp", "key", "epub", "djvu", "fb2", "html", "htm"]),
    ];

    public static DownloadKind Of(string name)
    {
        var dot = name.LastIndexOf('.');
        if (dot <= 0) return DownloadKind.Other;
        var ext = name[(dot + 1)..].ToLowerInvariant();
        foreach (var (kind, extensions) in Table) if (extensions.Contains(ext)) return kind;
        return DownloadKind.Other;
    }

    /// <summary>Lowercase name shared with macOS (`DownloadKind.rawValue`).</summary>
    public static string Name(DownloadKind kind) => kind.ToString().ToLowerInvariant();
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
