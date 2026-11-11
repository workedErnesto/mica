using System.IO.Compression;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Mica.Core;
using Mica.Design;
using Windows.Storage.Pickers;

namespace Mica.App.Import;

/// <summary>Moves history and bookmarks from browsers on this computer into mica (macOS ImportManager). Files are read
/// from copies; the source browser is never written to. Windows needs no folder permission, so found profiles are
/// readable at once; a running Chrome may hold its files open, which the copy works around.</summary>
public sealed partial class ImportManager(Store store)
{
    public sealed record Summary(string Source, int History, int Bookmarks, List<string> Problems);
    public enum Phase { Idle, Reading, Done, Failed }
    public List<ImportProfile> Profiles { get; private set; } = [];
    public bool Discovered { get; private set; }
    public string? Selection { get; set; }
    public HashSet<ImportKind> Kinds { get; } = [ImportKind.History, ImportKind.Bookmarks];
    public Phase State { get; private set; }
    public Summary? Result { get; private set; }
    public string? Failure { get; private set; }
    public event Action? Changed;
    public ImportProfile? Selected => Profiles.FirstOrDefault(p => p.Id == Selection);

    public async void Discover()
    {
        Profiles = await Task.Run(() => ImportDiscovery.Profiles());
        if (Selection is not null && !Profiles.Any(p => p.Id == Selection)) Selection = null;
        Discovered = true;
        Changed?.Invoke();
    }

    public string Title(ImportProfile profile) => profile.Browser.DisplayName(store.TextStyle(store.Active?.ProfileId).Language);
    public void Select(ImportProfile profile) { if (State == Phase.Reading) return; Reset(); Selection = profile.Id; Changed?.Invoke(); }
    public void Reset() { State = Phase.Idle; Result = null; Failure = null; }

    public async void Run()
    {
        if (Selected is not { } profile || State == Phase.Reading || Kinds.Count == 0) return;
        State = Phase.Reading; Changed?.Invoke();
        var wanted = Kinds.ToHashSet();
        var (bundle, failures) = await Task.Run(() => ImportReader.Read(profile, wanted));
        var (history, bookmarks) = Apply(bundle);
        Result = new Summary(Title(profile), history, bookmarks, failures.OrderBy(f => f.Key).Select(f => Describe(f.Value, f.Key)).ToList());
        State = Phase.Done; Changed?.Invoke();
    }

    public async void ChooseExport(nint window)
    {
        var picker = new FileOpenPicker { SuggestedStartLocation = PickerLocationId.Downloads };
        foreach (var type in new[] { ".html", ".htm", ".json", ".zip" }) picker.FileTypeFilter.Add(type);
        WinRT.Interop.InitializeWithWindow.Initialize(picker, window);
        var file = await picker.PickSingleFileAsync();
        if (file is null) return;
        State = Phase.Reading; Changed?.Invoke();
        try
        {
            var bundle = await Task.Run(() =>
            {
                if (!file.Path.EndsWith(".zip", StringComparison.OrdinalIgnoreCase)) return ExportReader.Read(file.Path);
                var folder = Path.Combine(Path.GetTempPath(), "mica-export-" + Guid.NewGuid().ToString("N"));
                try
                {
                    using var archive = System.IO.Compression.ZipFile.OpenRead(file.Path);
                    foreach (var entry in archive.Entries)
                    {
                        if (!PackageSafety.SafeEntry(entry.FullName) || entry.FullName.EndsWith('/')) continue;
                        var target = Path.GetFullPath(Path.Combine(folder, entry.FullName));
                        if (!target.StartsWith(folder, StringComparison.OrdinalIgnoreCase)) continue;
                        Directory.CreateDirectory(Path.GetDirectoryName(target)!);
                        entry.ExtractToFile(target);
                    }
                    return ExportReader.Read(folder);
                }
                finally { try { Directory.Delete(folder, true); } catch (IOException) { } }
            });
            var (history, bookmarks) = Apply(bundle);
            Result = new Summary(file.Name, history, bookmarks, []);
            State = Phase.Done;
        }
        catch (Exception e) when (e is ImportException or IOException or InvalidDataException)
        {
            Failure = store.Text("в файле нет закладок или истории в известном формате", "В файле нет закладок или истории в известном формате");
            State = Phase.Failed;
        }
        Changed?.Invoke();
    }

    public async void ChooseProfile(nint window)
    {
        var picker = new FolderPicker { SuggestedStartLocation = PickerLocationId.ComputerFolder };
        picker.FileTypeFilter.Add("*");
        WinRT.Interop.InitializeWithWindow.Initialize(picker, window);
        var folder = await picker.PickSingleFolderAsync();
        if (folder is null) return;
        var found = ImportDiscovery.ProfilesIn(folder.Path);
        if (found.Count == 0) { Failure = store.Text("профили в этой папке не найдены", "Профили в этой папке не найдены"); State = Phase.Failed; Changed?.Invoke(); return; }
        foreach (var profile in found) if (!Profiles.Any(p => p.Id == profile.Id)) Profiles.Add(profile);
        Selection = found[0].Id;
        Reset();
        Changed?.Invoke();
    }

    (int History, int Bookmarks) Apply(ImportBundle bundle)
    {
        int history = 0, bookmarks = 0;
        if (bundle.History.Count > 0) { var merged = ImportMerge.History(store.History, bundle.History); store.SetHistory(merged.Merged); history = merged.Added; }
        if (bundle.Bookmarks.Count > 0) { var merged = ImportMerge.Bookmarks(store.Bookmarks, bundle.Bookmarks); store.SetBookmarks(merged.Merged); bookmarks = merged.Added; }
        return (history, bookmarks);
    }

    string Describe(ImportException error, ImportKind kind)
    {
        var what = kind == ImportKind.History ? store.Text("история", "История") : store.Text("закладки", "Закладки");
        return error.Failure switch
        {
            ImportFailure.NoAccess => what + store.Text(": нет доступа к файлу", ": нет доступа к файлу"),
            ImportFailure.Locked => what + store.Text(": файл занят браузером. закройте его и повторите", ": файл занят браузером. Закройте его и повторите"),
            _ => what + store.Text(": файл не прочитан, возможно, браузер сменил формат", ": файл не прочитан, возможно, браузер сменил формат"),
        };
    }
}

/// <summary>Source browser, what to bring, and the result; shared by onboarding and settings.</summary>
public sealed partial class ImportView : StackPanel
{
    readonly BrowserModel browser;
    public ImportView(BrowserModel browser)
    {
        this.browser = browser;
        Spacing = Space.Normal;
        var manager = browser.Store.Importer;
        this.Bind(h => manager.Changed += h, h => manager.Changed -= h, Render);
        Loaded += (_, _) => { if (!manager.Discovered) manager.Discover(); };
    }

    void Render()
    {
        var s = browser.Store; var m = s.Importer;
        Children.Clear();
        if (!m.Discovered) { Children.Add(Ui.Text(s.Text("ищем браузеры на этом компьютере", "Ищем браузеры на этом компьютере"), 12.5, Palette.Text2.Brush())); return; }
        if (m.Profiles.Count == 0) Children.Add(Ui.Text(s.Text("доступные профили не найдены. можно выбрать папку профиля или файл экспорта", "Доступные профили не найдены. Можно выбрать папку профиля или файл экспорта"), 12.5, Palette.Text2.Brush(), wrap: true));
        else
        {
            var group = new SettingsGroup(s.Text("откуда", "Откуда"));
            for (var i = 0; i < m.Profiles.Count; i++) group.Add(SourceRow(m.Profiles[i], i < m.Profiles.Count - 1));
            Children.Add(group);
            if (m.Selected is null) Children.Add(Ui.Text(s.Text("выберите браузер, чтобы открыть его данные", "Выберите браузер, чтобы открыть его данные"), 12.5, Palette.Text2.Brush(), wrap: true));
            else
            {
                Children.Add(new SettingsGroup(s.Text("что перенести", "Что перенести"), s.Text("входы на сайты и пароли не переносятся. исходный браузер не изменяется", "Входы на сайты и пароли не переносятся. Исходный браузер не изменяется"))
                    .Add(new ToggleRow(s.Text("история", "История"), m.Kinds.Contains(ImportKind.History), v => { if (v) m.Kinds.Add(ImportKind.History); else m.Kinds.Remove(ImportKind.History); Render(); }))
                    .Add(new ToggleRow(s.Text("закладки и избранное", "Закладки и избранное"), m.Kinds.Contains(ImportKind.Bookmarks), v => { if (v) m.Kinds.Add(ImportKind.Bookmarks); else m.Kinds.Remove(ImportKind.Bookmarks); Render(); }, divider: false)));
            }
        }
        var actions = Ui.H(Space.Small);
        if (m.Selected is not null)
        {
            var run = new MButton(s.Text("перенести", "Перенести"), ButtonKind.Primary) { IsEnabled = m.State != ImportManager.Phase.Reading && m.Kinds.Count > 0 };
            run.Click += m.Run;
            actions.Children.Add(run);
        }
        var other = new MButton(s.Text("другие источники…", "Другие источники…")) { IsEnabled = m.State != ImportManager.Phase.Reading };
        var hwnd = browser.Window is { } w ? Win32.Handle(w) : 0;
        other.Click += () => MicaMenu.ShowBelow([
            MenuEntry.Item(s.Text("выбрать папку профиля…", "Выбрать папку профиля…"), () => m.ChooseProfile(hwnd)),
            MenuEntry.Item(s.Text("из файла экспорта…", "Из файла экспорта…"), () => m.ChooseExport(hwnd)),
        ], other);
        actions.Children.Add(other);
        if (m.State == ImportManager.Phase.Reading) actions.Children.Add(new Microsoft.UI.Xaml.Controls.ProgressRing { IsActive = true, Width = 16, Height = 16 });
        Children.Add(actions);
        if (m.State == ImportManager.Phase.Done && m.Result is { } r)
        {
            var result = Ui.V(4, Ui.Text(s.Text("готово: ", "Готово: ") + r.Source, 13, null, Ui.Medium), Ui.Text(s.Text("история: ", "История: ") + r.History + ", " + s.Text("закладки: ", "Закладки: ") + r.Bookmarks, 12.5, Palette.Text2.Brush()));
            foreach (var problem in r.Problems) result.Children.Add(Ui.Text(problem, 12, Palette.Text3.Brush(), wrap: true));
            Children.Add(result); Motion.Appear(result);
        }
        if (m.State == ImportManager.Phase.Failed && m.Failure is { } f) Children.Add(Ui.Text(f, 12.5, Palette.Danger.Brush(), wrap: true));
    }

    FrameworkElement SourceRow(ImportProfile profile, bool divider)
    {
        var m = browser.Store.Importer;
        var chosen = m.Selection == profile.Id;
        var row = new Grid { Padding = new Thickness(14, 8, 14, 8), ColumnSpacing = 10, Background = Palette.Clear };
        row.ColumnDefinitions.Add(Ui.Auto()); row.ColumnDefinitions.Add(Ui.Star()); row.ColumnDefinitions.Add(Ui.Auto());
        row.Column(new Monogram(profile.Browser.Name, 22), 0);
        var labels = Ui.V(1, Ui.Text(m.Title(profile), 13));
        if (profile.Name.Length > 0 && m.Profiles.Count(p => p.Browser == profile.Browser) > 1) labels.Children.Add(Ui.Text(profile.Name, 11.5, Palette.Text3.Brush()));
        row.Column(labels, 1);
        row.Column(new Glyph("checkmark", 12, Palette.Ink.Brush()) { Opacity = chosen ? 1 : 0, VerticalAlignment = VerticalAlignment.Center }, 2);
        var plate = Ui.Rounded(8); plate.Margin = new Thickness(-11, -5, -11, -5); Grid.SetColumnSpan(plate, 3); row.Children.Insert(0, plate);
        var interaction = new Interaction(row, () => { }, 0.99);
        row.PointerEntered += (_, _) => plate.Background = Palette.Hover.Brush();
        row.PointerExited += (_, _) => plate.Background = Palette.Clear;
        interaction.Invoked += () => m.Select(profile);
        var stack = Ui.V(0, row);
        if (divider) stack.Children.Add(Ui.Hairline().Margin(46, 0, 0, 0));
        return stack;
    }
}
