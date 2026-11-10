using System.Numerics;
using Microsoft.UI.Composition;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Hosting;

namespace Mica.Design;

/// <summary>Springs and fades for state changes. Actions happen at once; animations follow, are interruptible and
/// never block input. With "Animation effects" off in Windows settings (the Reduce Motion counterpart) spatial
/// motion is skipped and only opacity and colour change.</summary>
public static class Motion
{
    static readonly Windows.UI.ViewManagement.UISettings Settings = new();
    public static bool Reduced => !Settings.AnimationsEnabled;
    public static Spring Press => MotionTokens.Press;
    public static Spring Snappy => MotionTokens.Snappy;
    public static Spring Panel => MotionTokens.Panel;
    public static readonly TimeSpan Hover = TimeSpan.FromSeconds(MotionTokens.HoverDuration);

    static Visual Visual(UIElement element) => ElementCompositionPreview.GetElementVisual(element);

    static SpringScalarNaturalMotionAnimation ScalarSpring(Compositor c, Spring s, float target)
    {
        var a = c.CreateSpringScalarAnimation();
        a.Period = TimeSpan.FromSeconds(s.Response);
        a.DampingRatio = (float)s.Damping;
        a.FinalValue = target;
        return a;
    }

    static SpringVector3NaturalMotionAnimation VectorSpring(Compositor c, Spring s, Vector3 target)
    {
        var a = c.CreateSpringVector3Animation();
        a.Period = TimeSpan.FromSeconds(s.Response);
        a.DampingRatio = (float)s.Damping;
        a.FinalValue = target;
        return a;
    }

    /// <summary>Scale around the element centre, as SwiftUI scaleEffect does.</summary>
    public static void Scale(UIElement element, double scale, Spring spring)
    {
        var visual = Visual(element);
        if (element is FrameworkElement fe) visual.CenterPoint = new Vector3((float)fe.ActualWidth / 2, (float)fe.ActualHeight / 2, 0);
        var target = new Vector3((float)scale, (float)scale, 1);
        if (Reduced) { visual.StopAnimation("Scale"); visual.Scale = Vector3.One; return; }
        visual.StartAnimation("Scale", VectorSpring(visual.Compositor, spring, target));
    }

    /// <summary>Moves by a translation that layout does not see (matched geometry, slides, knob travel).</summary>
    public static void Translate(UIElement element, Vector3 offset, Spring spring, bool animated = true)
    {
        ElementCompositionPreview.SetIsTranslationEnabled(element, true);
        var visual = Visual(element);
        if (Reduced || !animated) { visual.StopAnimation("Translation"); visual.Properties.InsertVector3("Translation", offset); return; }
        visual.StartAnimation("Translation", VectorSpring(visual.Compositor, spring, offset));
    }

    /// <summary>Horizontal fill from the leading edge (progress bars): scale X around the left edge with a spring.</summary>
    public static void Stretch(UIElement element, double fraction, Spring spring)
    {
        var visual = Visual(element);
        visual.CenterPoint = Vector3.Zero;
        var target = new Vector3((float)Math.Clamp(fraction, 0, 1), 1, 1);
        if (Reduced) { visual.StopAnimation("Scale"); visual.Scale = target; return; }
        visual.StartAnimation("Scale", VectorSpring(visual.Compositor, spring, target));
    }

    public static void Fade(UIElement element, double opacity, TimeSpan? duration = null)
    {
        var visual = Visual(element);
        var time = duration ?? Hover;
        if (time <= TimeSpan.Zero) { visual.StopAnimation("Opacity"); visual.Opacity = (float)opacity; return; }
        var animation = visual.Compositor.CreateScalarKeyFrameAnimation();
        animation.InsertKeyFrame(1, (float)opacity);
        animation.Duration = time;
        visual.StartAnimation("Opacity", animation);
    }

    /// <summary>Layout moves (reordered tabs, panels opening beside) animate from the old position with a spring.</summary>
    public static void AnimateLayoutMoves(UIElement element, Spring spring)
    {
        var visual = Visual(element);
        var c = visual.Compositor;
        var offset = c.CreateSpringVector3Animation();
        offset.Target = "Offset";
        offset.FinalValue = default;
        offset.Period = TimeSpan.FromSeconds(spring.Response);
        offset.DampingRatio = (float)spring.Damping;
        offset.InitialValueExpressions["FinalValue"] = "this.FinalValue";
        var collection = c.CreateImplicitAnimationCollection();
        collection["Offset"] = offset;
        visual.ImplicitAnimations = Reduced ? null : collection;
    }

    public enum Edge { None, Leading, Trailing, Top, Bottom }

    /// <summary>Appearance: a pop (scale 0.96 and fade) or a short slide from an edge with fade.</summary>
    public static void Appear(UIElement element, Edge edge = Edge.None, Spring? spring = null)
    {
        var s = spring ?? Snappy;
        var visual = Visual(element);
        visual.Opacity = 0;
        if (!Reduced)
        {
            if (edge == Edge.None)
            {
                if (element is FrameworkElement fe) fe.SizeChanged += Center;
                visual.Scale = new Vector3((float)MotionTokens.PopScale, (float)MotionTokens.PopScale, 1);
                visual.StartAnimation("Scale", VectorSpring(visual.Compositor, s, Vector3.One));
            }
            else
            {
                var from = edge switch { Edge.Leading => new Vector3(-24, 0, 0), Edge.Trailing => new Vector3(24, 0, 0), Edge.Top => new Vector3(0, -12, 0), _ => new Vector3(0, 12, 0) };
                Translate(element, from, s, animated: false);
                element.DispatcherQueue.TryEnqueue(() => Translate(element, Vector3.Zero, s));
            }
        }
        element.DispatcherQueue.TryEnqueue(() => Fade(element, 1, TimeSpan.FromSeconds(Reduced ? 0.12 : 0.18)));
        static void Center(object sender, SizeChangedEventArgs e) { var fe = (FrameworkElement)sender; Visual(fe).CenterPoint = new Vector3((float)fe.ActualWidth / 2, (float)fe.ActualHeight / 2, 0); }
    }

    /// <summary>Window and start page entrance (macOS EntranceModifier, MotionTokens.Entrance): the element appears
    /// <paramref name="delay"/> seconds after the entrance begins, fading in and settling from the offset and scale with
    /// the spring. It takes input at once. With animation effects off it is only a short fade without delay. Do not use
    /// it on an element that sets the XAML Translation property (shadow depth): wrap that element instead.</summary>
    public static void Enter(UIElement element, double delay, double rise = MotionTokens.Entrance.Rise, double dx = 0, double scale = 1, Spring? spring = null, double fade = 0.24)
    {
        var visual = Visual(element);
        var c = visual.Compositor;
        var wait = TimeSpan.FromSeconds(Reduced ? 0 : delay);
        visual.Opacity = 0;
        var opacity = c.CreateScalarKeyFrameAnimation();
        opacity.InsertKeyFrame(0, 0);
        opacity.InsertKeyFrame(1, 1, c.CreateCubicBezierEasingFunction(new Vector2(0.2f, 0), new Vector2(0.2f, 1)));
        opacity.Duration = TimeSpan.FromSeconds(Reduced ? MotionTokens.Entrance.ReducedFade : fade);
        opacity.DelayTime = wait;
        opacity.DelayBehavior = AnimationDelayBehavior.SetInitialValueBeforeDelay;
        visual.StartAnimation("Opacity", opacity);
        if (Reduced) return;
        var s = spring ?? Panel;
        if (rise != 0 || dx != 0)
        {
            ElementCompositionPreview.SetIsTranslationEnabled(element, true);
            visual.Properties.InsertVector3("Translation", new Vector3((float)dx, (float)rise, 0));
            var move = VectorSpring(c, s, Vector3.Zero);
            move.DelayTime = wait;
            visual.StartAnimation("Translation", move);
        }
        if (scale != 1)
        {
            if (element is FrameworkElement fe)
            {
                visual.CenterPoint = new Vector3((float)fe.ActualWidth / 2, (float)fe.ActualHeight / 2, 0);
                fe.SizeChanged += (_, e) => visual.CenterPoint = new Vector3((float)e.NewSize.Width / 2, (float)e.NewSize.Height / 2, 0);
            }
            visual.Scale = new Vector3((float)scale, (float)scale, 1);
            var grow = VectorSpring(c, s, Vector3.One);
            grow.DelayTime = wait;
            visual.StartAnimation("Scale", grow);
        }
    }

    /// <summary>Disappearance, then <paramref name="done"/> removes the element. Input passes through at once.</summary>
    public static void Disappear(UIElement element, Action done, Edge edge = Edge.None)
    {
        element.IsHitTestVisible = false;
        Fade(element, 0, TimeSpan.FromSeconds(0.14));
        if (!Reduced)
        {
            if (edge == Edge.None) Scale(element, MotionTokens.PopScale, Snappy);
            else Translate(element, edge switch { Edge.Leading => new Vector3(-24, 0, 0), Edge.Trailing => new Vector3(24, 0, 0), Edge.Top => new Vector3(0, -12, 0), _ => new Vector3(0, 12, 0) }, Snappy);
        }
        var timer = element.DispatcherQueue.CreateTimer();
        timer.Interval = TimeSpan.FromMilliseconds(Reduced ? 120 : 170);
        timer.IsRepeating = false;
        timer.Tick += (_, _) => done();
        timer.Start();
    }
}
