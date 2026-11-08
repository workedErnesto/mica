using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Mica.Core;
using Mica.Design;

namespace Mica.App;

/// <summary>Site details under the address field (macOS SiteInfo): connection, per-site blocking and decisions.</summary>
public sealed partial class SiteInfo : StackPanel
{
    public SiteInfo(Tab tab, BrowserModel browser)
    {
        var store = browser.Store;
        Spacing = Space.Normal; Padding = new Thickness(16);
        var host = AddressParser.Host(tab.Url);
        var headline = Ui.Text(host ?? "mica", 14, null, Ui.Medium); headline.IsTextSelectionEnabled = true;
        var connection = Ui.H(4, new Glyph(tab.Secure ? "lock.fill" : "exclamationmark.shield", 11, Palette.Text2.Brush()),
            Ui.Text(tab.Secure ? browser.Text("соединение HTTPS", "Соединение HTTPS") : browser.Text("защищённое соединение не подтверждено", "Защищённое соединение не подтверждено"), 11.5, Palette.Text2.Brush()));
        Children.Add(Ui.H(10, new Monogram(host, 32), Ui.V(2, headline, connection)));
        if (host is not null)
        {
            var on = store.Preferences.Blocking && !store.Preferences.BlockingExceptions.Contains(host);
            var toggle = new Switch(on, browser.Text("блокировка рекламы на сайте", "Блокировка рекламы на сайте"));
            toggle.Toggled += value => store.Change(p =>
            {
                if (value) { p.BlockingExceptions.Remove(host); p.Blocking = true; }
                else if (!p.BlockingExceptions.Contains(host)) p.BlockingExceptions.Add(host);
            });
            var row = new Grid(); row.ColumnDefinitions.Add(Ui.Star()); row.ColumnDefinitions.Add(Ui.Auto());
            row.Column(Ui.Text(browser.Text("блокировка рекламы на сайте", "Блокировка рекламы на сайте"), 12.5), 0); row.Column(toggle, 1);
            Children.Add(row);
            Children.Add(Ui.Text(browser.Text("правила применяются к новым запросам; перезагрузите страницу для полной проверки", "Правила применяются к новым запросам; перезагрузите страницу для полной проверки"), 11, Palette.Text3.Brush(), wrap: true));
        }
        if (Origin.Of(tab.Url) is { } origin)
        {
            Children.Add(Ui.Hairline());
            foreach (var capability in SiteCapabilities.Windows.Where(c => !(browser.PrivateMode && c == SiteCapability.Notifications)))
            {
                var segmented = new Segmented<Decision>(store.DecisionFor(origin, capability, browser),
                    [(Decision.Ask, browser.Text("спрашивать", "Спрашивать")), (Decision.Allow, browser.Text("разрешить", "Разрешить")), (Decision.Deny, browser.Text("запретить", "Запретить"))], compact: true, label: store.CapabilityName(capability));
                segmented.Changed += decision => store.SetPermission(origin, capability, decision, browser);
                Children.Add(Ui.V(6, Ui.Text(store.CapabilityName(capability), 12, Palette.Text2.Brush()), segmented));
            }
            Children.Add(Ui.Text(browser.Text("отзыв разрешения действует на новые запросы. чтобы остановить идущую запись, перезагрузите страницу; windows показывает свой значок, пока камера или микрофон заняты.", "Отзыв разрешения действует на новые запросы. Чтобы остановить идущую запись, перезагрузите страницу; Windows показывает свой значок, пока камера или микрофон заняты."), 11, Palette.Text3.Brush(), wrap: true));
        }
    }
}
