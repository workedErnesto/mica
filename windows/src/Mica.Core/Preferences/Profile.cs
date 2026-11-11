namespace Mica.Core;

/// <summary>What a profile changes: the start page, the window arrangement, theme and colours, the greeting name, and the
/// language and letter case of the interface text (macOS ProfileLook). Passwords, cookies, history, bookmarks, downloads and extensions are shared by every profile.</summary>
public sealed class ProfileLook
{
    public TabLayout Layout { get; set; } = TabLayout.Left;
    public Theme Theme { get; set; } = Theme.System;
    public Theme CustomBase { get; set; } = Theme.System;
    public string Accent { get; set; } = "#6E56CF";
    public double CustomTint { get; set; } = 0.3;
    public bool Frosted { get; set; } = true;
    public double Transparency { get; set; } = 0.55;
    public string UserName { get; set; } = "";
    public bool GreetByName { get; set; } = true;
    public ToolbarLayout Toolbar { get; set; } = new();
    public StartPage Start { get; set; } = new();
    public bool SidebarCollapsed { get; set; }
    public double SidebarWidth { get; set; } = 248;
    /// <summary>Interface language and letter case of this profile's windows. Null only in profiles saved before they had their
    /// own, which follow the application-wide setting until Profiles.Normalized fills them in.</summary>
    public Language? Language { get; set; }
    public bool? Lowercase { get; set; }

    public static ProfileLook From(Preferences p) => new()
    {
        Layout = p.Layout, Theme = p.Theme, CustomBase = p.CustomBase, Accent = p.Accent, CustomTint = p.CustomTint, Frosted = p.Frosted,
        Transparency = p.Transparency, UserName = p.UserName, GreetByName = p.GreetByName, SidebarCollapsed = p.SidebarCollapsed, SidebarWidth = p.SidebarWidth,
        Toolbar = p.Toolbar.Clone(), Start = p.Clone().Start, Language = p.Language, Lowercase = p.Lowercase,
    };

    /// <summary>A copy of the application-wide preferences with this profile's part laid over them.</summary>
    public Preferences AppliedTo(Preferences base_)
    {
        var p = base_.Clone();
        p.Layout = Layout; p.Theme = Theme; p.CustomBase = CustomBase; p.Accent = Accent; p.CustomTint = CustomTint; p.Frosted = Frosted;
        p.Transparency = Transparency; p.UserName = UserName; p.GreetByName = GreetByName; p.SidebarCollapsed = SidebarCollapsed; p.SidebarWidth = SidebarWidth;
        p.Toolbar = Toolbar.Clone();
        p.Start = Start;
        p.Language = Language ?? base_.Language; p.Lowercase = Lowercase ?? base_.Lowercase;
        return p.Clone().Sanitized();
    }

    /// <summary>Clamped and repaired the same way preferences are.</summary>
    public ProfileLook Sanitized()
    {
        Toolbar ??= new(); Start ??= new(); Accent ??= "#6E56CF"; UserName ??= "";
        var repaired = From(AppliedTo(new Preferences()));
        Toolbar = repaired.Toolbar; Start = repaired.Start; Accent = repaired.Accent; CustomTint = repaired.CustomTint; Transparency = repaired.Transparency;
        UserName = repaired.UserName; SidebarWidth = repaired.SidebarWidth; CustomBase = repaired.CustomBase;
        if (Language is { } language && !Enum.IsDefined(language)) Language = null;
        return this;
    }

    /// <summary>Fills a missing language or case from source.</summary>
    public void Adopt(ProfileLook source)
    {
        Language ??= source.Language;
        Lowercase ??= source.Lowercase;
    }

    public bool SameAs(ProfileLook other) =>
        System.Text.Json.JsonSerializer.Serialize(this, MicaJson.Info<ProfileLook>()) == System.Text.Json.JsonSerializer.Serialize(other, MicaJson.Info<ProfileLook>());
}

/// <summary>Where a profile chosen in the profile menu opens. Switching a window replaces its pinned tabs with the
/// profile's, so the safe default asks first.</summary>
public enum ProfileOpening { Ask, Here, NewWindow }

/// <summary>Colour of the profile glyph on its background. Auto picks white or ink by contrast.</summary>
public enum ProfileGlyph { Auto, Light, Dark }

/// <summary>A named look for browser windows. Every window belongs to one profile; the standard profile always exists,
/// can be renamed and get another icon, but cannot be removed.</summary>
public sealed class Profile
{
    public static readonly Guid StandardId = new("6D1CA000-0000-4000-8000-000000000001");
    public const int NameLimit = 32;
    public Guid Id { get; set; } = Guid.NewGuid();
    /// <summary>Empty only for the standard profile, which then shows its localized default name.</summary>
    public string Name { get; set; } = "";
    public string Icon { get; set; } = ProfileCatalog.StandardIcon;
    public string Background { get; set; } = ProfileCatalog.StandardBackground;
    public ProfileGlyph Glyph { get; set; } = ProfileGlyph.Auto;
    public ProfileLook Look { get; set; } = new();
    /// <summary>Pinned tabs a new window of this profile opens with.</summary>
    public List<SavedTab> Pinned { get; set; } = [];
    public bool IsStandard => Id == StandardId;

    public static Profile Standard(ProfileLook? look = null) => new() { Id = StandardId, Look = look ?? new ProfileLook() };

    public Profile Sanitized()
    {
        Name = Profiles.Name(Name ?? "");
        if (!ProfileCatalog.Icons.Contains(Icon)) Icon = ProfileCatalog.StandardIcon;
        Background = (Background ?? "").ToUpperInvariant();
        if (HexColor.Parse(Background) is null) Background = ProfileCatalog.StandardBackground;
        if (!Enum.IsDefined(Glyph)) Glyph = ProfileGlyph.Auto;
        Look = (Look ?? new()).Sanitized();
        Pinned = (Pinned ?? []).Where(t => t.Pinned && t.Url is { } url && (url.StartsWith("https://", StringComparison.OrdinalIgnoreCase) || url.StartsWith("http://", StringComparison.OrdinalIgnoreCase)) && AddressParser.Navigable(url)).ToList();
        return this;
    }

    public Profile Copy() => new() { Id = Id, Name = Name, Icon = Icon, Background = Background, Glyph = Glyph, Look = ProfileLook.From(Look.AppliedTo(new Preferences())), Pinned = Pinned.Select(t => t.Copy()).ToList() };
}

public static class Profiles
{
    public const int Limit = 24;

    /// <summary>Spaces and line breaks around the name are dropped; the name keeps its case and is cut at the limit.</summary>
    public static string Name(string input)
    {
        // Swift: lines joined by a space, then horizontal whitespace trimmed (CharacterSet.whitespaces).
        var lines = input.Split(['\n', '\r', '\u0085', '\u2028', '\u2029', '\u000B', '\u000C']);
        var flat = string.Join(" ", lines);
        int start = 0, end = flat.Length;
        while (start < end && Horizontal(flat[start])) start++;
        while (end > start && Horizontal(flat[end - 1])) end--;
        flat = flat[start..end];
        var info = new System.Globalization.StringInfo(flat);
        return info.LengthInTextElements > Profile.NameLimit ? info.SubstringByTextElements(0, Profile.NameLimit) : flat;
    }

    static bool Horizontal(char c) => c == '\t' || char.GetUnicodeCategory(c) == System.Globalization.UnicodeCategory.SpaceSeparator;

    /// <summary>The standard profile first, each id once. A list without the standard one gets it back.</summary>
    public static List<Profile> Normalized(IEnumerable<Profile> list, ProfileLook? fallback = null)
    {
        var seen = new HashSet<Guid>();
        var unique = list.Where(p => p is not null && seen.Add(p.Id)).Select(p => p.Sanitized()).ToList();
        var standard = unique.FirstOrDefault(p => p.IsStandard) ?? Profile.Standard(fallback);
        unique.RemoveAll(p => p.IsStandard);
        // Profiles saved before they had their own language and case take the application-wide ones.
        if (fallback is not null) foreach (var p in unique.Append(standard)) p.Look.Adopt(fallback);
        return [.. new[] { standard }.Concat(unique).Take(Limit)];
    }

    public static Profile Resolve(Guid? id, IReadOnlyList<Profile> list) =>
        list.FirstOrDefault(p => p.Id == id) ?? list.FirstOrDefault(p => p.IsStandard) ?? Profile.Standard();

    /// <summary>A new profile takes the first icon and the first background no other profile uses yet, and starts with
    /// no start page sites of its own.</summary>
    public static Profile Next(IReadOnlyList<Profile> list, string name, ProfileLook look)
    {
        var icons = list.Select(p => p.Icon).ToHashSet();
        var backgrounds = list.Select(p => p.Background).ToHashSet();
        var icon = ProfileCatalog.Icons.FirstOrDefault(i => !icons.Contains(i)) ?? ProfileCatalog.Icons[list.Count % ProfileCatalog.Icons.Count];
        var background = ProfileCatalog.Backgrounds.FirstOrDefault(b => !backgrounds.Contains(b)) ?? ProfileCatalog.Backgrounds[list.Count % ProfileCatalog.Backgrounds.Count];
        // The arrangement and colours carry over, the source profile's own and hidden start page sites do not.
        var copy = ProfileLook.From(look.AppliedTo(new Preferences()));
        copy.Start.Shortcuts = []; copy.Start.HiddenHosts = [];
        return new Profile { Name = Name(name), Icon = icon, Background = background, Look = copy };
    }

    public static List<Profile> Removing(Guid id, IEnumerable<Profile> list) => id == Profile.StandardId ? list.ToList() : list.Where(p => p.Id != id).ToList();

    /// <summary>Visits recorded before profiles existed belong to the standard profile.</summary>
    public static Guid Owner(Visit visit) => visit.Profile ?? Profile.StandardId;

    public static string DisplayName(Profile profile, bool lowercase, Language language)
    {
        if (profile.Name.Length > 0) return profile.Name;
        return profile.IsStandard ? Copy.Text("обычный", "Обычный", lowercase, language) : Copy.Text("профиль", "Профиль", lowercase, language);
    }

    /// <summary>White glyph while it keeps the 3:1 contrast WCAG asks of non-text elements, ink on lighter backgrounds.</summary>
    public static bool LightGlyph(string background, ProfileGlyph glyph = ProfileGlyph.Auto) => glyph switch
    {
        ProfileGlyph.Light => true,
        ProfileGlyph.Dark => false,
        _ => 1.05 / ((HexColor.Luminance(background) ?? 0) + 0.05) >= 3,
    };
}
