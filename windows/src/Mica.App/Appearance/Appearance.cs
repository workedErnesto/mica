using System.Runtime.InteropServices;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Mica.Core;
using Mica.Design;

namespace Mica.App.Appearance;

/// <summary>App icons from the Orbit pack, converted from macOS HEIC to ICO and PNG in shared/icons/app. On Windows a
/// chosen icon shows on the taskbar and in Alt+Tab for open windows, and on mica's Start menu, desktop and taskbar
/// shortcuts while it is closed (macOS: Dock tile plug-in and the bundle's Finder icon).</summary>
public static class AppIcons
{
    public sealed record Icon(string Id, string Low, string Regular);
    public sealed record IconSet(string Id, string Low, string Regular, Icon[] Icons);
    public const string Standard = "base-original";
    public static readonly IconSet[] Sets =
    [
        new("base", "стандартные", "Стандартные", [new("base-original", "исходная", "Исходная"), new("base-light", "светлая", "Светлая"), new("base-dark", "тёмная", "Тёмная"), new("base-cream", "кремовая", "Кремовая"), new("base-purple", "фиолетовая", "Фиолетовая"), new("base-blue", "голубая", "Голубая"), new("base-pink", "розовая", "Розовая"), new("base-red-neon", "красный неон", "Красный неон")]),
        new("sonic", "sonic", "Sonic", new[] { "Sonic", "Tails", "Knuckles", "Amy", "Shadow" }.Select(n => new Icon("sonic-" + n.ToLowerInvariant(), n, n)).ToArray()),
        new("kitty", "hello kitty", "Hello Kitty", new[] { "Hello Kitty", "Kuromi", "My Melody", "Cinnamoroll", "Pompompurin" }.Select(n => new Icon("kitty-" + n.ToLowerInvariant().Replace(' ', '-'), n, n)).ToArray()),
        new("pony", "my little pony", "My Little Pony", new[] { "Twilight Sparkle", "Rainbow Dash", "Pinkie Pie", "Rarity", "Applejack", "Fluttershy" }.Select(n => new Icon("pony-" + n.ToLowerInvariant().Replace(' ', '-'), n, n)).ToArray()),
    ];

    static string Folder => Path.Combine(AppContext.BaseDirectory, "Assets", "AppIcons");
    public static string? Ico(string? id) { var path = Path.Combine(Folder, (id ?? Standard) + ".ico"); return File.Exists(path) ? path : null; }
    public static string? Png(string? id) { var path = Path.Combine(Folder, (id ?? Standard) + ".png"); return File.Exists(path) ? path : null; }
    public static bool Available => Png(Standard) is not null;

    public static void Apply(Store store)
    {
        var path = Ico(store.Preferences.AppIcon) ?? Path.Combine(AppContext.BaseDirectory, "Assets", "mica.ico");
        foreach (var window in store.Windows) window.AppWindow.SetIcon(path);
        ApplyToShortcuts(store.Preferences.AppIcon);
    }

    /// <summary>The Start menu, desktop and taskbar pins show the choice while mica is closed. The standard choice
    /// points back at mica.exe, as the installer writes them; an update recreates the Start menu shortcut, and the
    /// next launch applies the choice again. Runs off the UI thread: the shell may be slow to answer.</summary>
    static void ApplyToShortcuts(string? id)
    {
        if (Program.QA || !OperatingSystem.IsWindows() || Environment.ProcessPath is not { } exe) return;
        var ico = id is null || id == Standard ? null : Ico(id);
        _ = Task.Run(() =>
        {
            var changed = false;
            try
            {
                foreach (var link in Mica.Install.Shortcuts.ToApp())
                {
                    try { changed |= Mica.Install.Shortcuts.SetIcon(link, exe, ico ?? exe, 0); }
                    catch (Exception e) when (e is COMException or IOException or UnauthorizedAccessException or InvalidCastException) { Diagnostics.Log.Error(e); }
                }
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException) { Diagnostics.Log.Error(e); }
            if (changed) Mica.Install.Shortcuts.RefreshIcons();
        });
    }
}
