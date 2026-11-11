using System.Globalization;
using Mica.Core;
using Mica.Design;
using Microsoft.UI.Dispatching;
using Microsoft.Web.WebView2.Core;

namespace Mica.App;

/// <summary>Profile, persistence and windows (macOS Store). JSON lives in %LOCALAPPDATA%\mica, the QA profile in its
/// own folder; site data lives in WebView2's user data folder beside it. Writes are atomic and debounced.</summary>
public sealed partial class Store
{
    public static readonly Store Shared = new();
    public string Root { get; }
    /// <summary>Application-wide preferences. The part a profile owns (ProfileLook) is read through Prefs(profile); its
    /// copy here only seeds the standard profile when preferences from a build before profiles are first loaded.</summary>
    public Preferences Preferences { get; private set; }
    /// <summary>The standard profile first. Each window shows one of them.</summary>
    public List<Profile> Profiles { get; private set; }
    public event Action? ProfilesChanged;
    public List<Visit> Bookmarks { get; private set; }
    public List<Visit> History { get; private set; }
    public List<SitePermission> Permissions { get; private set; }
    public List<DownloadRecord> DownloadRecords { get; private set; }
    public string? Issue { get; set; }
    public readonly List<BrowserWindow> Windows = [];
    public bool ShuttingDown { get; set; }

    public event Action<Preferences>? PreferencesChanged;
    /// <summary>Same moment as PreferencesChanged, for views that only re-render.</summary>
    public event Action? PreferencesUpdated;
    public event Action? BookmarksChanged, HistoryChanged, PermissionsChanged, DownloadsChanged, IssueChanged;

    public Engine Engine { get; }
    public Blocker Blocker { get; }
    public Extensions.ExtensionManager Extensions { get; }
    public Import.ImportManager Importer { get; }
    public Update.Updater Updater { get; }
    public Passwords.PasswordManager Passwords { get; }
    /// <summary>Site icons of normal windows; incognito windows keep their own (BrowserModel.Favicons).</summary>
    public Favicons Favicons { get; }

    readonly HashSet<string> unreadable = [];
    readonly DispatcherQueue queue = DispatcherQueue.GetForCurrentThread();
    DispatcherQueueTimer? sessionTimer, preferencesTimer, profilesTimer;

    Store()
    {
        var app = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "mica");
        Root = Program.QA ? Path.Combine(app, "QA") : app;
        Directory.CreateDirectory(Root);
        Favicons = new Favicons(Path.Combine(Root, "Favicons"));
        var issues = new List<string>();
        T? Read<T>(string name) where T : class
        {
            var path = Path.Combine(Root, name);
            if (!File.Exists(path)) return null;
            try { return Persistence.Read<T>(path); }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException or System.Text.Json.JsonException or InvalidDataException or NotSupportedException)
            {
                var recovery = Path.Combine(Root, "Recovery");
                Directory.CreateDirectory(recovery);
                try { File.Copy(path, Path.Combine(recovery, Guid.NewGuid() + "-" + name)); } catch (IOException) { }
                issues.Add(name + ": " + e.Message);
                unreadable.Add(name);
                return null;
            }
        }
        DownloadRecords = Read<List<DownloadRecord>>("downloads.json") ?? [];
        Preferences = (Read<Preferences>("preferences.json") ?? new Preferences()).Sanitized();
        Profiles = Core.Profiles.Normalized(Read<List<Profile>>("profiles.json") ?? [], ProfileLook.From(Preferences));
        // The first launch with profiles writes the standard profile made from the old preferences.
        if (!File.Exists(Path.Combine(Root, "profiles.json"))) Save(Profiles, "profiles.json");
        Bookmarks = Read<List<Visit>>("bookmarks.json") ?? [];
        History = Read<List<Visit>>("history.json") ?? [];
        Permissions = Read<List<SitePermission>>("permissions.json") ?? [];
        if (issues.Count > 0) Issue = "mica: " + string.Join("\n", issues);
        if (Program.QA) { Preferences.OnboardingComplete = true; Preferences.Restore = false; }
        Engine = new Engine(this);
        Blocker = new Blocker(this);
        Extensions = new Extensions.ExtensionManager(this);
        Importer = new Import.ImportManager(this);
        Updater = new Update.Updater(this);
        Passwords = new Passwords.PasswordManager(this);
        ApplyAppearance();
        global::Windows.UI.ViewManagement.UISettings settings = new();
        settings.ColorValuesChanged += (_, _) => queue.TryEnqueue(ApplyAppearance);
    }

    /// <summary>Text that belongs to no window (jump list, dialogs without an owner, extension and update messages) takes the
    /// language and case of the profile of the window in front. A window's own text follows its profile (BrowserModel.Text).</summary>
    public string Text(string low, string regular) => TextStyle(Active?.ProfileId).Text(low, regular);
    public CultureInfo Culture => TextStyle(Active?.ProfileId).Language.Culture();
    /// <summary>Language and case of a profile's windows, without building its whole preferences.</summary>
    public TextStyle TextStyle(Guid? profile)
    {
        var look = Profile(profile).Look;
        return new TextStyle(look.Language ?? Preferences.Language, look.Lowercase ?? Preferences.Lowercase);
    }

    public string CapabilityName(SiteCapability capability) => capability switch
    {
        SiteCapability.Camera => Text("камера", "Камера"),
        SiteCapability.Microphone => Text("микрофон", "Микрофон"),
        SiteCapability.Notifications => Text("уведомления", "Уведомления"),
        _ => Text("геолокация", "Геолокация"),
    };

    public BrowserModel? Active => Windows.FirstOrDefault(w => w.IsKey)?.Model ?? Windows.LastOrDefault()?.Model;

    public Profile Profile(Guid? id) => Core.Profiles.Resolve(id, Profiles);
    public string ProfileName(Profile profile) => TextStyle(Active?.ProfileId).ProfileName(profile);
    public string Quoted(string text) => TextStyle(Active?.ProfileId).Quoted(text);
    /// <summary>Preferences in effect for a window of this profile: the application-wide ones with the profile's look over them.</summary>
    public Preferences Prefs(Guid? profile) => Profile(profile).Look.AppliedTo(Preferences);
    /// <summary>Preferences of the window in front. Settings and onboarding live in that window and edit its profile.</summary>
    public Preferences ActivePrefs => Prefs(Active?.ProfileId);

    /// <summary>Edits preferences of the window in front; its profile takes the look part, the application the rest.
    /// Dependants (appearance, blocking, icon) react to what actually changed.</summary>
    public void Change(Action<Preferences> edit) => Change(Active?.ProfileId, edit);

    public void Change(Guid? profile, Action<Preferences> edit)
    {
        var old = Preferences.Clone();
        var target = Profile(profile);
        var effective = target.Look.AppliedTo(Preferences);
        edit(effective);
        effective.Sanitized();
        var look = ProfileLook.From(effective);
        // The application-wide copy keeps its own look fields; only the rest of the edit reaches it.
        var legacy = ProfileLook.From(Preferences);
        Preferences = legacy.AppliedTo(effective);
        SchedulePreferences();
        if (!look.SameAs(target.Look)) { target.Look = look; ScheduleProfiles(); }
        ApplyAppearance();
        if (old.AppIcon != Preferences.AppIcon) { Appearance.AppIcons.Apply(this); FlushPreferences(); }
        if (old.Blocking != Preferences.Blocking || !old.BlockingExceptions.SequenceEqual(Preferences.BlockingExceptions)) _ = Blocker.RebuildAsync();
        PreferencesChanged?.Invoke(old);
        PreferencesUpdated?.Invoke();
    }

    /// <summary>Name, icon, background or pinned tabs of one profile. An empty name is kept only by the standard profile.</summary>
    public void ChangeProfile(Guid id, Action<Profile> edit)
    {
        var index = Profiles.FindIndex(p => p.Id == id);
        if (index < 0) return;
        var copy = Profiles[index].Copy();
        edit(copy);
        copy.Name = Core.Profiles.Name(copy.Name);
        if (copy.Name.Length == 0 && !copy.IsStandard) return;
        Profiles[index] = copy.Sanitized();
        ScheduleProfiles();
        foreach (var window in Windows) window.UpdateTitle();
        ProfilesChanged?.Invoke();
        PreferencesUpdated?.Invoke();
    }

    /// <summary>A new profile starts from the look of the profile it was created from.</summary>
    public Profile AddProfile(Guid? source)
    {
        var profile = Core.Profiles.Next(Profiles, Text("профиль ", "Профиль ") + (Profiles.Count + 1), Profile(source).Look);
        Profiles.Add(profile);
        ScheduleProfiles();
        foreach (var window in Windows) window.UpdateTitle();
        ProfilesChanged?.Invoke();
        return profile;
    }

    /// <summary>Windows of a removed profile move to the standard one; history keeps the mark of the removed profile.</summary>
    public void RemoveProfile(Guid id)
    {
        if (id == Core.Profile.StandardId) return;
        foreach (var window in Windows.Where(w => w.Model.ProfileId == id).ToList()) window.Model.SwitchProfile(Core.Profile.StandardId);
        Profiles = Core.Profiles.Removing(id, Profiles);
        ScheduleProfiles();
        foreach (var window in Windows) window.UpdateTitle();
        ProfilesChanged?.Invoke();
        PreferencesUpdated?.Invoke();
    }

    /// <summary>A window of this profile comes forward, or a new one opens.</summary>
    public void OpenProfile(Guid id, bool newWindow = false)
    {
        if (!newWindow && Windows.LastOrDefault(w => w.Model.ProfileId == id && !w.Model.PrivateMode) is { } window) { window.Bring(); return; }
        NewWindow(profile: id);
    }

    /// <summary>A window changed profile: views of profile-owned settings redraw.</summary>
    public void NotifyProfileSwitch() { ProfilesChanged?.Invoke(); PreferencesUpdated?.Invoke(); }

    void ScheduleProfiles()
    {
        profilesTimer ??= Debounce(TimeSpan.FromMilliseconds(150), () => Save(Profiles, "profiles.json"));
        profilesTimer.Stop(); profilesTimer.Start();
        JumpList.Update(this);
    }

    public void Save<T>(T value, string name)
    {
        if (unreadable.Contains(name)) return;
        try { Persistence.Write(value, Path.Combine(Root, name)); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { Issue = Text("не удалось сохранить данные: ", "Не удалось сохранить данные: ") + e.Message; IssueChanged?.Invoke(); }
    }

    void SchedulePreferences()
    {
        preferencesTimer ??= Debounce(TimeSpan.FromMilliseconds(150), () => Save(Preferences, "preferences.json"));
        preferencesTimer.Stop(); preferencesTimer.Start();
    }
    public void FlushPreferences() { preferencesTimer?.Stop(); Save(Preferences, "preferences.json"); profilesTimer?.Stop(); Save(Profiles, "profiles.json"); }

    DispatcherQueueTimer Debounce(TimeSpan delay, Action action)
    {
        var timer = queue.CreateTimer();
        timer.Interval = delay; timer.IsRepeating = false;
        timer.Tick += (_, _) => action();
        return timer;
    }

    /// <summary>Light or dark in effect: the custom theme brings its own base; "system" follows Windows.</summary>
    public bool DarkMode
    {
        get
        {
            var p = ActivePrefs;
            var mode = p.Theme == Theme.Custom ? p.CustomBase : p.Theme;
            if (mode == Theme.System)
            {
                var background = new global::Windows.UI.ViewManagement.UISettings().GetColorValue(global::Windows.UI.ViewManagement.UIColorType.Background);
                return background.R < 128;
            }
            return mode == Theme.Dark;
        }
    }

    public void ApplyAppearance()
    {
        var contrast = new global::Windows.UI.ViewManagement.AccessibilitySettings().HighContrast;
        Palette.Apply(DarkMode, contrast);
        // The palette is shared by every window, so theme and colours follow the profile of the window in front.
        var p = ActivePrefs;
        Look.Apply(p.Theme == Theme.Custom, p.Accent, p.CustomTint);
        foreach (var window in Windows) window.ApplyAppearance();
    }

    /// <summary>Opacity of the shell tint over the backdrop: 0.92 at zero transparency, 0.2 at full.</summary>
    public static double GlassTint(Preferences p) => 0.92 - p.Transparency * 0.72;
    /// <summary>Opacity of the start page fill over the glass: opaque at zero transparency, 0.45 at full, denser than the
    /// shell tint so the start page still reads as the card. Web pages are never made transparent.</summary>
    public static double StartTint(Preferences p) => 1 - p.Transparency * 0.55;

    public async Task StartAsync()
    {
        await Engine.StartAsync();
        await Blocker.RebuildAsync();
        if (!Program.Arguments.Any(a => a.StartsWith("--benchmark=", StringComparison.Ordinal))) await Extensions.RestoreAsync();
        Session? saved = null;
        var sessionPath = Path.Combine(Root, "session.json");
        if (Preferences.Restore && File.Exists(sessionPath))
        {
            try
            {
                var raw = Persistence.Read<Session>(sessionPath);
                if (raw.Version != 1) throw new InvalidDataException("session version");
                saved = raw.Validated();
            }
            catch (Exception e) when (e is IOException or System.Text.Json.JsonException or InvalidDataException)
            {
                unreadable.Add("session.json");
                var recovery = Path.Combine(Root, "Recovery");
                Directory.CreateDirectory(recovery);
                try { File.Copy(sessionPath, Path.Combine(recovery, Guid.NewGuid() + "-session.json")); } catch (IOException) { }
                Issue = Text("сессия повреждена. исходный файл скопирован в Recovery: ", "Сессия повреждена. Исходный файл скопирован в Recovery: ") + e.Message;
            }
        }
        if (Preferences.Restore && saved is { Windows.Count: > 0 }) foreach (var window in saved.Windows) NewWindow(saved: window);
        else NewWindow();
        Appearance.AppIcons.Apply(this);
        try { if (!Program.QA) Mica.Install.DefaultBrowser.Register(); } catch (Exception e) when (e is UnauthorizedAccessException or IOException or System.Security.SecurityException) { Diagnostics.Log.Error(e); }
        Updater.Start();
    }

    /// <summary>Without a profile the window takes the one of the window in front, so Ctrl+N stays in the current profile.</summary>
    public BrowserModel NewWindow(bool privateMode = false, SavedWindow? saved = null, Guid? profile = null)
    {
        var profileId = Profile(saved?.Profile ?? profile ?? Active?.ProfileId).Id;
        var model = new BrowserModel(this, privateMode, profileId);
        var window = new BrowserWindow(model);
        Windows.Add(window);
        if (saved is { Tabs.Count: > 0 })
        {
            foreach (var t in saved.Tabs) model.Add(t, activate: false, restored: true);
            if (model.Tabs.FirstOrDefault(t => t.Id == saved.Selected) is { } selected) model.Select(selected);
            foreach (var t in model.Tabs.Where(t => TabPolicy.ShouldLoadOnRestore(t.Saved, saved.Selected, Preferences)).ToList()) t.EnsureLoaded();
        }
        else
        {
            // A new window of a profile opens with that profile's pinned tabs, loaded when first selected.
            if (!privateMode) foreach (var pin in Profile(profileId).Pinned) model.Add(new SavedTab { Url = pin.Url, Title = pin.Title, Pinned = true }, activate: false, restored: true);
            model.Add();
        }
        window.Activate();
        window.Enter();
        ScheduleSession();
        return model;
    }

    public void ScheduleSession()
    {
        if (ShuttingDown) return;
        sessionTimer ??= Debounce(TimeSpan.FromMilliseconds(400), FlushSession);
        sessionTimer.Stop(); sessionTimer.Start();
    }

    public void FlushSession()
    {
        sessionTimer?.Stop();
        var normal = Windows.Where(w => !w.Model.PrivateMode).ToList();
        Save(new Session { Windows = normal.Select(w => w.Model.Snapshot).ToList() }, "session.json");
        // Each profile remembers the pinned tabs of its windows; with several windows the one in front wins.
        foreach (var window in normal.Where(w => !w.IsKey).Concat(normal.Where(w => w.IsKey))) window.Model.RememberPinned();
    }

    public void Record(Tab tab)
    {
        if (tab.Owner?.PrivateMode != false || tab.Url is not { } url || !(url.StartsWith("https://", StringComparison.Ordinal) || url.StartsWith("http://", StringComparison.Ordinal))) return;
        if (History.FirstOrDefault() is { } last && last.Url == url && DateTimeOffset.Now - last.Date < TimeSpan.FromSeconds(60)) return;
        History.Insert(0, new Visit(url, tab.Title, tab.Owner?.ProfileId));
        if (History.Count > 3000) History.RemoveRange(3000, History.Count - 3000);
        SetHistory(History);
    }

    public void SetHistory(List<Visit> visits) { History = visits; Save(History, "history.json"); HistoryChanged?.Invoke(); }
    public void SetBookmarks(List<Visit> visits) { Bookmarks = visits; Save(Bookmarks, "bookmarks.json"); BookmarksChanged?.Invoke(); }
    public void SetDownloadRecords(List<DownloadRecord> records) { DownloadRecords = records; Save(DownloadRecords, "downloads.json"); DownloadsChanged?.Invoke(); }

    public bool IsBookmarked(string? url) => url is not null && Bookmarks.Any(b => b.Url == url);

    public void Bookmark(Tab tab)
    {
        if (tab.Url is not { } url) return;
        var list = Bookmarks.ToList();
        var index = list.FindIndex(b => b.Url == url);
        if (index >= 0) list.RemoveAt(index); else list.Insert(0, new Visit(url, tab.Title));
        SetBookmarks(list);
    }

    public Decision DecisionFor(string origin, SiteCapability capability, BrowserModel? window = null)
    {
        var records = window?.PrivateMode == true ? window.TransientPermissions : Permissions;
        return records.FirstOrDefault(p => p.Origin == origin && p.Capability == capability)?.Decision ?? Decision.Ask;
    }

    public void SetPermission(string origin, SiteCapability capability, Decision decision, BrowserModel? window = null)
    {
        if (window?.PrivateMode == true)
        {
            window.TransientPermissions.RemoveAll(p => p.Origin == origin && p.Capability == capability);
            if (decision != Decision.Ask) window.TransientPermissions.Add(new SitePermission { Origin = origin, Capability = capability, Decision = decision });
            return;
        }
        Permissions.RemoveAll(p => p.Origin == origin && p.Capability == capability);
        if (decision != Decision.Ask) Permissions.Add(new SitePermission { Origin = origin, Capability = capability, Decision = decision });
        Save(Permissions, "permissions.json");
        PermissionsChanged?.Invoke();
    }

    /// <summary>Removes what the clear-data panel selected, from the start of its period up to now. Bookmarks, open tabs
    /// and incognito windows are not touched.</summary>
    public async Task ClearAsync(ClearChoice choice)
    {
        var now = DateTimeOffset.Now;
        var start = choice.Period.Start(now);
        if (choice.History) SetHistory(HistoryOps.Removing(History, start));
        // Icons are not dated, so any history or cache clearing forgets all of them.
        if (choice.History || choice.Cache) Favicons.Clear();
        if (choice.Permissions) { Permissions = []; Save(Permissions, "permissions.json"); PermissionsChanged?.Invoke(); }
        var kinds = (CoreWebView2BrowsingDataKinds)0;
        if (choice.SiteData) kinds |= CoreWebView2BrowsingDataKinds.AllDomStorage | CoreWebView2BrowsingDataKinds.Cookies | CoreWebView2BrowsingDataKinds.ServiceWorkers;
        if (choice.Cache) kinds |= CoreWebView2BrowsingDataKinds.DiskCache | CoreWebView2BrowsingDataKinds.CacheStorage;
        if (kinds != 0) await Engine.ClearAsync(kinds, start == DateTimeOffset.MinValue ? DateTime.UnixEpoch : start.UtcDateTime, now.UtcDateTime);
    }

    public void Quit()
    {
        FlushPreferences();
        FlushSession();
        ShuttingDown = true;
        foreach (var window in Windows.ToList()) window.Model.Downloads.CancelAll();
        foreach (var window in Windows.ToList()) window.CloseForQuit();
        Microsoft.UI.Xaml.Application.Current.Exit();
    }
}

/// <summary>Language and letter case of interface text, taken from a profile (macOS TextStyle).</summary>
public readonly record struct TextStyle(Language Language, bool Lowercase)
{
    public string Text(string low, string regular) => Copy.Text(low, regular, Lowercase, Language);
    /// <summary>A name inside authored text: «…» in Russian, “…” in English.</summary>
    public string Quoted(string text) => Language == Language.En ? "“" + text + "”" : "«" + text + "»";
    public string ProfileName(Profile profile) => Core.Profiles.DisplayName(profile, Lowercase, Language);
    public CultureInfo Culture => Language.Culture();
}
