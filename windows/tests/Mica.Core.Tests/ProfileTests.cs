using Mica.Core;
using Xunit;

namespace Mica.Core.Tests;

/// <summary>Same rules as macos/Tests/MicaCoreTests/ProfileTests.swift.</summary>
public class ProfileTests
{
    [Fact]
    public void LegacyPreferencesBecomeTheStandardProfile()
    {
        var old = new Preferences { Layout = TabLayout.Right, Theme = Theme.Custom, Accent = "#3E7BFA", UserName = "Алекс", SidebarCollapsed = true };
        old.Start.FrequentCount = 12;
        var list = Profiles.Normalized([], ProfileLook.From(old));
        Assert.Single(list);
        Assert.True(list[0].IsStandard);
        Assert.Equal(TabLayout.Right, list[0].Look.Layout);
        Assert.Equal("Алекс", list[0].Look.UserName);
        Assert.Equal(12, list[0].Look.Start.FrequentCount);
    }

    [Fact]
    public void LookOverlaysOnlyItsOwnPart()
    {
        var global = new Preferences { Search = SearchEngine.Kagi, Language = Language.En, Theme = Theme.Dark };
        var look = new ProfileLook { Theme = Theme.Light, Layout = TabLayout.Top };
        var effective = look.AppliedTo(global);
        Assert.Equal(SearchEngine.Kagi, effective.Search);
        Assert.Equal(Theme.Light, effective.Theme);
        Assert.Equal(TabLayout.Top, effective.Layout);
        Assert.Equal(Theme.Dark, global.Theme);
    }

    [Fact]
    public void ProfileRoundTripAndRepair()
    {
        var path = Path.Combine(Path.GetTempPath(), Guid.NewGuid() + ".json");
        var profile = new Profile { Name = "  x  ", Icon = "no.such.symbol", Background = "red", Pinned = [new SavedTab { Url = "javascript:alert(1)", Pinned = true }, new SavedTab { Url = "https://mail.example.com", Pinned = true }] };
        Persistence.Write(new List<Profile> { profile }, path);
        var read = Profiles.Normalized(Persistence.Read<List<Profile>>(path));
        File.Delete(path);
        Assert.Equal(2, read.Count);
        Assert.Equal("x", read[1].Name);
        Assert.Equal(ProfileCatalog.StandardIcon, read[1].Icon);
        Assert.Equal(ProfileCatalog.StandardBackground, read[1].Background);
        Assert.Single(read[1].Pinned);
    }

    [Fact]
    public void StandardProfileCannotBeRemovedAndStaysFirst()
    {
        var work = new Profile { Name = "work", Icon = "briefcase", Background = "#3E7BFA" };
        var list = Profiles.Normalized([work, Profile.Standard(), work]);
        Assert.Equal([Profile.StandardId, work.Id], list.Select(p => p.Id));
        Assert.Equal(2, Profiles.Removing(Profile.StandardId, list).Count);
        Assert.Equal(Profile.StandardId, Profiles.Resolve(work.Id, [Profile.Standard()]).Id);
    }

    [Fact]
    public void NewProfileKeepsLookButNotTheSourceSites()
    {
        var look = new ProfileLook { Theme = Theme.Dark, Layout = TabLayout.Top };
        look.Start.Shortcuts.Add(new StartShortcut { Title = "mail", Url = "https://mail.example.com" });
        look.Start.HiddenHosts.Add("news.example.com");
        var profile = Profiles.Next([Profile.Standard()], "x", look);
        Assert.Equal(Theme.Dark, profile.Look.Theme);
        Assert.Equal(TabLayout.Top, profile.Look.Layout);
        Assert.Empty(profile.Look.Start.Shortcuts);
        Assert.Empty(profile.Look.Start.HiddenHosts);
        Assert.Empty(profile.Pinned);
        Assert.Single(look.Start.Shortcuts);
    }

    [Fact]
    public void ProfileOpeningDefaultsToAskAndUsesMacSpelling()
    {
        Assert.Equal(ProfileOpening.Ask, new Preferences().ProfileOpening);
        var path = Path.Combine(Path.GetTempPath(), Guid.NewGuid() + ".json");
        Persistence.Write(new Preferences { ProfileOpening = ProfileOpening.NewWindow }, path);
        var text = File.ReadAllText(path);
        var read = Persistence.Read<Preferences>(path);
        File.Delete(path);
        Assert.Contains("\"newWindow\"", text);
        Assert.Equal(ProfileOpening.NewWindow, read.ProfileOpening);
    }

    [Fact]
    public void VisitsAndSessionsKeepTheirProfile()
    {
        Assert.Equal(Profile.StandardId, Profiles.Owner(new Visit("https://example.com", "")));
        var id = Guid.NewGuid();
        Assert.Equal(id, Profiles.Owner(new Visit("https://example.com", "", id)));
        var session = new Session { Windows = [new SavedWindow { Tabs = [new SavedTab { Url = "https://example.com" }], Profile = id }] };
        Assert.Equal(id, session.Validated().Windows[0].Profile);
    }

    [Fact]
    public void NewToolbarControlAppearsInSidebarOfOldLayouts()
    {
        var old = new ToolbarLayout { Sidebar = [ToolbarControl.Bookmarks, ToolbarControl.Settings], Known = [ToolbarControl.Sidebar, ToolbarControl.Back, ToolbarControl.Forward, ToolbarControl.Reload, ToolbarControl.NewTab, ToolbarControl.Bookmarks, ToolbarControl.History, ToolbarControl.Downloads, ToolbarControl.Extensions, ToolbarControl.Incognito, ToolbarControl.Settings] };
        var migrated = old.Migrated();
        Assert.Equal(ToolbarControl.Profile, migrated.Sidebar[0]);
    }
}
