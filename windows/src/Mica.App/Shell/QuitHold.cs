using Mica.Core;
using Windows.System;

namespace Mica.App;

/// <summary>The quit shortcut (Ctrl+Shift+Q) quits only after being held for <see cref="Duration"/> seconds, so a
/// stray press does not close every window (macOS QuitHold, ⌘Q). The shortcut starts the hold; the physical keys are
/// then polled, because key-up events do not reach the window while a page has focus. Releasing any key of the
/// shortcut or switching to another window cancels. While it is held the window's shell shows the plate whose outline
/// draws itself over the hold time. The "…" menu item still quits at once.</summary>
public static class QuitHold
{
    public const double Duration = 2;
    static BrowserModel? holding;
    static Shortcut? shortcut;
    static VirtualKey key;
    static DateTime start;
    static Microsoft.UI.Dispatching.DispatcherQueueTimer? poll;
    static bool quitting;

    public static void Begin(BrowserModel browser, Shortcut keys, VirtualKey virtualKey)
    {
        if (holding is not null || quitting) return;
        if (browser.Window is null || Microsoft.UI.Dispatching.DispatcherQueue.GetForCurrentThread() is not { } queue) { _ = Finish(browser); return; }
        holding = browser; shortcut = keys; key = virtualKey; start = DateTime.UtcNow;
        poll = queue.CreateTimer();
        poll.Interval = TimeSpan.FromMilliseconds(30);
        poll.IsRepeating = true;
        poll.Tick += (_, _) => Check();
        poll.Start();
        browser.QuitHolding = true;
    }

    static void Check()
    {
        if (holding is not { } browser || shortcut is not { } keys) { Stop(); return; }
        var held = Win32.IsDown((int)key) && (!keys.Ctrl || Win32.IsDown(0x11)) && (!keys.Shift || Win32.IsDown(0x10)) && (!keys.Alt || Win32.IsDown(0x12));
        if (!held || browser.Window?.IsKey != true) { Stop(); return; }
        if ((DateTime.UtcNow - start).TotalSeconds < Duration) return;
        Stop();
        _ = Finish(browser);
    }

    static void Stop()
    {
        poll?.Stop(); poll = null;
        if (holding is not { } browser) return;
        holding = null;
        browser.QuitHolding = false;
    }

    /// <summary>The existing quit path, which still asks about running downloads.</summary>
    static async Task Finish(BrowserModel browser)
    {
        quitting = true;
        try { await Commands.Quit(browser.Store); }
        finally { quitting = false; }
    }
}

public static partial class Win32
{
    [System.Runtime.InteropServices.LibraryImport("user32.dll")] private static partial short GetAsyncKeyState(int key);
    /// <summary>Whether a virtual key is physically down right now.</summary>
    public static bool IsDown(int virtualKey) => (GetAsyncKeyState(virtualKey) & 0x8000) != 0;
}
