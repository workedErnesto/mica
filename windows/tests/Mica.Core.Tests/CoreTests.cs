using Mica.Core;
using Xunit;

namespace Mica.Core.Tests;

public class CoreTests
{
    [Fact]
    public void PreferencesRoundTripUsesMacSpellings()
    {
        var p = new Preferences { Layout = TabLayout.Top, Search = SearchEngine.Yandex, Language = Language.En };
        p.Toolbar.Place(ToolbarControl.NewTab, ToolbarZone.Trailing);
        var json = System.Text.Encoding.UTF8.GetString(System.Text.Json.JsonSerializer.SerializeToUtf8Bytes(p, MicaJson.Info<Preferences>()));
        Assert.Contains("\"layout\": \"top\"", json);
        Assert.Contains("\"search\": \"Yandex\"", json);
        Assert.Contains("\"newTab\"", json);
        var back = System.Text.Json.JsonSerializer.Deserialize(json, MicaJson.Info<Preferences>())!.Sanitized();
        Assert.Equal(TabLayout.Top, back.Layout);
        Assert.Equal(ToolbarZone.Trailing, back.Toolbar.ZoneOf(ToolbarControl.NewTab));
    }

    [Fact]
    public void MissingKeysFallBackAndValuesAreClamped()
    {
        var p = System.Text.Json.JsonSerializer.Deserialize("{\"sidebarWidth\": 9999, \"customTint\": 5, \"accent\": \"nope\"}", MicaJson.Info<Preferences>())!.Sanitized();
        Assert.Equal(Preferences.SidebarMax, p.SidebarWidth);
        Assert.Equal(0.6, p.CustomTint);
        Assert.Equal("#6E56CF", p.Accent);
        Assert.True(p.NotificationRequests);
    }

    [Fact]
    public void ToolbarMigrationPlacesNewControlsOnce()
    {
        var old = new ToolbarLayout { Sidebar = [ToolbarControl.Bookmarks, ToolbarControl.Settings], Known = null };
        old.Migrated();
        Assert.Equal(ToolbarZone.Sidebar, old.ZoneOf(ToolbarControl.Incognito));
        Assert.Equal(ToolbarZone.Hidden, old.ZoneOf(ToolbarControl.History));
        var resolved = new ToolbarLayout().Resolve(sidebarAvailable: false);
        Assert.DoesNotContain(ToolbarControl.Sidebar, resolved.Leading);
        Assert.Contains(ToolbarControl.Settings, resolved.Trailing);
    }

    [Fact]
    public void SessionValidationDropsUnsafeAndDuplicates()
    {
        var id = Guid.NewGuid();
        var session = new Session { Windows = [new SavedWindow { Tabs = [new SavedTab { Id = id, Url = "https://a.example" }, new SavedTab { Id = id, Url = "https://b.example" }, new SavedTab { Url = "file:///c:/x" }, new SavedTab { Url = "https://p.example", Pinned = true }], Selected = Guid.NewGuid() }] };
        var valid = session.Validated();
        Assert.Equal(2, valid.Windows[0].Tabs.Count);
        Assert.True(valid.Windows[0].Tabs[0].Pinned);
        Assert.Equal(valid.Windows[0].Tabs[0].Id, valid.Windows[0].Selected);
    }

    [Fact]
    public void VaultSealsAndRejectsWrongKey()
    {
        var key = VaultCrypto.NewKey();
        var vault = new Vault();
        vault.Save("https://example.com", "me", "secret");
        var sealedBytes = VaultCrypto.Seal(vault, key);
        Assert.Equal("MICAPW1", System.Text.Encoding.ASCII.GetString(sealedBytes, 0, 7));
        Assert.Equal("secret", VaultCrypto.Open(sealedBytes, key).Logins[0].Password);
        Assert.ThrowsAny<System.Security.Cryptography.CryptographicException>(() => VaultCrypto.Open(sealedBytes, VaultCrypto.NewKey()));
        Assert.Empty(vault.Matches("https://example.com:443"));
        Assert.Single(vault.Matches("https://example.com"));
    }

    sealed class MemoryKeys : IVaultKeyStore { public byte[]? Key; public byte[]? Load() => Key; public void Save(byte[] key) => Key = key; }

    [Fact]
    public void VaultStoreNeverReplacesAMissingKey()
    {
        var path = Path.Combine(Path.GetTempPath(), "mica-vault-" + Guid.NewGuid() + ".bin");
        var keys = new MemoryKeys();
        var store = new VaultStore(path, keys);
        store.Update(v => v.Save("https://a.example", "u", "p"));
        Assert.Throws<InvalidOperationException>(() => new VaultStore(path, new MemoryKeys()));
        Assert.Single(new VaultStore(path, keys).Vault.Logins);
        File.Delete(path);
    }

    [Fact]
    public void GeneratedPasswordsHaveTheGroupedShape()
    {
        var password = PasswordGenerator.Strong();
        Assert.Matches("^[a-zA-Z2-9]{6}-[a-zA-Z2-9]{6}-[a-zA-Z2-9]{6}$", password);
        Assert.Contains(password, char.IsUpper);
        Assert.Contains(password, char.IsDigit);
        Assert.Equal(10, PasswordGenerator.Strong(10).Length);
    }

    [Fact]
    public void BlockerMatchesThirdPartySubdomainsOnly()
    {
        var blocker = new DomainBlocker(DomainBlocker.Builtin, ["news.example"]);
        Assert.True(blocker.ShouldBlock("https://www.google-analytics.com/analytics.js", "https://shop.example/"));
        Assert.False(blocker.ShouldBlock("https://www.google-analytics.com/analytics.js", "https://news.example/"));
        Assert.False(blocker.ShouldBlock("https://doubleclick.net/x", "https://ads.doubleclick.net/"));
        Assert.False(blocker.ShouldBlock("https://notdoubleclick.net/x", "https://a.example/"));
        Assert.True(DomainBlocker.ParseDomains(Blocklist.Bundled()).Count > 1000);
    }

    [Fact]
    public void NotificationPolicyMatchesMac()
    {
        var records = new List<SitePermission> { new() { Origin = "https://mail.example", Capability = SiteCapability.Notifications, Decision = Decision.Allow } };
        Assert.Equal(NotificationState.Granted, NotificationPolicy.State("https://mail.example", false, records));
        Assert.Equal(NotificationState.Denied, NotificationPolicy.State("https://mail.example", true, records));
        Assert.Equal(NotificationState.Default, NotificationPolicy.State("https://other.example", false, records));
        var a = WebNotification.Identifier("https://a", Guid.NewGuid(), new WebNotification("1", "x", Tag: "t"));
        var b = WebNotification.Identifier("https://a", Guid.NewGuid(), new WebNotification("2", "y", Tag: "t"));
        Assert.Equal(a, b);
    }

    [Fact]
    public void WindowsFileNamesAreSafe()
    {
        Assert.Equal("_CON.txt", DownloadSafety.Filename("CON.txt"));
        Assert.Equal("report", DownloadSafety.Filename("..\\report..."));
        Assert.Equal("ab.zip", DownloadSafety.Filename("a<b>.zip".Replace("<", "").Replace(">", "")));
        Assert.Equal("x.zip", DownloadSafety.Filename("C:\\Users\\x.zip"));
    }

    [Fact]
    public void KeymapAndGlyphsLoadFromShared()
    {
        Assert.Contains(Keymap.Windows["history"], s => s.Ctrl && s.Key == "H");
        Assert.Equal("Ctrl+Shift+T", Keymap.Label("reopen"));
        Assert.True(Glyphs.Known("puzzlepiece.extension"));
        Assert.Equal("\uE710", Glyphs.For("plus"));
    }

    [Fact]
    public void FirefoxProfilesIniDefaultFirst()
    {
        var parsed = GeckoReader.ParseProfiles("[General]\nStartWithLastProfile=1\n[Profile1]\nName=work\nPath=Profiles/b.work\nIsRelative=1\n[Profile0]\nName=default\nPath=Profiles/a.default\nDefault=1\n");
        Assert.Equal("default", parsed[0].Name);
        Assert.True(parsed[1].Relative);
    }

    [Fact]
    public void ChromiumBookmarksFlattenInOrder()
    {
        var json = """{"roots":{"bookmark_bar":{"children":[{"type":"url","url":"https://a.example","name":"A","date_added":"13300000000000000"},{"type":"folder","children":[{"type":"url","url":"https://b.example","name":""}]}]},"other":{"children":[{"type":"url","url":"javascript:void(0)","name":"x"}]}}}""";
        var bookmarks = ChromiumReader.Bookmarks(System.Text.Encoding.UTF8.GetBytes(json));
        Assert.Equal(["https://a.example", "https://b.example"], bookmarks.Select(b => b.Url));
        Assert.Equal("b.example", bookmarks[1].Title);
    }
}
