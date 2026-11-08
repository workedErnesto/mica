using Microsoft.UI.Xaml;

namespace Mica.App;

/// <summary>Change notification for models (the role of ObservableObject on macOS). Views subscribe while loaded.</summary>
public abstract class Observable
{
    public event Action? Changed;
    protected void Notify() => Changed?.Invoke();
}

public static class Bindings
{
    /// <summary>Runs <paramref name="render"/> now and whenever the source changes, while the element is in the tree.</summary>
    public static void Bind(this FrameworkElement element, Action<Action> subscribe, Action<Action> unsubscribe, Action render)
    {
        var attached = false;
        void Attach() { if (attached) return; attached = true; subscribe(render); render(); }
        void Detach() { if (!attached) return; attached = false; unsubscribe(render); }
        element.Loaded += (_, _) => Attach();
        element.Unloaded += (_, _) => Detach();
        if (element.IsLoaded) Attach();
    }

    public static void Bind(this FrameworkElement element, Observable source, Action render) =>
        element.Bind(h => source.Changed += h, h => source.Changed -= h, render);
}
