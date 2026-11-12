using System.Text.Json;
using System.Text.Json.Nodes;
using Mica.Core;
using Mica.App.Downloads;
using Windows.ApplicationModel.DataTransfer;

namespace Mica.App;

/// <summary>What the shell asks the window to do. Every name here is one the shell sends (windows/shell/js); the
/// actions are the same model calls the macOS views make.</summary>
public static class ShellCommands
{
    /// <summary>Password shown after Windows Hello, and the one just copied; both clear after a while.</summary>
    public static Guid? Revealed { get; private set; }
    public static string? RevealedSecret { get; private set; }
    public static Guid? Copied { get; private set; }
    public static bool DefaultBrowserFailed { get; private set; }
    public static bool Clearing { get; private set; }

    static string? Str(JsonElement a, string key) => a.ValueKind == JsonValueKind.Object && a.TryGetProperty(key, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;
    static bool Bool(JsonElement a, string key) => a.ValueKind == JsonValueKind.Object && a.TryGetProperty(key, out var v) && v.ValueKind == JsonValueKind.True;
    static bool Has(JsonElement a, string key) => a.ValueKind == JsonValueKind.Object && a.TryGetProperty(key, out var v) && v.ValueKind != JsonValueKind.Null;
    static double Num(JsonElement a, string key, double fallback = 0) => a.ValueKind == JsonValueKind.Object && a.TryGetProperty(key, out var v) && v.ValueKind == JsonValueKind.Number ? v.GetDouble() : fallback;
    static Guid? Id(JsonElement a, string key = "id") => Guid.TryParse(Str(a, key), out var id) ? id : null;
    static T? Enum<T>(string? raw) where T : struct, System.Enum => raw is not null && System.Enum.TryParse<T>(raw, ignoreCase: true, out var value) ? value : null;

    static Tab? TabOf(BrowserModel b, JsonElement a) => Id(a) is { } id ? b.Tabs.FirstOrDefault(t => t.Id == id) : b.Selected;

    static void CopyText(string text) { var data = new DataPackage(); data.SetText(text); Clipboard.SetContent(data); }

    /// <summary>Runs a command; a request returns its reply, anything else null.</summary>
    public static async Task<JsonNode?> Run(BrowserModel b, string name, JsonElement a)
    {
        var store = b.Store;
        switch (name)
        {
            // Tabs
            case "tab.new": b.Add(); b.FocusAddress(); break;
            case "tab.select": if (TabOf(b, a) is { } select) b.Select(select); break;
            case "tab.close": if (TabOf(b, a) is { } close) b.Close(close); break;
            case "tab.move": if (Id(a) is { } moving && Id(a, "before") is { } before) b.Move(moving, before); break;
            case "tab.pin": if (TabOf(b, a) is { } pin) b.Pin(pin); break;
            case "tab.duplicate": if (TabOf(b, a) is { } dup) b.Add(new SavedTab { Url = dup.Url, Title = dup.Title }); break;
            case "tab.copyAddress": if (TabOf(b, a)?.Url is { } address) CopyText(address); break;
            case "tab.toNewWindow": if (TabOf(b, a) is { } moved) { var window = store.NewWindow(b.PrivateMode); if (moved.Url is { } u) window.Selected?.Load(u); } break;
            case "tab.closeOthers": if (TabOf(b, a) is { } keep) foreach (var other in b.Tabs.Where(t => t.Id != keep.Id && !t.Pinned).ToList()) b.Close(other); break;
            case "tab.closeAll": b.CloseAll(); break;
            case "tab.reload": TabOf(b, a)?.Reload(); break;
            case "tab.stop": TabOf(b, a)?.Stop(); break;
            case "tab.back": if (TabOf(b, a) is { } back) { back.Error = null; back.GoBack(); back.Changed2(); } break;

            // Navigation and the command bar
            case "open":
                if (Str(a, "url") is { } openUrl)
                {
                    if (Bool(a, "newWindow")) store.NewWindow(b.PrivateMode, profile: b.ProfileId).Selected?.Load(openUrl);
                    else if (Bool(a, "newTab")) b.Open(openUrl);
                    else b.Selected?.Load(openUrl);
                }
                break;
            case "navigate": if (Str(a, "text") is { Length: > 0 } text) { b.Navigate(text); b.CommandBar = false; } break;
            case "suggestion.open":
                if (Id(a, "tab") is { } tabId && b.Tabs.FirstOrDefault(t => t.Id == tabId) is { } target) b.Select(target);
                else if (Str(a, "url") is { } suggested) b.Selected?.Load(suggested);
                b.CommandBar = false;
                break;
            case "suggest": return Suggest(b, Str(a, "text") ?? "");
            case "commandBar": b.CommandBar = Bool(a, "on") && b.Selected?.Url is not null; break;
            case "copy": if (Str(a, "text") is { } copy) CopyText(copy); break;
            case "command": if (Str(a, "name") is { } command) Commands.Run(b, command); break;
            case "key": if (Str(a, "command") is { } key) Commands.FromShell(b, key); break;

            // Window state
            case "panel.set": b.Panel = Enum<LibraryPanel>(Str(a, "panel")); break;
            case "customize.toolbar": b.ShowSettings = false; b.CustomizingToolbar = Bool(a, "on"); break;
            case "customize.start": b.CustomizingStart = Bool(a, "on"); break;
            case "prefs.set": SetPref(b, Str(a, "path") ?? "", a.TryGetProperty("value", out var value) ? value : default); break;

            // Toolbar
            case "toolbar.move":
                if (Enum<ToolbarControl>(Str(a, "item")) is { } item && Enum<ToolbarZone>(Str(a, "zone")) is { } zone)
                {
                    var beforeItem = Enum<ToolbarControl>(Str(a, "before"));
                    b.Change(p => { if (zone == ToolbarZone.Hidden) p.Toolbar.Insert(item, ToolbarZone.Hidden); else p.Toolbar.Insert(item, zone, beforeItem); });
                }
                break;
            case "toolbar.addressWidth": b.Change(p => p.Toolbar.AddressWidth = Math.Clamp(Num(a, "value", 560), ToolbarLayout.AddressMin, ToolbarLayout.AddressMax)); break;
            case "toolbar.reset": b.Change(p => p.Toolbar = new ToolbarLayout()); break;

            // Start page
            case "start.saveShortcut": return SaveShortcut(b, a);
            case "start.setVisible": if (Enum<StartSection>(Str(a, "section")) is { } visible) b.Change(p => p.Start.SetVisible(visible, Bool(a, "on"))); break;
            case "start.wordmark": b.Change(p => p.Start.Wordmark = Bool(a, "on")); break;
            case "start.frequentCount": b.Change(p => p.Start.FrequentCount = (int)Num(a, "value", 8)); break;
            case "start.shiftSection": if (Enum<StartSection>(Str(a, "section")) is { } shifted) b.Change(p => p.Start.Shift(shifted, (int)Num(a, "by"))); break;
            case "start.removeShortcut": if (Id(a) is { } removed) b.Change(p => p.Start.Shortcuts.RemoveAll(s => s.Id == removed)); break;
            case "start.moveShortcut": if (Id(a) is { } source && Id(a, "before") is { } dest) b.Change(p => p.Start.MoveShortcut(source, dest)); break;
            case "start.shiftShortcut": if (Id(a) is { } shortcut) b.Change(p => p.Start.ShiftShortcut(shortcut, (int)Num(a, "by"))); break;
            case "start.hideHost": if (Str(a, "host")?.ToLowerInvariant() is { } hide) b.Change(p => { if (!p.Start.HiddenHosts.Contains(hide)) p.Start.HiddenHosts.Add(hide); }); break;
            case "start.unhideHost": if (Str(a, "host") is { } unhide) b.Change(p => p.Start.HiddenHosts.Remove(unhide)); break;
            case "start.reset": b.Change(p => { var d = new Mica.Core.StartPage(); p.Start.Sections = [.. d.Sections]; p.Start.Wordmark = d.Wordmark; p.Start.FrequentCount = d.FrequentCount; }); break;
            case "start.pin": if (Str(a, "url") is { } pinUrl) b.Change(p => { p.Start.Shortcuts.Add(new StartShortcut { Url = pinUrl, Title = Str(a, "title") ?? "" }); p.Start.SetVisible(StartSection.Custom, true); }); break;
            case "start.unpinPage": if (Str(a, "url") is { } unpin) b.RemoveStartShortcut(unpin); break;

            // Site
            case "site.permission":
                if (Str(a, "origin") is { } origin && Enum<SiteCapability>(Str(a, "capability")) is { } capability && Enum<Decision>(Str(a, "decision")) is { } decision)
                { store.SetPermission(origin, capability, decision, b); Observable.TouchAll(); }
                break;
            case "site.blocking":
                if (Str(a, "host") is { } host)
                {
                    var on = Bool(a, "on");
                    store.Change(b.ProfileId, p => { if (on) { var inherited = DomainBlocker.MatchingExceptions(host, p.BlockingExceptions); p.BlockingExceptions.RemoveAll(inherited.Contains); p.Blocking = true; } else if (!p.BlockingExceptions.Contains(host)) p.BlockingExceptions.Add(host); });
                }
                break;
            case "site.stopCapture": break;
            case "page.save": if (b.Selected is { } page && Enum<PageFormat>(Str(a, "format")) is { } format) PageSaver.Save(page, b, format); break;

            // Find
            case "find.run": await Find(b, Str(a, "query") ?? "", Bool(a, "back")); break;
            case "find.close": b.ShowFind = false; b.Selected?.Core?.Find.Stop(); finds.Remove(b.Id); break;

            // Library
            case "history.remove": if (Id(a) is { } visit) store.SetHistory(store.History.Where(v => v.Id != visit).ToList()); break;
            case "history.removeHost": if (Str(a, "host") is { } site) store.SetHistory(HistoryOps.RemovingHost(store.History, site)); break;
            case "bookmarks.remove": if (Id(a) is { } mark) store.SetBookmarks(store.Bookmarks.Where(v => v.Id != mark).ToList()); break;
            case "download.cancel": Download(b, a)?.Cancel(); break;
            case "download.retry": Download(b, a)?.Retry(); break;
            case "download.reveal": Download(b, a)?.Reveal(); break;
            case "download.open": Download(b, a)?.Open(); break;
            case "download.remove": if (Download(b, a) is { } listed) b.Downloads.Remove(listed); break;
            case "extension.toggle": if (Extension(b, a) is { } toggled) await store.Extensions.ToggleAsync(toggled); break;
            case "extension.remove":
                if (Extension(b, a) is { } doomed && await Dialogs.Ask(b.Window, b.Text("удалить расширение?", "Удалить расширение?"), doomed.Name, [b.Text("отмена", "Отмена"), b.Text("удалить", "Удалить")], destructive: true) == 1)
                    await store.Extensions.RemoveAsync(doomed);
                break;
            case "extension.import": if (b.Window is { } w) store.Extensions.ChooseImport(Win32.Handle(w)); break;
            case "extension.installFromStore": await store.Extensions.InstallFromChromeStoreAsync(Str(a, "input") ?? ""); break;
            case "extensions.installFromPage":
                if (b.Selected?.Url is { } storePage) { b.Panel = LibraryPanel.Extensions; await store.Extensions.InstallFromChromeStoreAsync(storePage); }
                break;
            case "extension.action": case "extension.options": break;

            // Window-level cards
            case "settings.open":
                if (Str(a, "section") is { } section) b.SettingsSection = section;
                if (Id(a, "profile") is { } editing) b.EditingProfile = editing;
                if (b.SettingsSection == "transfer" && !store.Importer.Discovered) store.Importer.Discover();
                if (b.SettingsSection == "passwords") _ = store.Passwords.EnsureLoadedAsync();
                b.ShowSettings = true;
                break;
            case "settings.close": b.ShowSettings = false; Revealed = null; RevealedSecret = null; break;
            case "settings.draft": break;
            case "settings.set": SetSetting(b, Str(a, "key") ?? "", a.TryGetProperty("value", out var setting) ? setting : default); break;
            case "settings.search": if (SearchEngines.Parse(Str(a, "engine")) is { } engine) store.Change(b.ProfileId, p => p.Search = engine); break;
            case "settings.updateBlocklist": await store.UBlock.UpdateAsync(); break;
            case "settings.makeDefault":
                DefaultBrowserFailed = false;
                try { Mica.Install.DefaultBrowser.Register(); await Mica.Install.DefaultBrowser.OpenSettingsAsync(); }
                catch (Exception e) when (e is UnauthorizedAccessException or IOException or System.Security.SecurityException) { Diagnostics.Log.Error(e); DefaultBrowserFailed = true; }
                b.Touch();
                break;
            case "settings.appIcon": if (Str(a, "id") is { } icon) store.Change(b.ProfileId, p => p.AppIcon = icon == Appearance.AppIcons.Standard ? null : icon); break;
            case "settings.hosts":
                if (a.TryGetProperty("hosts", out var hosts) && hosts.ValueKind == JsonValueKind.Array && Str(a, "key") is "eagerHosts" or "blockingExceptions")
                {
                    try {
                        var list = DomainBlocker.ParseDomains(string.Join("\n", hosts.EnumerateArray().Where(h => h.ValueKind == JsonValueKind.String).Select(h => h.GetString())));
                        store.Change(b.ProfileId, p => { if (Str(a, "key") == "blockingExceptions") p.BlockingExceptions = list; else p.EagerHosts = list; });
                    } catch (FormatException) { store.Issue = b.Text("нужен домен без пути, например mail.example.com", "Нужен домен без пути, например mail.example.com"); }
                }
                break;
            case "settings.editProfile": if (Id(a) is { } profileId) { b.EditingProfile = profileId; b.Touch(); } break;
            case "system.settings": if (Str(a, "uri") is { } uri && uri.StartsWith("ms-settings:", StringComparison.Ordinal)) await Windows.System.Launcher.LaunchUriAsync(new Uri(uri)); break;

            case "onboarding.open": b.ShowSettings = false; b.OnboardingStep = 0; b.ShowOnboarding = true; break;
            case "onboarding.step": b.OnboardingStep = Math.Clamp((int)Num(a, "step"), 0, 5); if (b.OnboardingStep == 1 && !store.Importer.Discovered) store.Importer.Discover(); b.Touch(); break;
            case "onboarding.finish": store.Change(b.ProfileId, p => p.OnboardingComplete = true); b.ShowOnboarding = false; break;

            case "clearData.open": if (!b.PrivateMode) b.ShowClearData = true; break;
            case "clearData.close": b.ShowClearData = false; break;
            case "clearData.set": SetClearing(b, Str(a, "key") ?? "", a.TryGetProperty("value", out var clearValue) ? clearValue : default); break;
            case "clearData.run":
                if (Clearing) break;
                Clearing = true; b.Touch();
                try { await store.ClearAsync(store.Preferences.Clearing); }
                finally { Clearing = false; b.ShowClearData = false; }
                break;

            // Profiles
            case "profile.open": if (Id(a) is { } open) OpenProfile(b, open, Str(a, "where"), a); break;
            case "profilePrompt.close": b.ProfilePrompt = null; break;
            case "profile.add":
                if (store.Profiles.Count < Profiles.Limit) { var created = store.AddProfile(b.ProfileId); b.EditingProfile = created.Id; b.SettingsSection = "profiles"; b.ShowSettings = true; }
                break;
            case "profile.rename": if (Id(a) is { } renamed) store.ChangeProfile(renamed, p => p.Name = Str(a, "name") ?? ""); break;
            case "profile.look":
                if (Id(a) is { } looked)
                    store.ChangeProfile(looked, p =>
                    {
                        if (Str(a, "icon") is { } i && ProfileCatalog.Icons.Contains(i)) p.Icon = i;
                        if (Str(a, "background") is { } bg && HexColor.Parse(bg) is not null) p.Background = bg.ToUpperInvariant();
                        if (Enum<ProfileGlyph>(Str(a, "glyph")) is { } g) p.Glyph = g;
                    });
                break;
            case "profile.remove":
                if (Id(a) is { } gone && gone != Profile.StandardId)
                {
                    var profile = store.Profile(gone);
                    if (await Dialogs.Ask(b.Window, b.Text("удалить профиль ", "Удалить профиль ") + b.Quoted(b.ProfileName(profile)) + "?",
                        b.Text("окна профиля перейдут в основной профиль. история и данные сайтов останутся.", "Окна профиля перейдут в основной профиль. История и данные сайтов останутся."),
                        [b.Text("отмена", "Отмена"), b.Text("удалить", "Удалить")], destructive: true) == 1)
                    { store.RemoveProfile(gone); b.EditingProfile = b.ProfileId; }
                }
                break;

            // Passwords
            case "passwords.reveal":
                if (Id(a) is { } shown)
                {
                    if (Revealed == shown) { Revealed = null; RevealedSecret = null; b.Touch(); break; }
                    if (!await store.Passwords.AuthenticateAsync(b.Window)) break;
                    var login = store.Passwords.Vault.Logins.FirstOrDefault(l => l.Id == shown);
                    Revealed = login?.Id; RevealedSecret = login?.Password; b.Touch();
                }
                break;
            case "passwords.copy":
                if (Id(a) is { } copied && store.Passwords.Vault.Logins.FirstOrDefault(l => l.Id == copied) is { } entry && await store.Passwords.AuthenticateAsync(b.Window))
                {
                    CopyText(entry.Password); Copied = entry.Id; b.Touch();
                    await Task.Delay(1500); if (Copied == entry.Id) { Copied = null; b.Touch(); }
                }
                break;
            case "passwords.remove":
                if (Id(a) is { } removedLogin && store.Passwords.Vault.Logins.FirstOrDefault(l => l.Id == removedLogin) is { } doomedLogin
                    && await Dialogs.Ask(b.Window, b.Text("удалить пароль?", "Удалить пароль?"), doomedLogin.Origin + "\n" + doomedLogin.Username, [b.Text("отмена", "Отмена"), b.Text("удалить", "Удалить")], destructive: true) == 1)
                    store.Passwords.Update(v => v.Logins.RemoveAll(l => l.Id == removedLogin));
                break;
            case "passwords.removeNever": if (Str(a, "origin") is { } never) store.Passwords.Update(v => v.Never.Remove(never)); break;

            // Data transfer
            case "import.run":
                if (Str(a, "browser") is { } importId && store.Importer.Profiles.FirstOrDefault(p => p.Id == importId) is { } importProfile)
                { store.Importer.Select(importProfile); store.Importer.Run(); }
                break;
            case "import.choose": if (b.Window is { } importWindow) store.Importer.ChooseExport(Win32.Handle(importWindow)); break;
            case "import.profile": break;

            case "alert.answer":
                if ((int)Num(a, "id", -1) is var question and >= 0)
                {
                    var values = a.TryGetProperty("values", out var v) && v.ValueKind == JsonValueKind.Array ? v.EnumerateArray().Select(x => x.GetString() ?? "").ToArray() : [];
                    Dialogs.Answer(b, question, (int)Num(a, "index"), values);
                }
                break;
            case "app.quit": await Commands.Quit(store); break;
            default: Diagnostics.Log.Error(new InvalidOperationException("unknown shell command " + name)); break;
        }
        return null;
    }

    static DownloadItem? Download(BrowserModel b, JsonElement a) => Id(a) is { } id ? b.Downloads.Items.FirstOrDefault(d => d.Id == id) : null;
    static ExtensionRecord? Extension(BrowserModel b, JsonElement a) => Id(a) is { } id ? b.Store.Extensions.Records.FirstOrDefault(r => r.Id == id) : null;

    static void OpenProfile(BrowserModel b, Guid id, string? where, JsonElement a)
    {
        var store = b.Store;
        var fromPrompt = Has(a, "remember");
        if (fromPrompt && Bool(a, "remember") && where is not null)
            store.Change(b.ProfileId, p => p.ProfileOpening = where == "here" ? ProfileOpening.Here : ProfileOpening.NewWindow);
        b.ProfilePrompt = null;
        switch (where)
        {
            case "here": b.SwitchProfile(id); break;
            // The prompt brings an open window of the profile forward; the right-click choice always opens a new one.
            case "newWindow": store.OpenProfile(id, newWindow: !fromPrompt); break;
            default:
                if (id == b.ProfileId) return;
                switch (store.Preferences.ProfileOpening)
                {
                    case ProfileOpening.Ask: b.ProfilePrompt = id; break;
                    case ProfileOpening.Here: b.SwitchProfile(id); break;
                    default: store.OpenProfile(id); break;
                }
                break;
        }
    }

    static void SetPref(BrowserModel b, string path, JsonElement value)
    {
        bool flag = value.ValueKind == JsonValueKind.True;
        double number = value.ValueKind == JsonValueKind.Number ? value.GetDouble() : 0;
        string? text = value.ValueKind == JsonValueKind.String ? value.GetString() : null;
        switch (path)
        {
            case "layout": if (TabLayouts.Parse(text) is { } layout) b.Change(p => p.Layout = layout); break;
            case "sidebarCollapsed": b.Change(p => p.SidebarCollapsed = flag); break;
            case "sidebarWidth": b.Change(p => p.SidebarWidth = number); break;
            case "theme": if (Enum<Theme>(text) is { } theme) b.Change(p => p.Theme = theme); break;
            case "customBase": if (Enum<Theme>(text) is { } basis && basis != Theme.Custom) b.Change(p => p.CustomBase = basis); break;
            case "accent": if (text is not null && HexColor.Parse(text) is not null) b.Change(p => p.Accent = text.ToUpperInvariant()); break;
            case "customTint": b.Change(p => p.CustomTint = number); break;
            case "frosted": b.Change(p => p.Frosted = flag); break;
            case "transparency": b.Change(p => p.Transparency = number); break;
            case "userName": b.Change(p => p.UserName = text ?? ""); break;
            case "greetByName": b.Change(p => p.GreetByName = flag); break;
            case "language": b.Change(p => p.Language = text == "en" ? Language.En : Language.Ru); break;
            case "lowercase": b.Change(p => p.Lowercase = flag); break;
            case "address.full": b.Change(p => p.Address.Full = flag); break;
            case "address.dimSubdomain": b.Change(p => p.Address.DimSubdomain = flag); break;
            case "address.dimPath": b.Change(p => p.Address.DimPath = flag); break;
        }
    }

    static void SetSetting(BrowserModel b, string key, JsonElement value)
    {
        var store = b.Store;
        bool flag = value.ValueKind == JsonValueKind.True;
        switch (key)
        {
            case "blocking": store.Change(b.ProfileId, p => p.Blocking = flag); break;
            case "restore": store.Change(b.ProfileId, p => p.Restore = flag); break;
            case "lazyRestore": store.Change(b.ProfileId, p => p.LazyRestore = flag); break;
            case "notificationRequests": store.Change(b.ProfileId, p => p.NotificationRequests = flag); break;
            case "offerPasswords": store.Change(b.ProfileId, p => p.OfferPasswords = flag); break;
            case "fillPasswords": store.Change(b.ProfileId, p => p.FillPasswords = flag); break;
            case "updateChecks": store.Updater.EnableChecks(flag); break;
            case "profileOpening": if (Enum<ProfileOpening>(value.ValueKind == JsonValueKind.String ? value.GetString() : null) is { } opening) store.Change(b.ProfileId, p => p.ProfileOpening = opening); break;
        }
    }

    static void SetClearing(BrowserModel b, string key, JsonElement value)
    {
        bool flag = value.ValueKind == JsonValueKind.True;
        b.Store.Change(b.ProfileId, p =>
        {
            switch (key)
            {
                case "period": if (Enum<ClearPeriod>(value.ValueKind == JsonValueKind.String ? value.GetString() : null) is { } period) p.Clearing.Period = period; break;
                case "history": p.Clearing.History = flag; break;
                case "siteData": p.Clearing.SiteData = flag; break;
                case "cache": p.Clearing.Cache = flag; break;
                case "permissions": p.Clearing.Permissions = flag; break;
            }
        });
    }

    /// <summary>Adds or edits a custom start page site. Plain words are refused instead of becoming a search shortcut;
    /// the page's own address is kept as it is, so the address bar finds the page pinned afterwards.</summary>
    static JsonNode SaveShortcut(BrowserModel b, JsonElement a)
    {
        var address = (Str(a, "address") ?? "").Trim();
        var page = Str(a, "page");
        var url = page is not null && address == page ? page : Mica.Core.StartPage.ShortcutUrl(address, b.Store.Preferences.Search);
        if (url is null) return false;
        var title = (Str(a, "title") ?? "").Trim();
        var id = Id(a);
        b.Change(p =>
        {
            if (id is { } existing && p.Start.Shortcuts.FirstOrDefault(s => s.Id == existing) is { } shortcut) { shortcut.Url = url; shortcut.Title = title; }
            else { p.Start.Shortcuts.Add(new StartShortcut { Url = url, Title = title }); p.Start.SetVisible(StartSection.Custom, true); }
        });
        return true;
    }

    static JsonArray Suggest(BrowserModel b, string input)
    {
        var store = b.Store;
        var query = input.Trim();
        var result = new JsonArray();
        if (query.Length == 0) return result;
        var seen = new HashSet<string>();
        void Add(string id, string kind, string title, string detail, string? url, Guid? tab = null)
        {
            if (result.Count >= 8) return;
            if (url is not null) seen.Add(url);
            result.Push(new JsonObject { ["id"] = id, ["kind"] = kind, ["title"] = title, ["detail"] = detail, ["url"] = url, ["tabId"] = tab?.ToString() });
        }
        var engine = store.Preferences.Search;
        var target = AddressParser.Resolve(query, engine);
        if (target.Kind == AddressKind.Web)
        {
            var searchDetail = b.Text("поиск: ", "Поиск: ") + engine.Title(b.TextStyle.Language);
            if (engine.IsSearch(target.Value, query)) Add("search", "search", query, searchDetail, target.Value);
            else
            {
                Add("open", "open", target.Value, b.Text("открыть адрес", "Открыть адрес"), target.Value);
                Add("search", "search", query, searchDetail, engine.Search(query));
            }
        }
        bool Matches(string title, string url) => title.Contains(query, StringComparison.CurrentCultureIgnoreCase) || url.Contains(query, StringComparison.CurrentCultureIgnoreCase);
        foreach (var tab in b.Tabs.Where(t => t.Id != b.SelectedId))
            if (tab.Url is { } url && Matches(tab.Title, url) && !seen.Contains(url)) Add("tab-" + tab.Id, "tab", tab.Title.Length == 0 ? url : tab.Title, b.Text("перейти к вкладке", "Перейти к вкладке"), url, tab.Id);
        foreach (var visit in store.Bookmarks)
            if (Matches(visit.Title, visit.Url) && !seen.Contains(visit.Url)) Add("b-" + visit.Id, "bookmark", visit.Title.Length == 0 ? visit.Url : visit.Title, visit.Host ?? visit.Url, visit.Url);
        if (!b.PrivateMode)
            foreach (var visit in store.History)
            {
                if (result.Count >= 8) break;
                if (Matches(visit.Title, visit.Url) && !seen.Contains(visit.Url)) Add("h-" + visit.Id, "history", visit.Title.Length == 0 ? visit.Url : visit.Title, visit.Host ?? visit.Url, visit.Url);
            }
        return result;
    }

    // Find on page with WebView2's find API (macOS FindBar with WKWebView.find).
    sealed record FindState(string Query, int Total, int Index);
    static readonly Dictionary<Guid, FindState> finds = [];

    public static JsonObject? FindResult(BrowserModel b) =>
        b.ShowFind && finds.TryGetValue(b.Id, out var f) && f.Query.Length > 0 ? new JsonObject { ["found"] = f.Total > 0, ["total"] = f.Total, ["index"] = f.Index + 1 } : null;

    static async Task Find(BrowserModel b, string query, bool back)
    {
        if (b.Selected?.Core is not { } core || b.Store.Engine.Environment is not { } env) return;
        if (query.Length == 0) { core.Find.Stop(); finds.Remove(b.Id); b.Touch(); return; }
        if (finds.TryGetValue(b.Id, out var current) && current.Query == query)
        {
            if (back) core.Find.FindPrevious(); else core.Find.FindNext();
        }
        else
        {
            var options = env.CreateFindOptions();
            options.FindTerm = query; options.IsCaseSensitive = false; options.SuppressDefaultFindDialog = true; options.ShouldHighlightAllMatches = true;
            await core.Find.StartAsync(options);
        }
        finds[b.Id] = new FindState(query, (int)core.Find.MatchCount, (int)core.Find.ActiveMatchIndex);
        b.Touch();
    }
}
