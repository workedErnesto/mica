using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Markup;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.XamlTypeInfo;
using Mica.Core;
using Mica.Design;
using Mica.Install;

namespace Mica.App.Uninstaller;

/// <summary>"Installed apps" runs mica.exe --uninstall: a small window in mica's own style asks whether to keep the
/// profile, then removes files, shortcuts and registration. --quiet does the same without a window and keeps data.</summary>
public sealed partial class UninstallApplication : Application, IXamlMetadataProvider
{
    readonly XamlControlsXamlMetaDataProvider provider = new();
    public IXamlType GetXamlType(Type type) => provider.GetXamlType(type);
    public IXamlType GetXamlType(string fullName) => provider.GetXamlType(fullName);
    public XmlnsDefinition[] GetXmlnsDefinitions() => provider.GetXmlnsDefinitions();
    Window? window;

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        Resources.MergedDictionaries.Add(new XamlControlsResources());
        var background = new Windows.UI.ViewManagement.UISettings().GetColorValue(Windows.UI.ViewManagement.UIColorType.Background);
        Palette.Apply(background.R < 128, new Windows.UI.ViewManagement.AccessibilitySettings().HighContrast);
        Look.Apply(false, "#6E56CF", 0);
        if (Program.Has("--quiet")) { _ = Remove(keepData: true).ContinueWith(_ => Exit()); return; }
        window = new Window { ExtendsContentIntoTitleBar = true, Title = "mica" };
        window.AppWindow.Resize(new Windows.Graphics.SizeInt32((int)(520 * Win32.DpiFor(window) / 96.0), (int)(380 * Win32.DpiFor(window) / 96.0)));
        if (window.AppWindow.Presenter is OverlappedPresenter p) { p.IsResizable = false; p.IsMaximizable = false; }
        window.SystemBackdrop = new MicaBackdrop();
        window.AppWindow.SetIcon(Path.Combine(AppContext.BaseDirectory, "Assets", "mica.ico"));
        window.Content = new UninstallView(this);
        window.Activate();
    }

    static string T(string low, string regular) => Copy.Text(low, regular, true, LanguageInfo.Preferred());

    internal async Task Remove(bool keepData)
    {
        var folder = AppContext.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar);
        foreach (var process in Processes.Running(folder).Where(p => p.Id != Environment.ProcessId)) { try { process.CloseMainWindow(); } catch (InvalidOperationException) { } }
        await Processes.WaitForExit(folder, TimeSpan.FromSeconds(10));
        foreach (var process in Processes.Running(folder).Where(p => p.Id != Environment.ProcessId)) { try { process.Kill(); } catch (InvalidOperationException) { } }
        DefaultBrowser.Unregister();
        Shortcuts.Remove(InstallLayout.StartMenuShortcut);
        Shortcuts.Remove(InstallLayout.DesktopShortcut);
        try { Microsoft.Windows.AppNotifications.AppNotificationManager.Default.UnregisterAll(); } catch (Exception) { }
        InstallLayout.RemoveUninstallEntry();
        if (!keepData) { try { Directory.Delete(InstallLayout.DataFolder, true); } catch (IOException) { } catch (UnauthorizedAccessException) { } }
        // The running executable cannot delete itself; a short-lived hidden shell removes the folder after exit.
        System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo("cmd.exe", $"/c timeout /t 2 /nobreak >nul & rmdir /s /q \"{folder}\"") { CreateNoWindow = true, UseShellExecute = false });
    }

    sealed partial class UninstallView : Grid
    {
        public UninstallView(UninstallApplication app)
        {
            RequestedTheme = Palette.ElementTheme;
            Background = Palette.Clear;
            var content = new StackPanel { Spacing = Space.Normal, Padding = new Thickness(36, 56, 36, 28), VerticalAlignment = VerticalAlignment.Stretch };
            var icon = new Image { Width = 56, Height = 56, HorizontalAlignment = HorizontalAlignment.Left, Source = new Microsoft.UI.Xaml.Media.Imaging.BitmapImage(new Uri(Path.Combine(AppContext.BaseDirectory, "Assets", "mica-512.png"))) };
            var title = Ui.Text(T("удалить mica?", "Удалить mica?"), 24, null, Ui.Weight(300)); title.CharacterSpacing = -20;
            var detail = Ui.Text(T("приложение будет удалено с этого компьютера. закладки, история и пароли хранятся отдельно, их можно оставить.", "Приложение будет удалено с этого компьютера. Закладки, история и пароли хранятся отдельно, их можно оставить."), 13, Palette.Text2.Brush(), wrap: true);
            var data = new ToggleRow(T("удалить также данные профиля", "Удалить также данные профиля"), false, _ => { }, divider: false, detail: T("история, закладки, пароли, cookie и настройки", "История, закладки, пароли, cookie и настройки"));
            var group = new SettingsGroup().Add(data);
            var cancel = new MButton(T("отмена", "Отмена"), ButtonKind.Ghost);
            var remove = new MButton(T("удалить", "Удалить"), ButtonKind.Destructive);
            var buttons = Ui.H(Space.Small, cancel, remove); buttons.HorizontalAlignment = HorizontalAlignment.Right;
            content.Children.Add(icon); content.Children.Add(title); content.Children.Add(detail); content.Children.Add(group); content.Children.Add(buttons);
            Children.Add(content);
            cancel.Click += () => app.Exit();
            remove.Click += async () =>
            {
                remove.IsEnabled = cancel.IsEnabled = false; remove.Title = T("удаляем…", "Удаляем…");
                await app.Remove(keepData: !data.Switch.IsOn);
                content.Children.Clear();
                var done = Ui.Text(T("mica удалена", "mica удалена"), 24, null, Ui.Weight(300));
                var close = new MButton(T("закрыть", "Закрыть"), ButtonKind.Primary);
                close.Click += () => app.Exit();
                content.Children.Add(icon); content.Children.Add(done); content.Children.Add(close);
                Motion.Appear(done, Motion.Edge.Bottom);
            };
            Loaded += (_, _) => Motion.Appear(content, Motion.Edge.Bottom, Motion.Panel);
        }
    }
}
