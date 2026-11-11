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
