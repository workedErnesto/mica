using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Mica.Core;
using Mica.Design;

namespace Mica.App;

/// <summary>Top bar across the window (macOS TopBar). The address field is centred on the window wherever the tabs
/// are and narrows before it moves; controls come from the toolbar layout at each edge and next to the field.
/// The caption buttons take the right edge on Windows, so that side reserves their width. With the tabs above the
/// address (TabsAbove) the bar is the second row, under the tab strip, and reserves nothing.</summary>
public sealed partial class TopBar : Grid
{
    readonly BrowserModel browser;
    Store Store => browser.Store;
    readonly StackPanel leadingEdge = new() { Orientation = Orientation.Horizontal, Spacing = 2, HorizontalAlignment = HorizontalAlignment.Left, VerticalAlignment = VerticalAlignment.Center };
    readonly StackPanel trailingEdge = new() { Orientation = Orientation.Horizontal, Spacing = 2, HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Center };
    readonly StackPanel leadingInner = new() { Orientation = Orientation.Horizontal, Spacing = 2, HorizontalAlignment = HorizontalAlignment.Left, VerticalAlignment = VerticalAlignment.Center };
    readonly StackPanel trailingInner = new() { Orientation = Orientation.Horizontal, Spacing = 2, HorizontalAlignment = HorizontalAlignment.Left, VerticalAlignment = VerticalAlignment.Center };
    readonly Grid addressHost = new() { VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Left };
    readonly Grid editingZones = new();
    readonly IconButton menuButton;
    AddressPill? pill;
    Guid? pillTab;
    string signature = "";
    const double Gap = Space.Small;

    public TopBar(BrowserModel browser)
    {
        this.browser = browser;
        Height = BrowserWindow.Bar;
        Background = Palette.Clear;
        menuButton = new IconButton("ellipsis", browser.Text("меню mica", "Меню mica"));
        menuButton.Click += () => MicaMenu.ShowBelow(AppMenu.Entries(browser), menuButton);
        browser.MenuRequested += () => MicaMenu.ShowBelow(AppMenu.Entries(browser), menuButton);
        Children.Add(leadingEdge); Children.Add(trailingEdge); Children.Add(leadingInner); Children.Add(trailingInner); Children.Add(addressHost); Children.Add(editingZones);
        this.ContextMenu(() => browser.CustomizingToolbar ? [] : [MenuEntry.Item(browser.Text("настроить панель инструментов…", "Настроить панель инструментов…"), () => browser.CustomizingToolbar = true, "slider.horizontal.3"), MenuEntry.Separator, .. LayoutMenu.Entries(Store)]);
    }

    public IEnumerable<FrameworkElement> Interactive()
    {
        foreach (var panel in new[] { leadingEdge, trailingEdge, leadingInner, trailingInner })
            foreach (var child in panel.Children.OfType<FrameworkElement>()) yield return child;
        if (pill is not null) yield return pill;
        foreach (var child in editingZones.Children.OfType<FrameworkElement>()) yield return child;
    }

    static double Span(IReadOnlyCollection<ToolbarControl> list, int extras) => (list.Count + (list.Contains(ToolbarControl.Extensions) ? extras : 0)) * Chrome.Item;

    public void Render(TabLayout layout, double windowWidth)
    {
        if (windowWidth <= 0) return;
        var toolbar = browser.Prefs.Toolbar;
        var items = toolbar.Resolve(sidebarAvailable: !layout.IsHorizontal());
        var edge = layout.SidebarEdge();
        var editing = browser.CustomizingToolbar;
        var extras = editing ? 0 : Store.Extensions.Actionable(browser.PrivateMode).Count;
        var badge = browser.PrivateMode && !editing ? Chrome.Item : 0;
        var leadingInset = Space.Small;
        // With the tabs above the address the bar is the second row, clear of the caption buttons.
        var captionInset = browser.FullScreen || layout == TabLayout.TabsAbove ? 0 : Chrome.CaptionInset;
        var menu = Chrome.Item;
        var inner = editing ? Math.Max(44, Math.Max(Span(items.LeadingInner, 0), Span(items.TrailingInner, 0)) + 4) : Math.Max(Span(items.LeadingInner, extras), Span(items.TrailingInner, extras));
        var innerRoom = inner > 0 || editing ? inner + Gap : 0;
        var edgeLeading = editing ? Math.Max(48, Span(items.Leading, 0) + 4 + Chrome.Item) : Span(items.Leading, extras);
        var edgeTrailing = editing ? Math.Max(48, Span(items.Trailing, 0) + 4 + Chrome.Item) : Span(items.Trailing, extras) + badge;
        var leading = leadingInset + edgeLeading + Gap + innerRoom;
        var trailing = captionInset + menu + edgeTrailing + Gap + innerRoom;
        var room = windowWidth - 2 * Math.Max(leading, trailing);
        var width = Math.Max(0, Math.Min(toolbar.AddressWidth, room));
        var centred = width >= 200 || editing;

        var key = string.Join(",", items.Leading) + "|" + string.Join(",", items.LeadingInner) + "|" + string.Join(",", items.TrailingInner) + "|" + string.Join(",", items.Trailing) + $"|{edge}|{editing}|{centred}|{extras}|{browser.PrivateMode}";
        if (key != signature)
        {
            signature = key;
            Fill(leadingEdge, editing ? [] : items.Leading.Concat(centred ? [] : items.LeadingInner), edge);
            Fill(trailingEdge, editing ? [] : (centred ? items.Trailing : items.TrailingInner.Concat(items.Trailing)), edge);
            if (!editing && browser.PrivateMode) trailingEdge.Children.Add(new Glyph(Glyph.Incognito, 13, Palette.Text2.Brush()) { Width = 28, Height = 28 }.Tip(browser.Text("окно инкогнито", "Окно инкогнито")));
            if (!editing) trailingEdge.Children.Add(menuButton);
            Fill(leadingInner, editing || !centred ? [] : items.LeadingInner, edge);
            Fill(trailingInner, editing || !centred ? [] : items.TrailingInner, edge);
            editingZones.Children.Clear();
            if (editing) BuildZones(items, layout);
        }
        leadingEdge.Margin = new Thickness(leadingInset, 0, 0, 0);
        trailingEdge.Margin = new Thickness(0, 0, captionInset + Space.Small, 0);
        if (editing)
        {
            var half = windowWidth / 2 - width / 2 - Gap - inner - Gap;
            if (editingZones.Children.Count == 4)
            {
                Place(editingZones.Children[0], leadingInset, Math.Max(0, half - leadingInset));
                Place(editingZones.Children[1], leadingInset + Math.Max(0, half - leadingInset) + Gap, inner);
                Place(editingZones.Children[2], windowWidth / 2 + width / 2 + Gap, inner);
                Place(editingZones.Children[3], windowWidth / 2 + width / 2 + Gap + inner + Gap, Math.Max(0, windowWidth - (windowWidth / 2 + width / 2 + 2 * Gap + inner) - captionInset - Space.Small));
            }
        }
        // The field and the inner groups.
        var tab = browser.Selected;
        if (tab is not null && (pill is null || pillTab != tab.Id))
        {
            addressHost.Children.Clear();
            pill = new AddressPill(tab, browser);
            pillTab = tab.Id;
            addressHost.Children.Add(pill);
        }
        if (pill is not null) { pill.IsHitTestVisible = !editing; pill.Opacity = editing ? 0.55 : 1; }
        if (centred)
        {
            addressHost.Width = width;
            addressHost.Margin = new Thickness(windowWidth / 2 - width / 2, 0, 0, 0);
            leadingInner.Margin = new Thickness(windowWidth / 2 - width / 2 - Gap - Span(items.LeadingInner, extras), 0, 0, 0);
            trailingInner.Margin = new Thickness(windowWidth / 2 + width / 2 + Gap, 0, 0, 0);
        }
        else
        {
            var flowLeading = leadingInset + Span(items.Leading, extras) + Span(items.LeadingInner, extras);
            var flowTrailing = captionInset + menu + Space.Small + Span(items.Trailing, extras) + Span(items.TrailingInner, extras) + badge;
            addressHost.Width = Math.Max(0, windowWidth - flowLeading - flowTrailing - 2 * Gap);
            addressHost.Margin = new Thickness(flowLeading + Gap, 0, 0, 0);
        }
    }

    static void Place(UIElement element, double x, double width)
    {
        var fe = (FrameworkElement)element;
        fe.HorizontalAlignment = HorizontalAlignment.Left;
        fe.Margin = new Thickness(x, 0, 0, 0);
        fe.Width = Math.Max(0, width);
    }

    void Fill(StackPanel panel, IEnumerable<ToolbarControl> controls, TabLayout? edge)
    {
        panel.Children.Clear();
        foreach (var item in controls)
            foreach (var element in ToolbarButton.Make(item, browser, edge, inSidebar: false))
            {
                panel.Children.Add(element);
                Motion.Appear(element);
            }
    }

    void BuildZones(ToolbarLayout.Resolved items, TabLayout layout)
    {
        editingZones.Children.Add(new ToolbarDropZone(ToolbarZone.Leading, items.Leading, browser, layout, HorizontalAlignment.Left) { MinWidth = 0, VerticalAlignment = VerticalAlignment.Center });
        editingZones.Children.Add(new ToolbarDropZone(ToolbarZone.LeadingInner, items.LeadingInner, browser, layout, HorizontalAlignment.Right) { MinWidth = 0, VerticalAlignment = VerticalAlignment.Center });
        editingZones.Children.Add(new ToolbarDropZone(ToolbarZone.TrailingInner, items.TrailingInner, browser, layout, HorizontalAlignment.Left) { MinWidth = 0, VerticalAlignment = VerticalAlignment.Center });
        editingZones.Children.Add(new ToolbarDropZone(ToolbarZone.Trailing, items.Trailing, browser, layout, HorizontalAlignment.Right) { MinWidth = 0, VerticalAlignment = VerticalAlignment.Center });
    }
}

/// <summary>Where the tabs live, from any context menu of the shell.</summary>
public static class LayoutMenu
{
    public static IEnumerable<MenuEntry> Entries(Store store)
    {
        var current = store.ActivePrefs.Layout;
        void Choose(TabLayout layout) => store.Change(p => p.Layout = layout);
        return
        [
            MenuEntry.Item(store.Text("боковая панель слева", "Боковая панель слева"), () => Choose(TabLayout.Left), "sidebar.left", @checked: current == TabLayout.Left),
            MenuEntry.Item(store.Text("вкладки под адресом", "Вкладки под адресом"), () => Choose(TabLayout.Top), "rectangle.topthird.inset.filled", @checked: current == TabLayout.Top),
            MenuEntry.Item(store.Text("вкладки над адресом", "Вкладки над адресом"), () => Choose(TabLayout.TabsAbove), "macwindow", @checked: current == TabLayout.TabsAbove),
            MenuEntry.Item(store.Text("боковая панель справа", "Боковая панель справа"), () => Choose(TabLayout.Right), "sidebar.right", @checked: current == TabLayout.Right),
        ];
    }
}

/// <summary>The menu that stands in for the macOS menu bar: Windows has no app menu bar, so every command that lives
/// only in the macOS menus is here, with its Windows shortcut.</summary>
public static class AppMenu
{
    public static IEnumerable<MenuEntry> Entries(BrowserModel b)
    {
        var s = b.Store;
        string? K(string command) => Keymap.Label(command);
        var tab = b.Selected;
        return
        [
            MenuEntry.Item(s.Text("новая вкладка", "Новая вкладка"), () => Commands.Run(b, "tab"), "plus", shortcut: K("tab")),
            MenuEntry.Item(s.Text("новое окно", "Новое окно"), () => Commands.Run(b, "newWindow"), "macwindow", shortcut: K("newWindow")),
            MenuEntry.Item(s.Text("новое окно инкогнито", "Новое окно инкогнито"), () => Commands.Run(b, "private"), Glyph.Incognito, shortcut: K("private")),
            MenuEntry.Item(s.Text("восстановить вкладку", "Восстановить вкладку"), () => Commands.Run(b, "reopen"), "arrow.counterclockwise", enabled: b.Closed.Count > 0, shortcut: K("reopen")),
            MenuEntry.Separator,
            MenuEntry.Item(s.Text("история", "История"), () => Commands.Run(b, "history"), "clock", shortcut: K("history")),
            MenuEntry.Item(s.Text("закладки", "Закладки"), () => b.Panel = b.Panel == LibraryPanel.Bookmarks ? null : LibraryPanel.Bookmarks, "bookmark"),
            MenuEntry.Item(s.Text("загрузки", "Загрузки"), () => Commands.Run(b, "downloads"), "arrow.down.circle", shortcut: K("downloads")),
            MenuEntry.Item(s.Text("расширения", "Расширения"), () => Commands.Run(b, "extensions"), "puzzlepiece.extension", shortcut: K("extensions")),
            MenuEntry.Item(s.Text("очистить историю…", "Очистить историю…"), () => Commands.Run(b, "clearData"), "trash", shortcut: K("clearData")),
            MenuEntry.Separator,
            MenuEntry.Item(s.Text("найти на странице", "Найти на странице"), () => Commands.Run(b, "find"), "text.magnifyingglass", enabled: tab?.Core is not null, shortcut: K("find")),
            MenuEntry.Item(s.Text("печать…", "Печать…"), () => Commands.Run(b, "print"), "printer", enabled: tab?.Core is not null, shortcut: K("print")),
            MenuEntry.Item(s.Text("увеличить", "Увеличить"), () => Commands.Run(b, "zoomIn"), "plus", enabled: tab?.Core is not null, shortcut: K("zoomIn")),
            MenuEntry.Item(s.Text("уменьшить", "Уменьшить"), () => Commands.Run(b, "zoomOut"), "minus", enabled: tab?.Core is not null, shortcut: K("zoomOut")),
            MenuEntry.Item(s.Text("исходный масштаб", "Исходный масштаб") + (tab is { Zoom: not 1 } ? $" ({Math.Round(tab.Zoom * 100)}%)" : ""), () => Commands.Run(b, "zoomReset"), null, enabled: tab is { Zoom: not 1 }, shortcut: K("zoomReset")),
            MenuEntry.Item(s.Text("полноэкранный режим", "Полноэкранный режим"), () => Commands.Run(b, "fullscreen"), "arrow.up.left.and.arrow.down.right", shortcut: K("fullscreen")),
            MenuEntry.Separator,
            .. ProfileMenu.OpenEntries(s),
            MenuEntry.Item(s.Text("настроить профили…", "Настроить профили…"), () => ProfileMenu.Edit(b, b.ProfileId), "person.crop.circle"),
            MenuEntry.Separator,
            MenuEntry.Item(s.Text("настроить панель инструментов…", "Настроить панель инструментов…"), () => b.CustomizingToolbar = true, "slider.horizontal.3"),
            .. LayoutMenu.Entries(s),
            MenuEntry.Separator,
            MenuEntry.Item(s.Text("настройки…", "Настройки…"), () => Commands.Run(b, "settings"), "gearshape", shortcut: K("settings")),
            MenuEntry.Item(s.Text("о mica", "О mica"), () => { b.SettingsSection = Mica.App.Settings.SettingsSection.About; b.ShowSettings = true; }, "info.circle"),
            MenuEntry.Item(s.Text("завершить mica", "Завершить mica"), () => Commands.Run(b, "quit"), null, shortcut: K("quit")),
        ];
    }
}
