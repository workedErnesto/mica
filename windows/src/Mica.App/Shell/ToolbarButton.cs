using Microsoft.UI.Xaml;
using Mica.Core;
using Mica.App.Downloads;
using Mica.Design;

namespace Mica.App;

public static class ToolbarControls
{
    public static string Symbol(this ToolbarControl item) => item switch
    {
        ToolbarControl.Sidebar => "sidebar.left", ToolbarControl.Back => "chevron.left", ToolbarControl.Forward => "chevron.right",
        ToolbarControl.Reload => "arrow.clockwise", ToolbarControl.NewTab => "plus", ToolbarControl.Bookmarks => "bookmark",
        ToolbarControl.History => "clock", ToolbarControl.Downloads => "arrow.down.circle", ToolbarControl.Extensions => "puzzlepiece.extension",
        ToolbarControl.Incognito => Glyph.Incognito, ToolbarControl.Profile => "person.crop.circle", ToolbarControl.Save => "square.and.arrow.down", _ => "gearshape",
    };

    public static string Title(this ToolbarControl item, Store s) => item switch
    {
        ToolbarControl.Sidebar => s.Text("боковая панель", "Боковая панель"), ToolbarControl.Back => s.Text("назад", "Назад"),
        ToolbarControl.Forward => s.Text("вперёд", "Вперёд"), ToolbarControl.Reload => s.Text("перезагрузить", "Перезагрузить"),
        ToolbarControl.NewTab => s.Text("новая вкладка", "Новая вкладка"), ToolbarControl.Bookmarks => s.Text("закладки", "Закладки"),
        ToolbarControl.History => s.Text("история", "История"), ToolbarControl.Downloads => s.Text("загрузки", "Загрузки"),
        ToolbarControl.Extensions => s.Text("расширения", "Расширения"), ToolbarControl.Incognito => s.Text("окно инкогнито", "Окно инкогнито"),
        ToolbarControl.Profile => s.Text("профиль", "Профиль"), ToolbarControl.Save => s.Text("сохранить страницу", "Сохранить страницу"),
        _ => s.Text("настройки", "Настройки"),
    };

    public static LibraryPanel? PanelOf(this ToolbarControl item) => item switch
    {
        ToolbarControl.Bookmarks => LibraryPanel.Bookmarks, ToolbarControl.History => LibraryPanel.History, ToolbarControl.Downloads => LibraryPanel.Downloads, ToolbarControl.Extensions => LibraryPanel.Extensions, _ => null,
    };

    public static string Title(this ToolbarZone zone, Store s) => zone switch
    {
        ToolbarZone.Leading => s.Text("у левого края", "У левого края"), ToolbarZone.LeadingInner => s.Text("слева от адреса", "Слева от адреса"),
        ToolbarZone.TrailingInner => s.Text("справа от адреса", "Справа от адреса"), ToolbarZone.Trailing => s.Text("у правого края", "У правого края"),
        ToolbarZone.Sidebar => s.Text("в боковой панели", "В боковой панели"), _ => s.Text("не показывается", "Не показывается"),
    };
}

/// <summary>One configurable control; the same item works in the top bar, the sidebar footer and the rail.</summary>
public static class ToolbarButton
{
    static string Shortcut(string command) => Keymap.Label(command) is { } k ? " " + k : "";

    public static IEnumerable<FrameworkElement> Make(ToolbarControl item, BrowserModel browser, TabLayout? edge, bool inSidebar)
    {
        var store = browser.Store;
        switch (item)
        {
            case ToolbarControl.Sidebar:
            {
                var button = new IconButton(edge == TabLayout.Right ? "sidebar.right" : "sidebar.left", "");
                void Label() => button.SetLabel((browser.Prefs.SidebarCollapsed ? browser.Text("развернуть боковую панель", "Развернуть боковую панель") : browser.Text("свернуть боковую панель", "Свернуть боковую панель")) + Shortcut("sidebar"));
                Label();
                button.Click += () => browser.Change(p => p.SidebarCollapsed = !p.SidebarCollapsed);
                button.Bind(h => store.PreferencesUpdated += h, h => store.PreferencesUpdated -= h, Label);
                yield return button; yield break;
            }
            case ToolbarControl.Back:
            case ToolbarControl.Forward:
            {
                var forward = item == ToolbarControl.Forward;
                var button = new IconButton(item.Symbol(), item.Title(store) + Shortcut(forward ? "forward" : "back"));
                button.Click += () => { if (forward) browser.Selected?.GoForward(); else browser.Selected?.GoBack(); };
                Track(button, browser, tab => button.IsEnabled = tab is not null && (forward ? tab.CanForward : tab.CanBack));
                yield return button; yield break;
            }
            case ToolbarControl.Reload:
            {
                var button = new IconButton("arrow.clockwise", item.Title(store));
                button.Click += () => { if (browser.Selected is { Loading: true } t) t.Stop(); else browser.Selected?.Reload(); };
                Track(button, browser, tab =>
                {
                    button.IsEnabled = tab?.Url is not null;
                    button.Symbol = tab?.Loading == true ? "xmark" : "arrow.clockwise";
                    button.SetLabel(tab?.Loading == true ? browser.Text("остановить", "Остановить") : browser.Text("перезагрузить", "Перезагрузить") + Shortcut("reload"));
                });
                yield return button; yield break;
            }
            case ToolbarControl.NewTab:
            {
                var button = new IconButton("plus", item.Title(store) + Shortcut("tab"));
                button.Click += () => { browser.Add(); browser.FocusAddress(); };
                yield return button; yield break;
            }
            case ToolbarControl.Extensions:
            {
                var button = new IconButton(item.Symbol(), item.Title(store) + Shortcut("extensions"), selected: browser.Panel == LibraryPanel.Extensions);
                button.Click += () => browser.Panel = browser.Panel == LibraryPanel.Extensions ? null : LibraryPanel.Extensions;
                button.Bind(browser, () => button.Selected = browser.Panel == LibraryPanel.Extensions);
                // In the top bar the extension buttons sit next to the puzzle; in the sidebar they get their own row.
                if (!inSidebar) foreach (var action in Extensions.ExtensionButtons.Make(browser)) yield return action;
                yield return button; yield break;
            }
            case ToolbarControl.Incognito:
            {
                var button = new IconButton(item.Symbol(), browser.Text("новое окно инкогнито", "Новое окно инкогнито") + Shortcut("private"));
                button.Click += () => store.NewWindow(privateMode: true);
                yield return button; yield break;
            }
            case ToolbarControl.Profile:
            {
                yield return new ProfileButton(browser); yield break;
            }
            case ToolbarControl.Save:
            {
                yield return new SavePageButton(browser, item.Title(store) + Shortcut("save")); yield break;
            }
            case ToolbarControl.Settings:
            {
                var button = new IconButton(item.Symbol(), item.Title(store) + Shortcut("settings"));
                button.Click += () => browser.ShowSettings = true;
                yield return button; yield break;
            }
            default:
            {
                var panel = item.PanelOf()!.Value;
                var command = panel == LibraryPanel.History ? "history" : panel == LibraryPanel.Downloads ? "downloads" : "";
                var button = new IconButton(item.Symbol(), item.Title(store) + (command.Length > 0 ? Shortcut(command) : ""), selected: browser.Panel == panel);
                button.Click += () => browser.Panel = browser.Panel == panel ? null : panel;
                button.Bind(browser, () => button.Selected = browser.Panel == panel);
                yield return button; yield break;
            }
        }
    }

    /// <summary>Follows the selected tab, re-subscribing when the selection changes.</summary>
    static void Track(FrameworkElement element, BrowserModel browser, Action<Tab?> render)
    {
        Tab? current = null;
        void TabChanged() => render(current);
        void Selection()
        {
            if (current != browser.Selected)
            {
                if (current is not null) current.Changed -= TabChanged;
                current = browser.Selected;
                if (current is not null) current.Changed += TabChanged;
            }
            render(current);
        }
        element.Loaded += (_, _) => { browser.Changed += Selection; Selection(); };
        element.Unloaded += (_, _) => { browser.Changed -= Selection; if (current is not null) current.Changed -= TabChanged; current = null; };
    }
}

/// <summary>Saves the page of the selected tab (macOS SavePageButton): mica's format menu under the button, Ctrl+S opens
/// the same menu. While a page of this tab is being written the button shows its progress in place of the glyph.</summary>
public sealed partial class SavePageButton : Microsoft.UI.Xaml.Controls.Grid
{
    readonly BrowserModel browser;
    readonly IconButton button;
    readonly ProgressRing ring = new(16) { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
    public SavePageButton(BrowserModel browser, string label)
    {
        this.browser = browser;
        Width = Chrome.Item; Height = Chrome.Item;
        button = new IconButton(ToolbarControl.Save.Symbol(), label);
        button.Click += Open;
        ring.Opacity = 0;
        Children.Add(button); Children.Add(ring);
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(ring, browser.Text("сохраняется", "Сохраняется"));
        this.Bind(browser, Render);
        this.Bind(browser.Downloads, Render);
        this.Bind(h => browser.SaveMenuRequested += h, h => browser.SaveMenuRequested -= h, Open);
    }
    void Open() { if (browser.Selected is { } tab && PageSaver.CanSave(tab)) MicaMenu.ShowBelow(PageSaver.Entries(tab, browser), button); }
    void Render()
    {
        var tab = browser.Selected;
        var current = browser.Downloads.Items.FirstOrDefault(i => i.Saving && i.State == DownloadState.Running && i.Page == tab);
        button.IsEnabled = PageSaver.CanSave(tab);
        if (current is not null) ring.SetProgress(current.Fraction);
        Motion.Fade(ring, current is null ? 0 : 1);
        Motion.Fade(button, current is null ? 1 : 0);
        button.IsHitTestVisible = current is null;
    }
}
