using Microsoft.Win32;

namespace Mica.Install;

/// <summary>Per-user registration as a browser (no administrator rights): StartMenuInternet capabilities, the
/// micaURL and micaHTML ProgIDs, and RegisteredApplications. The installer writes the same keys; the app repeats it
/// so a moved or portable copy still offers itself.</summary>
public static class DefaultBrowser
{
    const string Key = @"Software\Clients\StartMenuInternet\mica";
    static string Exe => Environment.ProcessPath ?? Path.Combine(AppContext.BaseDirectory, "mica.exe");

    public static void Register(string? exePath = null)
    {
        var exe = exePath ?? Exe;
        var command = $"\"{exe}\" \"%1\"";
        using (var url = Registry.CurrentUser.CreateSubKey(@"Software\Classes\micaURL"))
        {
            url.SetValue("", "mica URL");
            url.SetValue("URL Protocol", "");
            using var icon = url.CreateSubKey("DefaultIcon"); icon.SetValue("", exe + ",0");
            using var open = url.CreateSubKey(@"shell\open\command"); open.SetValue("", command);
        }
        using (var html = Registry.CurrentUser.CreateSubKey(@"Software\Classes\micaHTML"))
        {
            html.SetValue("", "mica HTML");
            using var icon = html.CreateSubKey("DefaultIcon"); icon.SetValue("", exe + ",0");
            using var open = html.CreateSubKey(@"shell\open\command"); open.SetValue("", command);
        }
        foreach (var extension in new[] { ".html", ".htm", ".xhtml", ".xht", ".pdf" })
        {
            using var openWith = Registry.CurrentUser.CreateSubKey($@"Software\Classes\{extension}\OpenWithProgids");
            openWith.SetValue("micaHTML", Array.Empty<byte>(), RegistryValueKind.None);
        }
        using (var app = Registry.CurrentUser.CreateSubKey(Key))
        {
            app.SetValue("", "mica");
            using var icon = app.CreateSubKey("DefaultIcon"); icon.SetValue("", exe + ",0");
            using var open = app.CreateSubKey(@"shell\open\command"); open.SetValue("", $"\"{exe}\"");
            using var capabilities = app.CreateSubKey("Capabilities");
            capabilities.SetValue("ApplicationName", "mica");
            capabilities.SetValue("ApplicationDescription", "mica browser");
            capabilities.SetValue("ApplicationIcon", exe + ",0");
            using var urls = capabilities.CreateSubKey("URLAssociations");
            urls.SetValue("http", "micaURL"); urls.SetValue("https", "micaURL");
            using var files = capabilities.CreateSubKey("FileAssociations");
            foreach (var extension in new[] { ".html", ".htm", ".xhtml", ".xht", ".pdf" }) files.SetValue(extension, "micaHTML");
            using var start = capabilities.CreateSubKey("StartMenu"); start.SetValue("StartMenuInternet", "mica");
        }
        using var registered = Registry.CurrentUser.CreateSubKey(@"Software\RegisteredApplications");
        registered.SetValue("mica", Key + @"\Capabilities");
    }

    public static bool IsDefault()
    {
        foreach (var scheme in new[] { "http", "https" })
        {
            using var choice = Registry.CurrentUser.OpenSubKey($@"Software\Microsoft\Windows\Shell\Associations\UrlAssociations\{scheme}\UserChoice");
            if (choice?.GetValue("ProgId") as string != "micaURL") return false;
        }
        return true;
    }

    public static async Task OpenSettingsAsync()
    {
        if (!await Windows.System.Launcher.LaunchUriAsync(new Uri("ms-settings:defaultapps?registeredAppUser=mica")))
            await Windows.System.Launcher.LaunchUriAsync(new Uri("ms-settings:defaultapps"));
    }

    /// <summary>Removes everything Register wrote. Windows forgets mica as the default when its ProgID disappears.</summary>
    public static void Unregister()
    {
        foreach (var extension in new[] { ".html", ".htm", ".xhtml", ".xht", ".pdf" })
        {
            using var openWith = Registry.CurrentUser.OpenSubKey($@"Software\Classes\{extension}\OpenWithProgids", writable: true);
            openWith?.DeleteValue("micaHTML", throwOnMissingValue: false);
        }
        foreach (var key in new[] { @"Software\Classes\micaURL", @"Software\Classes\micaHTML", Key })
            Registry.CurrentUser.DeleteSubKeyTree(key, throwOnMissingSubKey: false);
        using var registered = Registry.CurrentUser.OpenSubKey(@"Software\RegisteredApplications", writable: true);
        registered?.DeleteValue("mica", throwOnMissingValue: false);
    }
}
