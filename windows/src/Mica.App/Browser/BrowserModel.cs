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
    public Settings.SettingsSection SettingsSection { get; set; } = Mica.App.Settings.SettingsSection.Space;
    public int OnboardingStep { get; set; }
    /// <summary>A window-level card covers the page; the web view takes no input meanwhile.</summary>
    public bool Modal => showSettings || showOnboarding || showClearData;
    public event Action? FocusAddressRequested;
    /// <summary>F10 or Alt+F: the "…" menu that stands in for the macOS menu bar.</summary>
    public event Action? MenuRequested;
    public void RequestMenu() => MenuRequested?.Invoke();
    public event Action<Tab>? WebViewCreated;
    public event Action<string>? Message;

    public BrowserModel(Store store, bool privateMode)
    {
        Store = store; PrivateMode = privateMode;
        Downloads = new Downloads.DownloadManager(this);
        showOnboarding = !store.Preferences.OnboardingComplete && !privateMode;
    }

    public string Text(string low, string regular) => Store.Text(low, regular);
    public Tab? Selected => Tabs.FirstOrDefault(t => t.Id == SelectedId);
    public SavedWindow Snapshot => new() { Tabs = Tabs.Select(t => t.Saved).ToList(), Selected = SelectedId };

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
    public void Close(Tab tab)
    {
        var index = Tabs.FindIndex(t => t.Id == tab.Id);
        if (index < 0) return;
        Closed.Insert(0, tab.Saved);
        if (Closed.Count > 30) Closed.RemoveRange(30, Closed.Count - 30);
        tab.Dispose();
        Tabs.RemoveAt(index);
        if (SelectedId == tab.Id)
        {
            if (Tabs.Count > 0) Select(Tabs[Math.Min(index, Tabs.Count - 1)]);
            else Add();
        }
        Store.ScheduleSession();
        Notify();
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
        var target = AddressParser.Resolve(input, Store.Preferences.Search);
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
