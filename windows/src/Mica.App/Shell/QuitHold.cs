using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;
using Microsoft.UI.Xaml.Shapes;
using Mica.Core;
using Mica.Design;
using Windows.Foundation;
using Windows.System;

namespace Mica.App;

/// <summary>The quit shortcut (Ctrl+Shift+Q) quits only after being held for <see cref="Duration"/> seconds, so a
/// stray press does not close every window (macOS QuitHold, ⌘Q). The keyboard accelerator starts the hold; the
/// physical keys are then polled, because key-up events do not reach XAML while the page has focus. Releasing any
/// key of the shortcut or switching to another window cancels. The "…" menu item still quits at once.</summary>
public static class QuitHold
{
    public const double Duration = 2;
    static BrowserModel? holding;
    static Shortcut? shortcut;
    static VirtualKey key;
    static DateTime start;
    static Microsoft.UI.Dispatching.DispatcherQueueTimer? poll;
    static bool quitting;
    static event Action? Changed;

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
        Changed?.Invoke();
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
        if (holding is null) return;
        holding = null;
        Changed?.Invoke();
    }

    /// <summary>The existing quit path, which still asks about running downloads.</summary>
    static async Task Finish(BrowserModel browser)
    {
        quitting = true;
        try { await Commands.Quit(browser.Store); }
        finally { quitting = false; }
    }

    /// <summary>Shows the badge over <paramref name="host"/> while this window holds the shortcut. Subscribed only
    /// while loaded, so a closed window is not kept alive by the static event.</summary>
    public static void Attach(Panel host, BrowserModel browser)
    {
        QuitHoldBadge? badge = null;
        void Update()
        {
            var shown = holding == browser;
            if (shown && badge is null)
            {
                badge = new QuitHoldBadge(browser, (DateTime.UtcNow - start).TotalSeconds);
                host.Children.Add(badge);
                Motion.Appear(badge);
            }
            else if (!shown && badge is { } old)
            {
                badge = null;
                // Disappears by fading only; the hold ended, nothing moves.
                Motion.Fade(old, 0, TimeSpan.FromSeconds(0.14));
                var timer = host.DispatcherQueue.CreateTimer();
                timer.Interval = TimeSpan.FromMilliseconds(150);
                timer.IsRepeating = false;
                timer.Tick += (_, _) => host.Children.Remove(old);
                timer.Start();
            }
        }
        host.Loaded += (_, _) => { Changed -= Update; Changed += Update; };
        host.Unloaded += (_, _) => Changed -= Update;
    }
}

/// <summary>Raised badge whose outline is drawn from the top centre clockwise over the hold time, as progress.
/// The countdown keeps running with animation effects off: it is a progress indicator, not decoration.</summary>
sealed partial class QuitHoldBadge : Grid
{
    const double Line = 2;
    readonly Microsoft.UI.Xaml.Shapes.Path outline;
    readonly DateTime shownAt = DateTime.UtcNow;
    readonly double elapsedAtStart;
    Storyboard? drawing;

    public QuitHoldBadge(BrowserModel browser, double elapsed)
    {
        elapsedAtStart = elapsed;
        HorizontalAlignment = HorizontalAlignment.Center; VerticalAlignment = VerticalAlignment.Center;
        IsHitTestVisible = false;
        var title = Ui.Text(browser.Text("закрытие mica", "Закрытие mica"), 13, Palette.Ink.Brush(), Ui.Medium);
        var row = Ui.H(Space.Small, title, KeyHint.Make(Keymap.Label("quit") ?? "Ctrl+Shift+Q"));
        row.VerticalAlignment = VerticalAlignment.Center;
        row.Margin = new Thickness(16, 0, 16, 0);
        var surface = Ui.Raised(row);
        surface.Height = 44;
        Children.Add(surface);
        outline = new Microsoft.UI.Xaml.Shapes.Path
        {
            Stroke = Look.Accent is { } accent ? new SolidColorBrush(accent) : Palette.Ink.Brush(),
            StrokeThickness = Line, StrokeStartLineCap = PenLineCap.Flat, StrokeEndLineCap = PenLineCap.Flat, StrokeDashCap = PenLineCap.Flat,
            IsHitTestVisible = false,
            // Same depth as the raised surface so the outline draws above it.
            Translation = surface.Translation,
        };
        Children.Add(outline);
        var announcement = browser.Text("закрытие mica: отпустите клавиши, чтобы отменить", "Закрытие mica: отпустите клавиши, чтобы отменить");
        AutomationProperties.SetName(this, announcement);
        AutomationProperties.SetLiveSetting(this, AutomationLiveSetting.Assertive);
        SizeChanged += (_, e) => Draw(e.NewSize);
        Loaded += (_, _) =>
        {
            var peer = FrameworkElementAutomationPeer.FromElement(this) ?? FrameworkElementAutomationPeer.CreatePeerForElement(this);
            peer?.RaiseNotificationEvent(AutomationNotificationKind.Other, AutomationNotificationProcessing.ImportantMostRecent, announcement, "mica.quitHold");
        };
    }

    /// <summary>Rounded-rectangle outline inside the 1 px border, starting at the top centre and running clockwise.
    /// A dash as long as the outline is revealed by animating the dash offset from its length to zero.</summary>
    void Draw(Size size)
    {
        double w = size.Width, h = size.Height, inset = Line / 2;
        if (w <= 2 * Line || h <= 2 * Line) return;
        double x0 = inset, y0 = inset, x1 = w - inset, y1 = h - inset;
        var r = Math.Min(Radius.Panel - inset, Math.Min(x1 - x0, y1 - y0) / 2);
        var figure = new PathFigure { StartPoint = new Point(w / 2, y0), IsClosed = false, IsFilled = false };
        void LineTo(double x, double y) => figure.Segments.Add(new LineSegment { Point = new Point(x, y) });
        void ArcTo(double x, double y) => figure.Segments.Add(new ArcSegment { Point = new Point(x, y), Size = new Size(r, r), SweepDirection = SweepDirection.Clockwise });
        LineTo(x1 - r, y0); ArcTo(x1, y0 + r);
        LineTo(x1, y1 - r); ArcTo(x1 - r, y1);
        LineTo(x0 + r, y1); ArcTo(x0, y1 - r);
        LineTo(x0, y0 + r); ArcTo(x0 + r, y0);
        LineTo(w / 2, y0);
        var geometry = new PathGeometry(); geometry.Figures.Add(figure);
        outline.Data = geometry;

        // Dash lengths are in multiples of the stroke thickness.
        var length = (2 * (x1 - x0 - 2 * r) + 2 * (y1 - y0 - 2 * r) + 2 * Math.PI * r) / Line;
        outline.StrokeDashArray = new DoubleCollection { length, length + 1 };
        var elapsed = elapsedAtStart + (DateTime.UtcNow - shownAt).TotalSeconds;
        var progress = Math.Clamp(elapsed / QuitHold.Duration, 0, 1);
        var remaining = Math.Max(0, QuitHold.Duration - elapsed);
        drawing?.Stop();
        outline.StrokeDashOffset = length * (1 - progress);
        if (remaining <= 0) { outline.StrokeDashOffset = 0; return; }
        var animation = new DoubleAnimation { From = length * (1 - progress), To = 0, Duration = TimeSpan.FromSeconds(remaining), EnableDependentAnimation = true };
        Storyboard.SetTarget(animation, outline);
        Storyboard.SetTargetProperty(animation, "StrokeDashOffset");
        drawing = new Storyboard();
        drawing.Children.Add(animation);
        drawing.Begin();
    }
}

public static partial class Win32
{
    [System.Runtime.InteropServices.LibraryImport("user32.dll")] private static partial short GetAsyncKeyState(int key);
    /// <summary>Whether a virtual key is physically down right now.</summary>
    public static bool IsDown(int virtualKey) => (GetAsyncKeyState(virtualKey) & 0x8000) != 0;
}
