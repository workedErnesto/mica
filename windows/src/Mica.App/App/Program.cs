using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.Windows.AppLifecycle;

namespace Mica.App;

public static class Program
{
    public static string[] Arguments { get; private set; } = [];
    public static bool Has(string flag) => Arguments.Contains(flag);
    public static bool QA => Has("--qa");

    /// <summary>One process per profile: a second launch (a link from another app when mica is the default browser,
    /// a pinned shortcut) hands its arguments to the running mica and exits.</summary>
    [STAThread]
    static int Main(string[] args)
    {
        Arguments = args;
        WinRT.ComWrappersSupport.InitializeComWrappers();
        // The uninstaller is mica itself; it must not hand over to a running copy.
        if (Has("--uninstall"))
        {
            Application.Start(callback =>
            {
                SynchronizationContext.SetSynchronizationContext(new DispatcherQueueSynchronizationContext(DispatcherQueue.GetForCurrentThread()));
                _ = new Uninstaller.UninstallApplication();
            });
            return 0;
        }
        var key = QA ? "mica-qa" : "mica";
        var instance = AppInstance.FindOrRegisterForKey(key);
        if (!instance.IsCurrent)
        {
            instance.RedirectActivationToAsync(AppInstance.GetCurrent().GetActivatedEventArgs()).AsTask().Wait();
            return 0;
        }
        instance.Activated += (_, e) => MicaApplication.Redirected(e);
        Application.Start(callback =>
        {
            var context = new DispatcherQueueSynchronizationContext(DispatcherQueue.GetForCurrentThread());
            SynchronizationContext.SetSynchronizationContext(context);
            _ = new MicaApplication();
        });
        return 0;
    }
}
