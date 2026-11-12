using Mica.Core;

namespace Mica.App;

public enum LibraryPanel { Bookmarks, History, Downloads, Extensions }

/// <summary>One browser window: tabs, selection and which overlays are open (macOS BrowserModel).</summary>
public sealed partial class BrowserModel : Observable
{
    public Store Store { get; }
    public bool PrivateMode { get; }
    public Guid Id { get; } = Guid.NewGuid();
    public List<Tab> Tabs { get; } = [];
    public Guid? SelectedId { get; private set; }
    public BrowserWindow? Window { get; set; }
    public List<SavedTab> Closed { get; } = [];
    public List<SitePermission> TransientPermissions { get; } = [];
    public Downloads.DownloadManager Downloads { get; }
    /// <summary>Incognito windows keep their own in-memory icons, so nothing they visit reaches normal windows or the disk.</summary>
    public Favicons Favicons { get; }

    LibraryPanel? panel; bool showFind, showSettings, showClearData, showOnboarding, commandBar, customizingToolbar, customizingStart, fullScreen;
    public LibraryPanel? Panel { get => panel; set { panel = value; Notify(); } }
    public bool ShowFind { get => showFind; set { showFind = value; Notify(); } }
    public bool ShowSettings { get => showSettings; set { showSettings = value; if (value) { CommandBar = false; CustomizingToolbar = false; } Notify(); } }
    public bool ShowClearData { get => showClearData; set { showClearData = value; if (value) { CommandBar = false; CustomizingToolbar = false; } Notify(); } }
    public bool ShowOnboarding { get => showOnboarding; set { showOnboarding = value; Notify(); } }
    public bool CommandBar { get => commandBar; set { commandBar = value; Notify(); } }
    public bool CustomizingToolbar { get => customizingToolbar; set { customizingToolbar = value; Notify(); } }
    public bool CustomizingStart { get => customizingStart; set { customizingStart = value; Notify(); } }
    public bool FullScreen { get => fullScreen; set { fullScreen = value; Notify(); } }
    /// <summary>Set once the window is first shown; the content card and the start page play their entrance from it.</summary>
    public bool Entered { get => entered; set { entered = value; Notify(); } }
    bool entered;
    /// <summary>Section open in settings: space, appearance, start, profiles, search, session, transfer, permissions, passwords, about.</summary>
    public string SettingsSection { get; set; } = "space";
    /// <summary>The quit shortcut is being held in this window; the shell shows the plate.</summary>
    public bool QuitHolding { get => quitHolding; set { quitHolding = value; Notify(); } }
    bool quitHolding;
    /// <summary>Questions of this window waiting for an answer in the shell, the first one shown (Dialogs).</summary>
    public List<Dialogs.Question> Questions { get; } = [];
    /// <summary>The password offer beside a sign-in field of the selected page (PasswordBridge); the shell draws it
    /// over the page while the page keeps the keyboard.</summary>
    public Passwords.OfferView? PasswordOffer { get => passwordOffer; set { passwordOffer = value; Notify(); } }
    Passwords.OfferView? passwordOffer;
    public void Touch() => Notify();
    /// <summary>Profile open in the profile editor of settings.</summary>
    public Guid? EditingProfile { get; set; }
    public int OnboardingStep { get; set; }
    /// <summary>A window-level card covers the page; the web view takes no input meanwhile.</summary>
    public bool Modal => showSettings || showOnboarding || showClearData || profilePrompt is not null;
    Guid? profilePrompt;
    /// <summary>Profile chosen in the profile menu while mica still has to ask where to open it.</summary>
    public Guid? ProfilePrompt { get => profilePrompt; set { profilePrompt = value; if (value is not null) { CommandBar = false; CustomizingToolbar = false; } Notify(); } }
    public event Action? FocusAddressRequested;
    /// <summary>F10 or Alt+F: the "…" menu that stands in for the macOS menu bar.</summary>
    public event Action? MenuRequested;
    /// <summary>F3, Ctrl+G and their Shift forms: the open find bar steps to the next or previous match; a closed bar opens instead.</summary>
    public event Action<bool>? FindStepRequested;
    public void StepFind(bool back)
    {
        if (Selected?.Core is null) return;
        if (ShowFind) FindStepRequested?.Invoke(back); else ShowFind = true;
    }
    public void RequestMenu() => MenuRequested?.Invoke();
    /// <summary>Ctrl+S: the save button opens its format menu.</summary>
    public event Action? SaveMenuRequested;
    public void RequestSaveMenu() => SaveMenuRequested?.Invoke();
    public event Action<Tab>? WebViewCreated;
    public event Action<string>? Message;

    /// <summary>Profile of this window: start page, arrangement, greeting and pinned tabs, and while it is in front the
    /// theme and colours of mica (the palette is shared by all windows). Data is shared by all profiles.</summary>
    public Guid ProfileId { get; private set; }
    public Profile Profile => Store.Profile(ProfileId);
    /// <summary>Preferences in effect in this window.</summary>
    public Preferences Prefs => Store.Prefs(ProfileId);
    /// <summary>Edits this window's preferences: the look part goes to its profile.</summary>
    public void Change(Action<Preferences> edit) => Store.Change(ProfileId, edit);
    /// <summary>Takes the page off the start page's own sites of this window's profile.</summary>
    public void RemoveStartShortcut(string url) => Change(p => p.Start.Shortcuts.RemoveAll(s => s.Url == url));

    public BrowserModel(Store store, bool privateMode, Guid profile)
    {
        Store = store; PrivateMode = privateMode; ProfileId = profile;
        Downloads = new Downloads.DownloadManager(this);
        Favicons = privateMode ? new Favicons(null) : store.Favicons;
        showOnboarding = !store.Preferences.OnboardingComplete && !privateMode;
    }

    /// <summary>Text of this window in its profile's language and case.</summary>
    public TextStyle TextStyle => Store.TextStyle(ProfileId);
    public string Text(string low, string regular) => TextStyle.Text(low, regular);
    public string Quoted(string text) => TextStyle.Quoted(text);
    public string ProfileName(Profile profile) => TextStyle.ProfileName(profile);
    public System.Globalization.CultureInfo Culture => TextStyle.Culture;
    public Tab? Selected => Tabs.FirstOrDefault(t => t.Id == SelectedId);
    public SavedWindow Snapshot => new() { Tabs = Tabs.Select(t => t.Saved).ToList(), Selected = SelectedId, Profile = ProfileId };

    /// <summary>The window takes another profile's look. Its pinned tabs are kept for the old profile and the new
    /// profile's pinned tabs take their place, loaded when selected.</summary>
    public void SwitchProfile(Guid id)
    {
        var target = Store.Profile(id).Id;
        if (target == ProfileId) return;
        if (!PrivateMode)
        {
            RememberPinned();
            var selectedPinned = Selected?.Pinned == true;
            foreach (var tab in Tabs.Where(t => t.Pinned).ToList()) Close(tab, remember: false);
            foreach (var pin in Store.Profile(target).Pinned) Add(new SavedTab { Url = pin.Url, Title = pin.Title, Pinned = true }, activate: false, restored: true);
            if (!Tabs.Any(t => !t.Pinned)) Add();
            else if (selectedPinned || Selected is null) Select(Tabs.First(t => !t.Pinned));
        }
        ProfileId = target;
        Window?.UpdateTitle();
        Store.ApplyAppearance();
        Store.ScheduleSession();
        Notify();
        Store.NotifyProfileSwitch();
    }

    /// <summary>Stores this window's pinned tabs as the profile's own.</summary>
    public void RememberPinned()
    {
        if (PrivateMode) return;
        var pinned = Tabs.Where(t => t.Pinned).Select(t => t.Saved).Where(t => t.Url is { } u && (u.StartsWith("https://", StringComparison.OrdinalIgnoreCase) || u.StartsWith("http://", StringComparison.OrdinalIgnoreCase))).ToList();
        var current = Profile.Pinned;
        if (current.Select(t => t.Url + "\n" + t.Title).SequenceEqual(pinned.Select(t => t.Url + "\n" + t.Title))) return;
        Store.ChangeProfile(ProfileId, p => p.Pinned = pinned.Select(t => t.Copy()).ToList());
    }

    /// <summary>The window list and Alt+Tab tell windows of different profiles apart by name.</summary>
    public string WindowTitle
    {
        get
        {
            var parts = new List<string> { "mica" };
            if (Store.Profiles.Count > 1 || !Profile.IsStandard) parts.Add(Store.ProfileName(Profile));
            if (PrivateMode) parts.Add(Text("инкогнито", "Инкогнито"));
            return string.Join(" — ", parts);
        }
    }

    public void FocusAddress() { if (Selected?.Url is not null) CommandBar = true; FocusAddressRequested?.Invoke(); }
    public void Show(string message) => Message?.Invoke(message);
    internal void DidCreateWebView(Tab tab) => WebViewCreated?.Invoke(tab);

    public Tab Add(SavedTab? saved = null, bool activate = true, bool restored = false)
    {
        var tab = new Tab(saved ?? new SavedTab(), this, restored);
        if (tab.Pinned) Tabs.Insert(Tabs.TakeWhile(t => t.Pinned).Count(), tab); else Tabs.Add(tab);
        if (activate) Select(tab);
        if (!restored && tab.Url is not null) tab.EnsureLoaded();
        Store.ScheduleSession();
        Notify();
        return tab;
    }

    public void Open(string url, bool background = false) => Add(new SavedTab { Url = url }, activate: !background);

    public void Select(Tab tab)
    {
        SelectedId = tab.Id;
        tab.EnsureLoaded();
        Window?.UpdateTitle();
        Store.ScheduleSession();
        Notify();
    }

    public void Cycle(int offset)
    {
        if (Tabs.Count == 0) return;
        var index = Math.Max(0, Tabs.FindIndex(t => t.Id == SelectedId));
        Select(Tabs[(index + offset + Tabs.Count) % Tabs.Count]);
    }

    /// <summary>No hidden reloads: closing explicitly ends the tab, forms and media included.</summary>
    public void Close(Tab tab) => Close(tab, remember: true);

    void Close(Tab tab, bool remember)
    {
        var index = Tabs.FindIndex(t => t.Id == tab.Id);
        if (index < 0) return;
        if (remember) { Closed.Insert(0, tab.Saved); if (Closed.Count > 30) Closed.RemoveRange(30, Closed.Count - 30); }
        tab.Dispose();
        Tabs.RemoveAt(index);
        if (SelectedId == tab.Id)
        {
            if (Tabs.Count > 0) Select(Tabs[Math.Min(index, Tabs.Count - 1)]);
            else if (remember) Add();
            else SelectedId = null;
        }
        Store.ScheduleSession();
        Notify();
    }

    /// <summary>Closes every unpinned tab and leaves a fresh start page selected; the window stays open. The new tab
    /// comes first, so closing the selected tab never falls back to another one or adds a second page.</summary>
    public void CloseAll()
    {
        var doomed = Tabs.Where(t => !t.Pinned).ToList();
        Add();
        foreach (var tab in doomed) Close(tab);
    }

    public void Reopen()
    {
        if (Closed.Count == 0) return;
        var tab = Closed[0]; Closed.RemoveAt(0);
        tab.Id = Guid.NewGuid();
        Add(tab);
    }

    public void Pin(Tab tab)
    {
        tab.Pinned = !tab.Pinned;
        Tabs.Remove(tab);
        Tabs.Insert(Tabs.TakeWhile(t => t.Pinned).Count(), tab);
        Store.ScheduleSession();
        Notify();
    }

    public void Move(Guid id, Guid before)
    {
        var order = TabPolicy.Moving(Tabs.Select(t => t.Saved).ToList(), id, before);
        var lookup = Tabs.ToDictionary(t => t.Id);
        var reordered = order.Select(s => lookup[s.Id]).ToList();
        Tabs.Clear(); Tabs.AddRange(reordered);
        Store.ScheduleSession();
        Notify();
    }

    public async void Navigate(string input)
    {
        var target = AddressParser.Resolve(input, Prefs.Search);
        switch (target.Kind)
        {
            case AddressKind.Web: Selected?.Load(target.Value); break;
            case AddressKind.External: await ExternalAsync(target.Value); break;
            default: Show(Text("этот адрес или протокол не поддерживается", "Этот адрес или протокол не поддерживается")); break;
        }
    }

    public async Task ExternalAsync(string url)
    {
        var scheme = url.Split(':')[0].ToLowerInvariant();
        if (scheme != "mailto" && scheme != "tel") { Show(Text("этот протокол не поддерживается: ", "Этот протокол не поддерживается: ") + scheme); return; }
        var answer = await Dialogs.Ask(Window, Text("открыть другое приложение?", "Открыть другое приложение?"), url, [Text("отмена", "Отмена"), Text("открыть", "Открыть")]);
        if (answer == 1) await Windows.System.Launcher.LaunchUriAsync(new Uri(url));
    }

    public void ZoomBy(double step) { if (Selected is { } tab) tab.SetZoom(step == 0 ? 1 : Math.Clamp(tab.Zoom + step, 0.5, 3)); }

    public void Dispose()
    {
        Downloads.CancelAll();
        foreach (var tab in Tabs) tab.Dispose();
        Tabs.Clear(); Closed.Clear(); TransientPermissions.Clear();
    }
}
