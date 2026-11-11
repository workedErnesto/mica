using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Input;
using Mica.Core;
using Mica.Design;
using Windows.System;

namespace Mica.App;

/// <summary>Keyboard commands from shared/keymap.json (macOS AppDelegate menu key equivalents) and their actions.</summary>
public static class Commands
{
    public static void Install(UIElement root, BrowserModel browser)
    {
        foreach (var (command, shortcuts) in Keymap.Windows)
        {
            foreach (var shortcut in shortcuts)
            {
                if (shortcut.Key is "XButton1" or "XButton2") continue;
                if (Key(shortcut.Key) is not { } key) continue;
                var accelerator = new KeyboardAccelerator { Key = key, Modifiers = Modifiers(shortcut), ScopeOwner = null };
                // Quit waits for the shortcut to be held (QuitHold); the menu item calls Run and quits at once.
                accelerator.Invoked += (_, e) => { e.Handled = true; if (command == "quit") QuitHold.Begin(browser, shortcut, key); else Run(browser, command); };
                root.KeyboardAccelerators.Add(accelerator);
            }
        }
        // Mouse back and forward buttons, as in other Windows browsers.
        root.PointerPressed += (_, e) =>
        {
            var properties = e.GetCurrentPoint(root).Properties;
            if (properties.IsXButton1Pressed) { Run(browser, "back"); e.Handled = true; }
            else if (properties.IsXButton2Pressed) { Run(browser, "forward"); e.Handled = true; }
        };
    }

    static VirtualKeyModifiers Modifiers(Shortcut s) =>
        (s.Ctrl ? VirtualKeyModifiers.Control : 0) | (s.Shift ? VirtualKeyModifiers.Shift : 0) | (s.Alt ? VirtualKeyModifiers.Menu : 0) | (s.Win ? VirtualKeyModifiers.Windows : 0);

    static VirtualKey? Key(string name) => name switch
    {
        "=" => (VirtualKey)0xBB, "-" => (VirtualKey)0xBD, "," => (VirtualKey)0xBC, "[" => (VirtualKey)0xDB, "]" => (VirtualKey)0xDD,
        _ when name.Length == 1 && char.IsAsciiLetterOrDigit(name[0]) => (VirtualKey)char.ToUpperInvariant(name[0]),
        _ => Enum.TryParse<VirtualKey>(name, out var key) ? key : null,
    };

    public static void Run(BrowserModel browser, string command)
    {
        var store = browser.Store;
        var tab = browser.Selected;
        switch (command)
        {
            case "newWindow": store.NewWindow(); break;
            case "private": store.NewWindow(privateMode: true); break;
            case "customize": browser.ShowSettings = false; browser.CustomizingToolbar = true; break;
            case "tab": browser.Add(); browser.FocusAddress(); break;
            case "close": if (tab is not null) browser.Close(tab); break;
            case "reopen": browser.Reopen(); break;
            case "address": browser.FocusAddress(); break;
            case "reload": tab?.Reload(); break;
            case "reloadHard": tab?.ReloadFromOrigin(); break;
            case "back": tab?.GoBack(); break;
            case "forward": tab?.GoForward(); break;
            case "find": if (tab?.Core is not null) browser.ShowFind = !browser.ShowFind; break;
            case "findNext": browser.StepFind(back: false); break;
            case "findPrevious": browser.StepFind(back: true); break;
            case "sidebar": browser.Change(p => p.SidebarCollapsed = !p.SidebarCollapsed); break;
            case "bookmark": if (tab is not null) store.Bookmark(tab); break;
            case "history": browser.Panel = browser.Panel == LibraryPanel.History ? null : LibraryPanel.History; break;
            case "clearData": browser.ShowClearData = true; break;
            case "downloads": browser.Panel = browser.Panel == LibraryPanel.Downloads ? null : LibraryPanel.Downloads; break;
            case "extensions": browser.Panel = browser.Panel == LibraryPanel.Extensions ? null : LibraryPanel.Extensions; break;
            case "settings": browser.ShowSettings = true; break;
            case "next": browser.Cycle(1); break;
            case "previous": browser.Cycle(-1); break;
            case "zoomIn": browser.ZoomBy(0.1); break;
            case "zoomOut": browser.ZoomBy(-0.1); break;
            case "zoomReset": browser.ZoomBy(0); break;
            case "print": tab?.Print(); break;
            case "save":
                if (!PageSaver.CanSave(tab)) break;
                // The menu hangs from the save button; with the button hidden it opens under the address instead.
                if (browser.Prefs.Toolbar.ZoneOf(ToolbarControl.Save) != ToolbarZone.Hidden) browser.RequestSaveMenu();
                else if (browser.Window?.Content is FrameworkElement root) MicaMenu.ShowAt(PageSaver.Entries(tab!, browser), root, new Windows.Foundation.Point(root.ActualWidth / 2 - 90, Chrome.Bar));
                break;
            case "fullscreen": browser.Window?.ToggleFullScreen(); break;
            case "menu": browser.RequestMenu(); break;
            case "quit": _ = Quit(store); break;
            case "tabLast": if (browser.Tabs.Count > 0) browser.Select(browser.Tabs[^1]); break;
            default:
                if (command.StartsWith("tab", StringComparison.Ordinal) && int.TryParse(command[3..], out var index) && browser.Tabs.Count > 0)
                    browser.Select(browser.Tabs[Math.Min(index - 1, browser.Tabs.Count - 1)]);
                break;
        }
    }

    internal static async Task Quit(Store store)
    {
        var running = store.Windows.Any(w => w.Model.Downloads.Items.Any(d => d.State is DownloadState.Running or DownloadState.Choosing or DownloadState.Paused));
        if (running && await Dialogs.Ask(store.Active?.Window, store.Text("завершить mica и отменить загрузки?", "Завершить mica и отменить загрузки?"), store.Text("незавершённые загрузки будут отменены", "Незавершённые загрузки будут отменены"), [store.Text("отмена", "Отмена"), store.Text("завершить", "Завершить")]) != 1) return;
        store.Quit();
    }
}
