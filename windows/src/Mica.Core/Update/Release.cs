using System.Text.Json.Serialization;

namespace Mica.Core;

/// <summary>Dotted numeric version such as 0.3.0; a leading "v" from a tag name is ignored.</summary>
public sealed class AppVersion : IComparable<AppVersion>, IEquatable<AppVersion>
{
    public IReadOnlyList<int> Parts { get; }
    AppVersion(int[] parts) { Parts = parts; }

    public static AppVersion? Parse(string? text)
    {
        if (text is null) return null;
        var raw = text.Trim(' ');
        if (raw.StartsWith('v') || raw.StartsWith('V')) raw = raw[1..];
        var components = raw.Split('.');
        if (components.Length == 0 || components.Length > 4 || components.Any(c => c.Length == 0 || !c.All(char.IsAsciiDigit))) return null;
        var parts = new int[components.Length];
        for (var i = 0; i < components.Length; i++) if (!int.TryParse(components[i], out parts[i])) return null;
        return new AppVersion(parts);
    }

    public int CompareTo(AppVersion? other)
    {
        if (other is null) return 1;
        for (var i = 0; i < Math.Max(Parts.Count, other.Parts.Count); i++)
        {
            int x = i < Parts.Count ? Parts[i] : 0, y = i < other.Parts.Count ? other.Parts[i] : 0;
            if (x != y) return x.CompareTo(y);
        }
        return 0;
    }
    public bool Equals(AppVersion? other) => other is not null && CompareTo(other) == 0;
    public override bool Equals(object? obj) => obj is AppVersion v && Equals(v);
    public override int GetHashCode() => string.Join('.', Parts.Reverse().SkipWhile(p => p == 0).Reverse()).GetHashCode();
    public override string ToString() => string.Join('.', Parts);
    public static bool operator <(AppVersion a, AppVersion b) => a.CompareTo(b) < 0;
    public static bool operator >(AppVersion a, AppVersion b) => a.CompareTo(b) > 0;
}

/// <summary>The part of a GitHub release mica needs.</summary>
public sealed class Release
{
    public sealed class Asset
    {
        [JsonPropertyName("name")] public string Name { get; set; } = "";
        [JsonPropertyName("browser_download_url")] public string Url { get; set; } = "";
        [JsonPropertyName("size")] public long Size { get; set; }
    }
    [JsonPropertyName("tag_name")] public string Tag { get; set; } = "";
    [JsonPropertyName("name")] public string? Name { get; set; }
    [JsonPropertyName("body")] public string? Notes { get; set; }
    [JsonPropertyName("html_url")] public string Page { get; set; } = "";
    [JsonPropertyName("draft")] public bool Draft { get; set; }
    [JsonPropertyName("prerelease")] public bool Prerelease { get; set; }
    [JsonPropertyName("assets")] public List<Asset> Assets { get; set; } = [];

    public AppVersion? Version => AppVersion.Parse(Tag);
    /// <summary>Installer for this machine: mica-&lt;version&gt;-win-&lt;x64|arm64&gt;-setup.exe.</summary>
    public Asset? Installer(string architecture) => Assets.FirstOrDefault(a => a.Name.EndsWith($"-win-{architecture}-setup.exe", StringComparison.OrdinalIgnoreCase));
    public Asset? Checksum(string architecture) => Installer(architecture) is { } exe ? Assets.FirstOrDefault(a => a.Name == exe.Name + ".sha256") : null;
}

public static class UpdatePolicy
{
    public const string Repository = "workedErnesto/mica";
    public static readonly TimeSpan CheckInterval = TimeSpan.FromHours(24);
    public static string LatestUrl => $"https://api.github.com/repos/{Repository}/releases/latest";

    public static TimeSpan DelaySinceLastCheck(DateTimeOffset? last, DateTimeOffset now)
    {
        if (last is null) return TimeSpan.Zero;
        var remaining = CheckInterval - (now - last.Value);
        return remaining < TimeSpan.Zero ? TimeSpan.Zero : remaining > CheckInterval ? CheckInterval : remaining;
    }

    public static bool Offer(Release release, AppVersion current, Preferences preferences, string architecture)
    {
        if (!preferences.UpdateChecks || release.Draft || release.Prerelease || release.Version is not { } version || !(version > current)) return false;
        if (release.Installer(architecture) is null || release.Checksum(architecture) is null) return false;
        return AppVersion.Parse(preferences.SkippedVersion) is not { } skipped || !skipped.Equals(version);
    }

    /// <summary>First hexadecimal SHA-256 in a sha256sum or shasum line.</summary>
    public static string? ParseChecksum(string text)
    {
        var token = text.Split([' ', '\n', '\t', '\r'], StringSplitOptions.RemoveEmptyEntries).FirstOrDefault()?.ToLowerInvariant() ?? "";
        return token.Length == 64 && token.All(c => char.IsAsciiDigit(c) || (c >= 'a' && c <= 'f')) ? token : null;
    }
}
