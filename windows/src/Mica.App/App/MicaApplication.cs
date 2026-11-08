using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Markup;
using Microsoft.UI.Xaml.XamlTypeInfo;
using Microsoft.Windows.AppLifecycle;
using Windows.ApplicationModel.Activation;
using Mica.Core;

namespace Mica.App;

/// <summary>The application object. UI is built in code; this provider supplies the WinUI control metadata the XAML
/// compiler would otherwise generate, and XamlControlsResources the default control styles.</summary>
public sealed partial class MicaApplication : Application, IXamlMetadataProvider
{
    public static new MicaApplication? Current { get; private set; }
    readonly XamlControlsXamlMetaDataProvider provider = new();
    public DispatcherQueue Dispatcher { get; }
    public Store Store { get; } = Store.Shared;
    // A redirected launch can arrive before this object exists or while StartAsync restores the session. Those links
    // wait here and open after the restored windows, so the session neither buries them nor gains a duplicate window.
    static readonly object gate = new();
    static readonly List<AppActivationArguments> early = [];
    readonly List<string> pending = [];
    bool started;

    public MicaApplication()
    {
        ResourceManagerRequested += (_, e) =>
        {
            var pri = Path.Combine(AppContext.BaseDirectory, "mica.pri");
            if (File.Exists(pri)) e.CustomResourceManager = new Microsoft.Windows.ApplicationModel.Resources.ResourceManager(pri);
        };
        Dispatcher = DispatcherQueue.GetForCurrentThread();
        lock (gate)
        {
            Current = this;
            foreach (var e in early) Dispatcher.TryEnqueue(() => Activate(e));
            early.Clear();
        }
        UnhandledException += (_, e) => { Diagnostics.Log.Error(e.Exception); e.Handled = Store.Shared.Windows.Count > 0; };
    }

    public IXamlType GetXamlType(Type type) => provider.GetXamlType(type);
    public IXamlType GetXamlType(string fullName) => provider.GetXamlType(fullName);
    public XmlnsDefinition[] GetXmlnsDefinitions() => provider.GetXmlnsDefinitions();

    protected override async void OnLaunched(Microsoft.UI.Xaml.LaunchActivatedEventArgs args)
    {
        Resources.MergedDictionaries.Add(new XamlControlsResources());
        Notifications.Notifier.Shared.Start();
        await Store.StartAsync();
        started = true;
        var links = LaunchUrls(Program.Arguments).Concat(pending).ToList();
        pending.Clear();
        if (links.Count > 0) OpenLinks(links);
        if (Program.QA) await Diagnostics.QA.RunAsync(Store);
    }

    /// <summary>Called by Program on the activation thread when a second launch hands over its arguments.</summary>
    public static void Redirected(AppActivationArguments e)
    {
        MicaApplication? app;
        lock (gate)
        {
            app = Current;
            if (app is null) { early.Add(e); return; }
        }
        app.Dispatcher.TryEnqueue(() => app.Activate(e));
    }

    /// <summary>A second launch or a protocol activation: open its links in a normal window.</summary>
    public void Activate(AppActivationArguments e)
    {
        var urls = new List<string>();
        if (e.Kind == ExtendedActivationKind.Launch && e.Data is ILaunchActivatedEventArgs launch) urls.AddRange(LaunchUrls(SplitArguments(launch.Arguments)));
        else if (e.Kind == ExtendedActivationKind.Protocol && e.Data is IProtocolActivatedEventArgs protocol) urls.Add(protocol.Uri.AbsoluteUri);
        else if (e.Kind == ExtendedActivationKind.File && e.Data is IFileActivatedEventArgs file) urls.AddRange(file.Files.Select(f => f.Path));
        else if (e.Kind == ExtendedActivationKind.AppNotification) { Notifications.Notifier.Shared.Activated(e); return; }
        var links = LaunchUrls(urls).ToList();
        if (!started) { pending.AddRange(links); return; }
        if (links.Count > 0) OpenLinks(links);
        else (Store.Active ?? Store.NewWindow()).Window?.Bring();
    }

    /// <summary>Links from other apps never land in a private window. A blank new tab takes the first link instead of
    /// staying behind it.</summary>
    void OpenLinks(IReadOnlyList<string> links)
    {
        var normal = Store.Windows.Where(w => !w.Model.PrivateMode).ToList();
        var browser = (normal.FirstOrDefault(w => w.IsKey) ?? normal.LastOrDefault())?.Model ?? Store.NewWindow();
        var rest = links.AsEnumerable();
        if (browser.Selected is { Url: null } blank) { if (AddressParser.OpenableFile(links[0])) blank.OpenFile(links[0]); else blank.Load(links[0]); rest = links.Skip(1); }
        foreach (var url in rest) browser.Open(url);
        browser.Window?.Bring();
    }

    public static IEnumerable<string> LaunchUrls(IEnumerable<string> arguments)
    {
        foreach (var argument in arguments)
        {
            if (argument.StartsWith("--", StringComparison.Ordinal)) continue;
            if (IsWebLink(argument)) { yield return argument; continue; }
            // Explorer passes a filesystem path, while file activation can supply a file URI.
            if (Uri.TryCreate(argument, UriKind.Absolute, out var uri) && uri.IsFile && AddressParser.OpenableFile(uri.AbsoluteUri))
                yield return uri.AbsoluteUri;
        }
    }

    /// <summary>Only http and https links from other apps; Navigable also rejects a missing host and credentials in the URL.</summary>
    static bool IsWebLink(string url) => AddressParser.Navigable(url) && url.StartsWith("http", StringComparison.OrdinalIgnoreCase);

    static string[] SplitArguments(string? text) => string.IsNullOrWhiteSpace(text) ? [] :
        System.Text.RegularExpressions.Regex.Matches(text, "\"([^\"]*)\"|(\\S+)").Select(m => m.Groups[1].Success ? m.Groups[1].Value : m.Groups[2].Value).ToArray();
}
