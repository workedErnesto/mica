using Mica.Core;
using Microsoft.Web.WebView2.Core;

namespace Mica.App;

/// <summary>Site permissions on WebView2. Camera, microphone, notifications and location use mica's saved decisions
/// and question; other kinds get a one-time question. The requesting origin must be HTTPS and match the frame.</summary>
public static class Permissions
{
    public static async void Handle(Tab tab, CoreWebView2PermissionRequestedEventArgs e)
    {
        var owner = tab.Owner;
        if (owner is null) { e.State = CoreWebView2PermissionState.Deny; return; }
        var deferral = e.GetDeferral();
        e.SavesInProfile = false;
        try { e.State = await Decide(tab, owner, e); }
        catch (Exception) { e.State = CoreWebView2PermissionState.Deny; }
        finally { deferral.Complete(); }
    }

    static SiteCapability? Capability(CoreWebView2PermissionKind kind) => kind switch
    {
        CoreWebView2PermissionKind.Camera => SiteCapability.Camera,
        CoreWebView2PermissionKind.Microphone => SiteCapability.Microphone,
        CoreWebView2PermissionKind.Notifications => SiteCapability.Notifications,
        CoreWebView2PermissionKind.Geolocation => SiteCapability.Location,
        _ => null,
    };

    static async Task<CoreWebView2PermissionState> Decide(Tab tab, BrowserModel owner, CoreWebView2PermissionRequestedEventArgs e)
    {
        var store = owner.Store;
        var origin = Origin.Of(e.Uri);
        if (origin is null || !Origin.Secure(origin)) return CoreWebView2PermissionState.Deny;
        var top = Origin.Of(tab.Core?.Source);
        var embedded = top is not null && top != origin;
        if (Capability(e.PermissionKind) is not { } capability)
        {
            if (e.PermissionKind == CoreWebView2PermissionKind.Autoplay) return CoreWebView2PermissionState.Deny;
            if (owner.SelectedId != tab.Id || !e.IsUserInitiated) return CoreWebView2PermissionState.Deny;
            var once = await Dialogs.Ask(owner.Window, origin, store.Text("сайт запрашивает: ", "Сайт запрашивает: ") + Describe(store, e.PermissionKind), [store.Text("запретить", "Запретить"), store.Text("разрешить один раз", "Разрешить один раз")]);
            return once == 1 ? CoreWebView2PermissionState.Allow : CoreWebView2PermissionState.Deny;
        }
        if (capability == SiteCapability.Notifications)
        {
            var state = NotificationPolicy.State(origin, owner.PrivateMode, owner.PrivateMode ? owner.TransientPermissions : store.Permissions);
            if (state != NotificationState.Default) return state == NotificationState.Granted ? CoreWebView2PermissionState.Allow : CoreWebView2PermissionState.Deny;
            if (!store.Preferences.NotificationRequests || embedded) return CoreWebView2PermissionState.Deny;
            if (!NotificationPolicy.MayAsk(origin, owner.PrivateMode, owner.SelectedId == tab.Id && owner.Window?.IsKey == true, e.IsUserInitiated, true)) return CoreWebView2PermissionState.Default;
            var answer = await Dialogs.Ask(owner.Window, origin + ": " + store.CapabilityName(capability),
                store.Text("сайт хочет показывать уведомления, пока вкладка открыта. windows отдельно проверит, разрешены ли уведомления mica.", "Сайт хочет показывать уведомления, пока вкладка открыта. Windows отдельно проверит, разрешены ли уведомления mica."),
                [store.Text("не сейчас", "Не сейчас"), store.Text("запретить", "Запретить"), store.Text("разрешить", "Разрешить")]);
            if (answer == 2)
            {
                if (!Notifications.Notifier.Shared.SystemAllows) owner.Show(store.Text("windows запрещает уведомления mica. разрешите их в параметрах windows, раздел «уведомления».", "Windows запрещает уведомления mica. Разрешите их в параметрах Windows, раздел «Уведомления»."));
                store.SetPermission(origin, capability, Decision.Allow, owner);
                return CoreWebView2PermissionState.Allow;
            }
            if (answer == 1) { store.SetPermission(origin, capability, Decision.Deny, owner); return CoreWebView2PermissionState.Deny; }
            return CoreWebView2PermissionState.Default;
        }
        var decision = store.DecisionFor(origin, capability, owner);
        if (decision == Decision.Deny) return CoreWebView2PermissionState.Deny;
        if (decision == Decision.Allow) return CoreWebView2PermissionState.Allow;
        if (owner.SelectedId != tab.Id) return CoreWebView2PermissionState.Deny;
        var detail = capability == SiteCapability.Location
            ? store.Text("сайт запрашивает ваше местоположение. windows отдельно проверит доступ к геолокации.", "Сайт запрашивает ваше местоположение. Windows отдельно проверит доступ к геолокации.")
            : store.Text("сайт запрашивает доступ для записи или звонка. windows отдельно проверит системное разрешение.", "Сайт запрашивает доступ для записи или звонка. Windows отдельно проверит системное разрешение.");
        if (embedded) detail += "\n" + store.Text("запрос из встроенного фрейма на ", "Запрос из встроенного фрейма на ") + top;
        var choice = await Dialogs.Ask(owner.Window, origin + ": " + store.CapabilityName(capability), detail,
            [store.Text("запретить", "Запретить"), store.Text("разрешить один раз", "Разрешить один раз"), store.Text("разрешить для сайта", "Разрешить для сайта")]);
        if (choice != 1) store.SetPermission(origin, capability, choice == 2 ? Decision.Allow : Decision.Deny, owner);
        return choice == 0 || choice < 0 ? CoreWebView2PermissionState.Deny : CoreWebView2PermissionState.Allow;
    }

    static string Describe(Store store, CoreWebView2PermissionKind kind) => kind switch
    {
        CoreWebView2PermissionKind.ClipboardRead => store.Text("чтение буфера обмена", "Чтение буфера обмена"),
        CoreWebView2PermissionKind.MultipleAutomaticDownloads => store.Text("несколько загрузок подряд", "Несколько загрузок подряд"),
        CoreWebView2PermissionKind.FileReadWrite => store.Text("доступ к выбранным файлам", "Доступ к выбранным файлам"),
        CoreWebView2PermissionKind.MidiSystemExclusiveMessages => store.Text("управление MIDI-устройствами", "Управление MIDI-устройствами"),
        CoreWebView2PermissionKind.WindowManagement => store.Text("расположение окон на экранах", "Расположение окон на экранах"),
        CoreWebView2PermissionKind.OtherSensors => store.Text("датчики устройства", "Датчики устройства"),
        _ => kind.ToString(),
    };
}
