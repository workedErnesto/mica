using System.Text.Json.Nodes;
using Mica.Core;
using Mica.App.Downloads;

namespace Mica.App;

/// <summary>The window as the shell sees it: one JSON snapshot of everything it draws (windows/shell/js/shell/model.js
/// documents the shape). Built by hand with JsonNode so Native AOT needs no reflection. The library lists and the
/// settings data are large and change rarely, so they are sent only when their content changed.</summary>
public static class ShellState
{
    /// <summary>JsonArray.Add of a typed value is generic and needs reflection under Native AOT; a node does not.</summary>
    public static void Push(this JsonArray array, JsonNode? node) => array.Add(node);
    public static void Push(this JsonArray array, string? text) => array.Add((JsonNode?)text);

    static string Lower(string name) => name.Length == 0 ? name : char.ToLowerInvariant(name[0]) + name[1..];
    static string Raw<T>(T value) where T : struct, Enum => Lower(value.ToString());
    static JsonArray Strings(IEnumerable<string> items) { var a = new JsonArray(); foreach (var i in items) a.Push(i); return a; }
    static JsonArray Controls(IEnumerable<ToolbarControl> items) => Strings(items.Select(Raw));
    static long Millis(DateTimeOffset date) => date.ToUnixTimeMilliseconds();

    /// <summary>Look of the window in effect: theme, contrast, glass and accent come from its own profile, so windows of
    /// different profiles show their own themes side by side.</summary>
    public sealed record Look(bool Dark, bool Contrast, bool Glass, double ShellAlpha, double StartAlpha, string? Accent, string OnAccent, double AccentTint);

    public static Look LookOf(BrowserModel browser)
    {
        var p = browser.Prefs;
        var contrast = new global::Windows.UI.ViewManagement.AccessibilitySettings().HighContrast;
        var mode = p.Theme == Theme.Custom ? p.CustomBase : p.Theme;
        var settings = new global::Windows.UI.ViewManagement.UISettings();
        var dark = mode == Theme.System ? settings.GetColorValue(global::Windows.UI.ViewManagement.UIColorType.Background).R < 128 : mode == Theme.Dark;
        var glass = p.Frosted && settings.AdvancedEffectsEnabled && !contrast && Microsoft.UI.Composition.SystemBackdrops.DesktopAcrylicController.IsSupported();
        string? accent = p.Theme == Theme.Custom && HexColor.Parse(p.Accent) is not null ? p.Accent.ToUpperInvariant() : null;
        // Text on the accent takes whichever of white or ink gives more contrast (Look.swift).
        var luminance = accent is null ? 0 : HexColor.Luminance(accent) ?? 0;
        var onAccent = 1.05 / (luminance + 0.05) >= (luminance + 0.05) / 0.0618 ? "#FFFFFF" : "#1C1917";
        return new Look(dark, contrast, glass, Store.GlassTint(p), Store.StartTint(p), accent, onAccent, p.CustomTint);
    }

    /// <summary>Surface luminance of the theme: one-colour favicons below 3:1 against it are drawn in ink.</summary>
    static double Surface(bool dark) => dark ? FaviconTone.Luminance(0x2A, 0x27, 0x25) : 1;

    static JsonObject Profile(BrowserModel browser, Profile profile) => new()
    {
        ["id"] = profile.Id.ToString(),
        ["name"] = browser.ProfileName(profile),
        ["icon"] = profile.Icon,
        ["background"] = profile.Background,
        ["glyph"] = Raw(profile.Glyph),
        ["lightGlyph"] = Profiles.LightGlyph(profile.Background, profile.Glyph),
        ["standard"] = profile.IsStandard,
        ["open"] = browser.Store.Windows.Any(w => w.Model.ProfileId == profile.Id && !w.Model.PrivateMode),
    };

    /// <summary>Icon address the shell loads from ShellView, and whether a one-colour mark should be drawn in ink.</summary>
    static void Icon(JsonObject node, Favicons favicons, string? url, bool dark)
    {
        if (Favicons.Key(url) is not { } key || favicons.Icon(url) is not { } icon) return;
        node["icon"] = "https://mica.icons/" + Uri.EscapeDataString(key) + "?v=" + icon.Version;
        node["ink"] = icon.Glyph is { } glyph && FaviconTone.NeedsInk(glyph, Surface(dark));
    }

    static JsonObject Prefs(Preferences p)
    {
        var t = p.Toolbar;
        var start = new JsonArray();
        foreach (var s in p.Start.Shortcuts) start.Push(new JsonObject { ["id"] = s.Id.ToString(), ["title"] = s.Title, ["url"] = s.Url, ["host"] = AddressParser.Host(s.Url) });
        return new JsonObject
        {
            ["layout"] = p.Layout.RawValue(),
            ["theme"] = Raw(p.Theme), ["customBase"] = Raw(p.CustomBase), ["accent"] = p.Accent, ["customTint"] = p.CustomTint,
            ["frosted"] = p.Frosted, ["transparency"] = p.Transparency,
            ["userName"] = p.UserName, ["greetByName"] = p.GreetByName,
            ["sidebarCollapsed"] = p.SidebarCollapsed, ["sidebarWidth"] = p.SidebarWidth,
            ["language"] = p.Language == Language.En ? "en" : "ru", ["lowercase"] = p.Lowercase,
            ["toolbar"] = new JsonObject
            {
                ["leading"] = Controls(t.Leading), ["leadingInner"] = Controls(t.LeadingInner), ["trailingInner"] = Controls(t.TrailingInner),
                ["trailing"] = Controls(t.Trailing), ["sidebar"] = Controls(t.Sidebar), ["addressWidth"] = t.AddressWidth,
            },
            ["address"] = new JsonObject { ["full"] = p.Address.Full, ["dimSubdomain"] = p.Address.DimSubdomain, ["dimPath"] = p.Address.DimPath },
            ["start"] = new JsonObject
            {
                ["wordmark"] = p.Start.Wordmark, ["sections"] = Strings(p.Start.Sections.Select(Raw)), ["frequentCount"] = p.Start.FrequentCount,
                ["shortcuts"] = start, ["hiddenHosts"] = Strings(p.Start.HiddenHosts),
            },
        };
    }

    static bool SameToolbar(ToolbarLayout a, ToolbarLayout b) =>
        a.Leading.SequenceEqual(b.Leading) && a.LeadingInner.SequenceEqual(b.LeadingInner) && a.TrailingInner.SequenceEqual(b.TrailingInner)
        && a.Trailing.SequenceEqual(b.Trailing) && a.Sidebar.SequenceEqual(b.Sidebar) && a.AddressWidth == b.AddressWidth;

    static JsonObject Tab(BrowserModel browser, Tab tab, Look look)
    {
        var store = browser.Store;
        var url = tab.Url;
        var web = url is not null && (url.StartsWith("http://", StringComparison.OrdinalIgnoreCase) || url.StartsWith("https://", StringComparison.OrdinalIgnoreCase));
        var local = url is not null && url.StartsWith("file:", StringComparison.OrdinalIgnoreCase);
        var node = new JsonObject
        {
            ["id"] = tab.Id.ToString(),
            ["url"] = url,
            ["title"] = tab.Title,
            ["host"] = AddressParser.Host(url),
            ["start"] = tab.WebView is null && url is null,
            ["pinned"] = tab.Pinned,
            ["loading"] = tab.Loading,
            ["progress"] = tab.Progress,
            ["phase"] = Raw(tab.Phase),
            ["canBack"] = tab.CanBack, ["canForward"] = tab.CanForward,
            ["secure"] = tab.Secure, ["local"] = local,
            ["canSave"] = PageSaver.CanSave(tab),
            ["pinnable"] = web,
            ["pinnedToStart"] = url is not null && browser.Prefs.Start.Shortcuts.Any(s => s.Url == url),
            ["bookmarked"] = store.IsBookmarked(url),
            ["zoom"] = tab.Zoom,
            ["capturing"] = false,
            ["storeExtension"] = !browser.PrivateMode && url is not null && ChromeStore.ExtensionId(url) is { } id && !store.Extensions.Records.Any(r => r.Source == "cws:" + id),
        };
        if (url is not null)
        {
            var parts = new JsonArray();
            foreach (var part in AddressDisplay.Parts(url, browser.Prefs.Address)) parts.Push(new JsonObject { ["text"] = part.Text, ["dim"] = part.Dim });
            node["address"] = parts;
        }
        if (tab.Error is { } error) node["error"] = new JsonObject { ["message"] = error, ["certificate"] = tab.CertificateFailure };
        if (!tab.Loading && tab.Phase != TabPhase.Terminated) Icon(node, browser.Favicons, url, look.Dark);
        return node;
    }

    static JsonObject Start(BrowserModel browser, Look look, int seed)
    {
        var store = browser.Store;
        var p = browser.Prefs;
        var options = p.Start;
        var sections = new JsonArray();
        JsonObject Site(string id, string title, string url, Guid? shortcut)
        {
            var site = new JsonObject { ["id"] = id, ["title"] = title, ["url"] = url, ["host"] = AddressParser.Host(url) };
            if (shortcut is { } s) site["shortcut"] = s.ToString();
            Icon(site, browser.Favicons, url, look.Dark);
            return site;
        }
        foreach (var section in Enum.GetValues<StartSection>())
        {
            var sites = new JsonArray();
            switch (section)
            {
                case StartSection.Custom:
                    foreach (var s in options.Shortcuts) sites.Push(Site(s.Id.ToString(), s.Title, s.Url, s.Id));
                    break;
                case StartSection.Frequent:
                    if (!browser.PrivateMode)
                    {
                        var excluded = options.Shortcuts.Select(s => AddressParser.Host(s.Url)?.ToLowerInvariant()).OfType<string>().ToHashSet();
                        excluded.UnionWith(options.HiddenHosts);
                        foreach (var v in Mica.Core.StartPage.Frequent(store.History, excluded, options.FrequentCount)) sites.Push(Site("f-" + v.Host, "", v.Url, null));
                    }
                    break;
                default:
                    foreach (var v in store.Bookmarks.Take(options.FrequentCount)) sites.Push(Site("b-" + v.Id, v.Title, v.Url, null));
                    break;
            }
            sections.Push(new JsonObject { ["section"] = Raw(section), ["sites"] = sites });
        }
        var defaults = new Mica.Core.StartPage();
        return new JsonObject
        {
            ["greeting"] = Greeting.Text(p, DateTime.Now.Hour, seed),
            ["searchTitle"] = store.Preferences.Search.Title(browser.TextStyle.Language),
            ["isDefault"] = options.Sections.SequenceEqual(defaults.Sections) && options.Wordmark == defaults.Wordmark && options.FrequentCount == defaults.FrequentCount,
            ["sections"] = sections,
        };
    }

    static JsonObject? Site(BrowserModel browser)
    {
        if (browser.Selected is not { Url: { } url }) return null;
        var store = browser.Store;
        var node = new JsonObject();
        if (url.StartsWith("file:", StringComparison.OrdinalIgnoreCase) && Uri.TryCreate(url, UriKind.Absolute, out var file))
        {
            node["fileName"] = Path.GetFileName(file.LocalPath);
            node["filePath"] = file.LocalPath;
            return node;
        }
        if (AddressParser.Host(url) is { } host)
        {
            node["host"] = host;
            node["blocking"] = store.Preferences.Blocking && !store.Preferences.BlockingExceptions.Contains(host);
        }
        if (Origin.Of(url) is { } origin)
        {
            node["origin"] = origin;
            var permissions = new JsonArray();
            foreach (var capability in Enum.GetValues<SiteCapability>())
            {
                if (browser.PrivateMode && capability == SiteCapability.Notifications) continue;
                permissions.Push(new JsonObject { ["capability"] = Raw(capability), ["decision"] = Raw(store.DecisionFor(origin, capability, browser)) });
            }
            node["permissions"] = permissions;
        }
        return node;
    }

    public static JsonObject Library(BrowserModel browser, Look look)
    {
        var store = browser.Store;
        var library = new JsonObject();
        switch (browser.Panel)
        {
            case LibraryPanel.History:
            case LibraryPanel.Bookmarks:
            {
                var list = new JsonArray();
                var history = browser.Panel == LibraryPanel.History;
                // The panel lists the newest thousand; search in the panel filters them.
                foreach (var visit in (history ? (browser.PrivateMode ? [] : store.History) : store.Bookmarks).Take(1000))
                {
                    var node = new JsonObject { ["id"] = visit.Id.ToString(), ["url"] = visit.Url, ["title"] = visit.Title, ["host"] = visit.Host, ["time"] = Millis(visit.Date), ["profile"] = Profiles.Owner(visit).ToString() };
                    Icon(node, browser.Favicons, visit.Url, look.Dark);
                    list.Push(node);
                }
                library[history ? "history" : "bookmarks"] = list;
                break;
            }
            case LibraryPanel.Downloads:
            {
                var list = new JsonArray();
                var downloads = PageSaver.DownloadsFolder;
                foreach (var item in browser.Downloads.Items.OrderByDescending(i => i.Date ?? DateTimeOffset.MinValue))
                {
                    var ext = Path.GetExtension(item.Name).TrimStart('.');
                    string? folder = null;
                    if (item.State == DownloadState.Complete && item.Destination is { } path && Path.GetDirectoryName(path) is { } directory)
                        folder = string.Equals(Path.GetFullPath(directory).TrimEnd('\\'), Path.GetFullPath(downloads).TrimEnd('\\'), StringComparison.OrdinalIgnoreCase)
                            ? browser.Text("загрузки", "Загрузки") : Path.GetFileName(directory.TrimEnd('\\'));
                    list.Push(new JsonObject
                    {
                        ["id"] = item.Id.ToString(), ["name"] = item.Name, ["kind"] = Raw(item.Kind), ["ext"] = ext,
                        ["state"] = Raw(item.State), ["active"] = item.Active, ["justFinished"] = item.JustFinished, ["saving"] = item.Saving,
                        ["bytes"] = item.Bytes, ["total"] = item.Total, ["fraction"] = item.Fraction, ["size"] = item.Size,
                        ["time"] = item.Date is { } date ? Millis(date) : null, ["folder"] = folder, ["failure"] = item.FailureText, ["source"] = item.Source,
                        ["resumable"] = item.Operation?.CanResume == true,
                    });
                }
                library["downloads"] = list;
                break;
            }
            case LibraryPanel.Extensions:
            {
                var manager = store.Extensions;
                var records = new JsonArray();
                foreach (var r in manager.Records)
                    records.Push(new JsonObject
                    {
                        ["id"] = r.Id.ToString(), ["name"] = r.Name, ["version"] = r.Version, ["enabled"] = r.Enabled, ["source"] = r.Source,
                        ["permissions"] = Strings(r.Permissions), ["hosts"] = Strings(r.Hosts), ["error"] = manager.Errors.GetValueOrDefault(r.Id),
                        // WebView2 runs extensions without toolbar popups or option pages.
                        ["options"] = false,
                    });
                var extensions = new JsonObject { ["records"] = records, ["status"] = manager.ChromeStatus, ["busy"] = manager.Busy };
                if (browser.Selected?.Url is { } url && ChromeStore.ExtensionId(url) is { } id)
                {
                    var title = browser.Selected.Title.Replace(" - Chrome Web Store", "").Trim();
                    extensions["currentStoreItem"] = new JsonObject { ["id"] = id, ["name"] = title.Length == 0 ? "Chrome Web Store" : title, ["installed"] = manager.Records.Any(r => r.Source == "cws:" + id) };
                }
                library["extensions"] = extensions;
                break;
            }
        }
        return library;
    }

    public static JsonObject Settings(BrowserModel browser)
    {
        var store = browser.Store;
        var p = store.Preferences;
        var engines = new JsonArray();
        foreach (var engine in Enum.GetValues<SearchEngine>())
            engines.Push(new JsonObject { ["id"] = engine.RawValue(), ["title"] = engine.Title(browser.TextStyle.Language), ["host"] = AddressParser.Host(engine.Home()) });
        var sample = new JsonArray();
        foreach (var part in AddressDisplay.Parts("https://shop.example.com/shoes/running?size=42", browser.Prefs.Address)) sample.Push(new JsonObject { ["text"] = part.Text, ["dim"] = part.Dim });
        var permissions = new JsonArray();
        foreach (var record in store.Permissions) permissions.Push(new JsonObject { ["origin"] = record.Origin, ["capability"] = Raw(record.Capability), ["decision"] = Raw(record.Decision) });
        var icons = new JsonArray();
        foreach (var set in Appearance.AppIcons.Sets)
            foreach (var icon in set.Icons)
                if (Appearance.AppIcons.Png(icon.Id) is not null)
                    icons.Push(new JsonObject { ["id"] = icon.Id, ["title"] = browser.Text(icon.Low, icon.Regular), ["image"] = "https://mica.icons/app/" + icon.Id });
        var passwords = store.Passwords;
        var logins = new JsonArray();
        foreach (var login in passwords.Vault.Logins.OrderBy(l => l.Origin, StringComparer.Ordinal)) logins.Push(new JsonObject { ["id"] = login.Id.ToString(), ["origin"] = login.Origin, ["username"] = login.Username });
        var importer = store.Importer;
        var browsers = new JsonArray();
        foreach (var profile in importer.Profiles)
        {
            var running = importer.State == Import.ImportManager.Phase.Reading && importer.Selection == profile.Id;
            browsers.Push(new JsonObject
            {
                ["id"] = profile.Id, ["name"] = importer.Title(profile) + (profile.Name.Length > 0 ? ", " + profile.Name : ""),
                ["detail"] = importer.Selection == profile.Id && importer.Result is { } r ? ImportResult(browser, r) : null,
                ["running"] = running,
            });
        }
        return new JsonObject
        {
            ["section"] = browser.SettingsSection,
            ["isDefault"] = SafeIsDefault(),
            ["defaultBusy"] = false,
            ["addressSample"] = sample,
            ["engines"] = engines,
            ["search"] = p.Search.RawValue(),
            ["blocking"] = p.Blocking,
            ["blockerCount"] = store.Blocker.Count,
            ["blockerStatus"] = store.Blocker.Status,
            ["blockerUpdating"] = store.Blocker.Updating,
            ["blockingExceptions"] = Strings(p.BlockingExceptions),
            ["restore"] = p.Restore, ["lazyRestore"] = p.LazyRestore, ["eagerHosts"] = Strings(p.EagerHosts),
            ["notificationRequests"] = p.NotificationRequests,
            ["permissions"] = permissions,
            ["offerPasswords"] = p.OfferPasswords, ["fillPasswords"] = p.FillPasswords,
            ["passwords"] = new JsonObject
            {
                ["logins"] = logins, ["never"] = Strings(passwords.Vault.Never),
                ["status"] = passwords.Loading ? browser.Text("открываем хранилище…", "Открываем хранилище…") : passwords.Error is { } e ? browser.Text("хранилище недоступно: ", "Хранилище недоступно: ") + e : null,
                ["revealed"] = ShellCommands.Revealed?.ToString(), ["secret"] = ShellCommands.RevealedSecret, ["copied"] = ShellCommands.Copied?.ToString(),
            },
            ["importer"] = new JsonObject
            {
                ["browsers"] = browsers,
                ["running"] = importer.State == Import.ImportManager.Phase.Reading,
                ["message"] = importer.State == Import.ImportManager.Phase.Failed ? importer.Failure : importer.Result is { } result && importer.Selected is null ? ImportResult(browser, result) : null,
                ["failed"] = importer.State == Import.ImportManager.Phase.Failed,
            },
            ["version"] = Update.Updater.CurrentVersion?.ToString(),
            ["updateChecks"] = p.UpdateChecks,
            ["profileOpening"] = Raw(p.ProfileOpening),
            ["editingProfile"] = (browser.EditingProfile ?? browser.ProfileId).ToString(),
            ["appIcon"] = p.AppIcon ?? Appearance.AppIcons.Standard,
            ["appIcons"] = icons,
            ["defaultFailed"] = ShellCommands.DefaultBrowserFailed,
        };
    }

    static bool SafeIsDefault()
    {
        try { return Mica.Install.DefaultBrowser.IsDefault(); }
        catch (Exception e) when (e is UnauthorizedAccessException or IOException or System.Security.SecurityException) { return false; }
    }

    static string ImportResult(BrowserModel browser, Import.ImportManager.Summary r)
    {
        var text = browser.Text("перенесено: история ", "Перенесено: история ") + r.History + browser.Text(", закладки ", ", закладки ") + r.Bookmarks;
        return r.Problems.Count == 0 ? text : text + ". " + string.Join(". ", r.Problems);
    }

    /// <summary>The whole snapshot. <paramref name="library"/> and <paramref name="settings"/> are left out when null:
    /// the shell keeps what it received before.</summary>
    public static JsonObject Build(BrowserModel browser, BrowserWindow window, Look look, int seed, JsonObject? library, JsonObject? settings)
    {
        var store = browser.Store;
        var prefs = browser.Prefs;
        var tabs = new JsonArray();
        foreach (var tab in browser.Tabs) tabs.Push(Tab(browser, tab, look));
        var profiles = new JsonArray();
        foreach (var profile in store.Profiles) profiles.Push(Profile(browser, profile));
        var saving = browser.Downloads.Items.FirstOrDefault(d => d.Saving && d.State == DownloadState.Running && d.Page == browser.Selected);
        JsonObject? alert = null;
        if (browser.Questions.FirstOrDefault() is { } q)
        {
            var fields = new JsonArray();
            foreach (var f in q.Fields ?? []) fields.Push(new JsonObject { ["label"] = f.Label, ["value"] = f.Value, ["secret"] = f.Secret });
            alert = new JsonObject
            {
                ["id"] = q.Id, ["title"] = q.Title, ["text"] = q.Text, ["buttons"] = Strings(q.Buttons), ["destructive"] = q.Destructive,
                ["choices"] = q.Choices is null ? null : Strings(q.Choices), ["fields"] = fields, ["cancel"] = 0,
            };
        }
        var clear = store.Preferences.Clearing;
        var state = new JsonObject
        {
            ["system"] = new JsonObject
            {
                ["captionInset"] = window.CaptionInset, ["captionHeight"] = BrowserWindow.Bar,
                ["reducedMotion"] = !new global::Windows.UI.ViewManagement.UISettings().AnimationsEnabled,
            },
            ["window"] = new JsonObject { ["isPrivate"] = browser.PrivateMode, ["fullScreen"] = browser.FullScreen },
            ["appearance"] = new JsonObject
            {
                ["dark"] = look.Dark, ["contrast"] = look.Contrast, ["glass"] = look.Glass, ["shellAlpha"] = look.ShellAlpha, ["startAlpha"] = look.StartAlpha,
                ["accent"] = look.Accent, ["onAccent"] = look.OnAccent, ["accentTint"] = look.AccentTint,
            },
            ["text"] = new JsonObject { ["language"] = browser.TextStyle.Language == Language.En ? "en" : "ru", ["lowercase"] = browser.TextStyle.Lowercase },
            ["profile"] = Profile(browser, browser.Profile),
            ["profiles"] = profiles,
            ["profileLimit"] = Profiles.Limit,
            ["prefs"] = Prefs(prefs),
            ["toolbarIsDefault"] = SameToolbar(prefs.Toolbar, new ToolbarLayout()),
            ["tabs"] = tabs,
            ["selectedId"] = browser.SelectedId?.ToString(),
            ["closedCount"] = browser.Closed.Count,
            ["panel"] = browser.Panel is { } panel ? Raw(panel) : null,
            ["saving"] = saving is null ? null : new JsonObject { ["fraction"] = saving.Fraction },
            ["overlay"] = new JsonObject
            {
                ["commandBar"] = browser.CommandBar, ["find"] = browser.ShowFind,
                ["settings"] = browser.ShowSettings, ["onboarding"] = browser.ShowOnboarding, ["onboardingStep"] = browser.OnboardingStep,
                ["clearData"] = browser.ShowClearData, ["profilePrompt"] = browser.ProfilePrompt?.ToString(), ["alert"] = alert,
                ["customizingToolbar"] = browser.CustomizingToolbar, ["customizingStart"] = browser.CustomizingStart,
                ["quitHold"] = browser.QuitHolding ? QuitHold.Duration : null,
            },
            ["start"] = Start(browser, look, seed),
            ["site"] = Site(browser),
            ["findResult"] = ShellCommands.FindResult(browser),
            ["clearData"] = browser.ShowClearData ? new JsonObject
            {
                ["period"] = Raw(clear.Period), ["history"] = clear.History, ["siteData"] = clear.SiteData, ["cache"] = clear.Cache, ["permissions"] = clear.Permissions,
                ["visits"] = HistoryOps.Count(store.History, clear.Period.Start(DateTimeOffset.Now)), ["working"] = ShellCommands.Clearing,
            } : null,
        };
        if (library is not null) state["library"] = library;
        if (settings is not null) state["settings"] = settings;
        return state;
    }
}
