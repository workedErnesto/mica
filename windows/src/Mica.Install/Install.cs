using System.IO.Compression;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.Marshalling;
using Microsoft.Win32;

namespace Mica.Install;

/// <summary>Where mica lives for the current user. No administrator rights: like the per-user setups of Chrome and
/// VS Code, files go to %LOCALAPPDATA%\Programs\mica, data stays in %LOCALAPPDATA%\mica.</summary>
public static class InstallLayout
{
    public static string DefaultFolder => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "mica");
    public static string DataFolder => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "mica");
    public static string StartMenuShortcut => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs), "mica.lnk");
    public static string DesktopShortcut => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), "mica.lnk");
    const string UninstallKey = @"Software\Microsoft\Windows\CurrentVersion\Uninstall\mica";

    public static string? InstalledFolder()
    {
        using var key = Registry.CurrentUser.OpenSubKey(UninstallKey);
        return key?.GetValue("InstallLocation") as string;
    }

    public static string? InstalledVersion()
    {
        using var key = Registry.CurrentUser.OpenSubKey(UninstallKey);
        return key?.GetValue("DisplayVersion") as string;
    }

    /// <summary>The entry in "Installed apps"; uninstalling runs mica itself with --uninstall.</summary>
    public static void WriteUninstallEntry(string folder, string version, long bytes)
    {
        var exe = Path.Combine(folder, "mica.exe");
        using var key = Registry.CurrentUser.CreateSubKey(UninstallKey);
        key.SetValue("DisplayName", "mica");
        key.SetValue("DisplayVersion", version);
        key.SetValue("Publisher", "mica");
        key.SetValue("DisplayIcon", exe + ",0");
        key.SetValue("InstallLocation", folder);
        key.SetValue("UninstallString", $"\"{exe}\" --uninstall");
        key.SetValue("QuietUninstallString", $"\"{exe}\" --uninstall --quiet");
        key.SetValue("NoModify", 1, RegistryValueKind.DWord);
        key.SetValue("NoRepair", 1, RegistryValueKind.DWord);
        key.SetValue("EstimatedSize", (int)(bytes / 1024), RegistryValueKind.DWord);
        key.SetValue("URLInfoAbout", "https://github.com/workedErnesto/mica");
        key.SetValue("InstallDate", DateTime.Now.ToString("yyyyMMdd"));
    }

    public static void RemoveUninstallEntry() => Registry.CurrentUser.DeleteSubKeyTree(UninstallKey, throwOnMissingSubKey: false);
}

/// <summary>WebView2 Evergreen Runtime: present on Windows 11 and on most up-to-date Windows 10 machines.</summary>
public static class Runtime
{
    const string ClientKey = @"Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}";
    public const string BootstrapperUrl = "https://go.microsoft.com/fwlink/p/?LinkId=2124703";

    public static string? WebView2Version()
    {
        foreach (var (hive, path) in new[] { (Registry.LocalMachine, @"SOFTWARE\WOW6432Node\" + ClientKey), (Registry.LocalMachine, @"SOFTWARE\" + ClientKey), (Registry.CurrentUser, @"Software\" + ClientKey) })
        {
            using var key = hive.OpenSubKey(path);
            if (key?.GetValue("pv") is string version && version.Length > 0 && version != "0.0.0.0") return version;
        }
        return null;
    }
}

/// <summary>Unpacks the embedded application archive, reporting real progress in bytes.</summary>
public static class Payload
{
    public static long Size(Stream archive)
    {
        using var zip = new ZipArchive(archive, ZipArchiveMode.Read, leaveOpen: true);
        return zip.Entries.Sum(e => e.Length);
    }

    /// <summary>Extracts into a staging folder beside the target, then swaps it in, so a failed or interrupted
    /// install leaves the previous version working.</summary>
    public static long Extract(Stream archive, string folder, IProgress<(long Done, long Total, string File)> progress, CancellationToken token)
    {
        var parent = Path.GetDirectoryName(Path.GetFullPath(folder))!;
        Directory.CreateDirectory(parent);
        var staging = folder + ".new";
        if (Directory.Exists(staging)) Directory.Delete(staging, true);
        Directory.CreateDirectory(staging);
        long done = 0;
        using (var zip = new ZipArchive(archive, ZipArchiveMode.Read, leaveOpen: true))
        {
            var total = zip.Entries.Sum(e => e.Length);
            var root = Path.GetFullPath(staging) + Path.DirectorySeparatorChar;
            var buffer = new byte[1 << 16];
            foreach (var entry in zip.Entries)
            {
                token.ThrowIfCancellationRequested();
                var target = Path.GetFullPath(Path.Combine(staging, entry.FullName));
                if (!target.StartsWith(root, StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("unsafe path " + entry.FullName);
                if (entry.FullName.EndsWith('/')) { Directory.CreateDirectory(target); continue; }
                Directory.CreateDirectory(Path.GetDirectoryName(target)!);
                using var input = entry.Open();
                using var output = File.Create(target);
                int read;
                while ((read = input.Read(buffer)) > 0)
                {
                    output.Write(buffer, 0, read);
                    done += read;
                    progress.Report((done, total, entry.Name));
                }
            }
        }
        var old = folder + ".old";
        if (Directory.Exists(old)) Directory.Delete(old, true);
        if (Directory.Exists(folder)) Directory.Move(folder, old);
        Directory.Move(staging, folder);
        try { if (Directory.Exists(old)) Directory.Delete(old, true); } catch (IOException) { } catch (UnauthorizedAccessException) { }
        return done;
    }
}

/// <summary>Start menu and desktop shortcuts through IShellLink, with source-generated COM (works under AOT).</summary>
public static partial class Shortcuts
{
    public static void Create(string path, string target, string description)
    {
        var clsid = new Guid("00021401-0000-0000-C000-000000000046");
        var iid = typeof(IShellLinkW).GUID;
        Marshal.ThrowExceptionForHR(CoCreateInstance(clsid, 0, 1, iid, out var pointer));
        var wrappers = new StrategyBasedComWrappers();
        var link = (IShellLinkW)wrappers.GetOrCreateObjectForComInstance(pointer, CreateObjectFlags.None);
        Marshal.Release(pointer);
        link.SetPath(target);
        link.SetWorkingDirectory(Path.GetDirectoryName(target)!);
        link.SetDescription(description);
        link.SetIconLocation(target, 0);
        var file = (IPersistFile)link;
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        file.Save(path, true);
    }

    public static void Remove(string path) { try { if (File.Exists(path)) File.Delete(path); } catch (IOException) { } }

    [LibraryImport("ole32.dll")]
    private static partial int CoCreateInstance(in Guid clsid, nint outer, uint context, in Guid iid, out nint result);

    [GeneratedComInterface, Guid("000214F9-0000-0000-C000-000000000046")]
    internal partial interface IShellLinkW
    {
        void GetPath(nint file, int max, nint data, uint flags);
        void GetIDList(out nint list);
        void SetIDList(nint list);
        void GetDescription(nint name, int max);
        void SetDescription([MarshalAs(UnmanagedType.LPWStr)] string name);
        void GetWorkingDirectory(nint dir, int max);
        void SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] string dir);
        void GetArguments(nint args, int max);
        void SetArguments([MarshalAs(UnmanagedType.LPWStr)] string args);
        void GetHotkey(out ushort key);
        void SetHotkey(ushort key);
        void GetShowCmd(out int show);
        void SetShowCmd(int show);
        void GetIconLocation(nint path, int max, out int index);
        void SetIconLocation([MarshalAs(UnmanagedType.LPWStr)] string path, int index);
        void SetRelativePath([MarshalAs(UnmanagedType.LPWStr)] string path, uint reserved);
        void Resolve(nint hwnd, uint flags);
        void SetPath([MarshalAs(UnmanagedType.LPWStr)] string file);
    }

    [GeneratedComInterface, Guid("0000010b-0000-0000-C000-000000000046")]
    internal partial interface IPersistFile
    {
        void GetClassID(out Guid clsid);
        [PreserveSig] int IsDirty();
        void Load([MarshalAs(UnmanagedType.LPWStr)] string file, uint mode);
        void Save([MarshalAs(UnmanagedType.LPWStr)] string file, [MarshalAs(UnmanagedType.Bool)] bool remember);
        void SaveCompleted([MarshalAs(UnmanagedType.LPWStr)] string file);
        void GetCurFile(out nint file);
    }
}

/// <summary>Waits for running copies of mica to exit (an update replaces their files).</summary>
public static class Processes
{
    public static IEnumerable<System.Diagnostics.Process> Running(string folder) =>
        System.Diagnostics.Process.GetProcessesByName("mica").Where(p => { try { return p.MainModule?.FileName?.StartsWith(folder, StringComparison.OrdinalIgnoreCase) == true; } catch (System.ComponentModel.Win32Exception) { return false; } });

    public static async Task<bool> WaitForExit(string folder, TimeSpan timeout)
    {
        var deadline = DateTime.UtcNow + timeout;
        while (DateTime.UtcNow < deadline)
        {
            if (!Running(folder).Any()) return true;
            await Task.Delay(250);
        }
        return !Running(folder).Any();
    }
}
