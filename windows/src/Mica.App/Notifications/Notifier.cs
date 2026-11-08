using Microsoft.Web.WebView2.Core;
using Microsoft.Windows.AppLifecycle;
using Microsoft.Windows.AppNotifications;
using Microsoft.Windows.AppNotifications.Builder;
using Mica.Core;

namespace Mica.App.Notifications;

/// <summary>Web notifications as Windows toasts. WebView2 implements the Notifications API itself; mica decides the
/// permission (Permissions.Handle) and shows each notification through App Notifications, so clicks come back to the
/// right tab. Push and service worker notifications of closed sites are not supported, the same as on macOS.</summary>
public sealed partial class Notifier
{
    public static readonly Notifier Shared = new();
    readonly Dictionary<string, (WeakReference<Tab> Tab, CoreWebView2Notification Notification)> live = [];
    bool registered;

    public void Start()
    {
        if (registered || Program.QA && !Program.Has("--notifications")) return;
        try
        {
            AppNotificationManager.Default.NotificationInvoked += (_, e) => MicaApplication.Current?.Dispatcher.TryEnqueue(() => Invoke(e.Arguments));
            AppNotificationManager.Default.Register();
            registered = true;
        }
        catch (Exception e) { Diagnostics.Log.Error(e); }
    }

    /// <summary>What Windows says about toasts for mica; off means the user disabled them in Windows settings.</summary>
    public bool SystemAllows => registered && AppNotificationManager.Default.Setting == AppNotificationSetting.Enabled;

    public void Activated(AppActivationArguments e) { if (e.Data is AppNotificationActivatedEventArgs args) Invoke(args.Arguments); }

    public void Show(Tab tab, CoreWebView2NotificationReceivedEventArgs e)
    {
        e.Handled = true;
        var deferral = e.GetDeferral();
        try
        {
            var owner = tab.Owner;
            var origin = Origin.Of(e.SenderOrigin) ?? e.SenderOrigin;
            if (owner is null || owner.PrivateMode || NotificationPolicy.State(origin, false, owner.Store.Permissions) != NotificationState.Granted || !SystemAllows) return;
            var n = e.Notification;
            var parsed = WebNotification.Parse(Guid.NewGuid().ToString("N"), n.Title, n.Body, n.Tag, n.IsSilent);
            if (parsed is null) return;
            var id = WebNotification.Identifier(origin, tab.Id, parsed);
            var builder = new AppNotificationBuilder()
                .AddArgument("tab", tab.Id.ToString())
                .AddArgument("id", id)
                .AddText(parsed.Title)
                .SetAttributionText(AddressParser.Host(origin) ?? origin);
            if (parsed.Body.Length > 0) builder.AddText(parsed.Body);
            if (parsed.Silent) builder.MuteAudio();
            var toast = builder.BuildNotification();
            toast.Tag = Truncate(parsed.Tag.Length > 0 ? parsed.Tag : parsed.Id, 64);
            toast.Group = Truncate(AddressParser.Host(origin) ?? "web", 64);
            AppNotificationManager.Default.Show(toast);
            live[id] = (new WeakReference<Tab>(tab), n);
            n.CloseRequested += async (_, _) => { live.Remove(id); await AppNotificationManager.Default.RemoveByTagAndGroupAsync(toast.Tag, toast.Group); };
            n.ReportShown();
        }
        catch (Exception ex) { Diagnostics.Log.Error(ex); }
        finally { deferral.Complete(); }
    }

    static string Truncate(string text, int max) => text.Length <= max ? text : text[..max];

    void Invoke(IDictionary<string, string> arguments)
    {
        if (!arguments.TryGetValue("id", out var id) || !live.TryGetValue(id, out var entry)) { Store.Shared.Active?.Window?.Bring(); return; }
        if (entry.Tab.TryGetTarget(out var tab) && tab.Owner is { } owner)
        {
            owner.Window?.Bring();
            owner.Select(tab);
        }
        entry.Notification.ReportClicked();
    }

    public void RemoveFor(Tab tab)
    {
        foreach (var key in live.Where(kv => !kv.Value.Tab.TryGetTarget(out var t) || t == tab).Select(kv => kv.Key).ToList())
        {
            live[key].Notification.ReportClosed();
            live.Remove(key);
        }
    }
}
