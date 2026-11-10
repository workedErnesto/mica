namespace Mica.Core;

public sealed class Preferences
{
    public const int NameLimit = 32;
    public const double SidebarMin = 200, SidebarMax = 380;

    public TabLayout Layout { get; set; } = TabLayout.Left;
    public Language Language { get; set; } = LanguageInfo.Preferred();
    /// <summary>Name for the start page greeting. Empty or GreetByName false keeps the mica wordmark.</summary>
    public string UserName { get; set; } = "";
    public bool GreetByName { get; set; } = true;
    public Theme Theme { get; set; } = Theme.System;
    public Theme CustomBase { get; set; } = Theme.System;
    public string Accent { get; set; } = "#6E56CF";
    /// <summary>How strongly the custom accent colours the shell, 0 to 0.6.</summary>
    public double CustomTint { get; set; } = 0.3;
    public bool Lowercase { get; set; } = true;
    public bool Frosted { get; set; } = true;
    /// <summary>Share of the backdrop that shows through the shell tint, 0 opaque to 1 the most see-through.</summary>
    public double Transparency { get; set; } = 0.55;
    public string? AppIcon { get; set; }
    public ToolbarLayout Toolbar { get; set; } = new();
    public StartPage Start { get; set; } = new();
    public SearchEngine Search { get; set; } = SearchEngine.DuckDuckGo;
    public bool Blocking { get; set; } = true;
    public bool Restore { get; set; } = true;
    public bool LazyRestore { get; set; } = true;
    public List<string> EagerHosts { get; set; } = [];
    public List<string> BlockingExceptions { get; set; } = [];
    public bool OnboardingComplete { get; set; }
    public bool SidebarCollapsed { get; set; }
    public double SidebarWidth { get; set; } = 248;
    public ClearChoice Clearing { get; set; } = new();
    public bool UpdateChecks { get; set; } = true;
    public string? SkippedVersion { get; set; }
    public bool OfferPasswords { get; set; } = true;
    public bool FillPasswords { get; set; } = true;
    /// <summary>Sites may ask for permission to show notifications. Off answers every new request with a refusal.</summary>
    public bool NotificationRequests { get; set; } = true;
    /// <summary>What choosing another profile in the profile menu does. Ask asks once and offers to remember the answer.</summary>
    public ProfileOpening ProfileOpening { get; set; } = ProfileOpening.Ask;

    /// <summary>Values read from disk are clamped and repaired the same way macOS decodes them.</summary>
    public Preferences Sanitized()
    {
        UserName = UserName.Length > NameLimit ? UserName[..NameLimit] : UserName;
        if (CustomBase == Theme.Custom) CustomBase = Theme.System;
        if (HexColor.Parse(Accent) is null) Accent = "#6E56CF";
        CustomTint = Math.Clamp(CustomTint, 0, 0.6);
        Transparency = Math.Clamp(Transparency, 0, 1);
        SidebarWidth = Math.Clamp(SidebarWidth, SidebarMin, SidebarMax);
        Toolbar = (Toolbar ?? new()).Migrated();
        Start = (Start ?? new()).Sanitized();
        Clearing ??= new();
        EagerHosts ??= []; BlockingExceptions ??= [];
        if (!Enum.IsDefined(ProfileOpening)) ProfileOpening = ProfileOpening.Ask;
        return this;
    }

    public Preferences Clone()
    {
        var copy = (Preferences)MemberwiseClone();
        copy.Toolbar = Toolbar.Clone();
        copy.Start = new StartPage { Wordmark = Start.Wordmark, Sections = [.. Start.Sections], FrequentCount = Start.FrequentCount, Shortcuts = Start.Shortcuts.Select(s => new StartShortcut { Id = s.Id, Title = s.Title, Url = s.Url }).ToList(), HiddenHosts = [.. Start.HiddenHosts] };
        copy.EagerHosts = [.. EagerHosts]; copy.BlockingExceptions = [.. BlockingExceptions]; copy.Clearing = Clearing.Copy();
        return copy;
    }
}
