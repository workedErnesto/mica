using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Markup;
using Microsoft.UI.Xaml.XamlTypeInfo;
using Microsoft.Windows.AppLifecycle;
using Windows.ApplicationModel.Activation;

namespace Mica.App;

/// <summary>The application object. UI is built in code; this provider supplies the WinUI control metadata the XAML
/// compiler would otherwise generate, and XamlControlsResources the default control styles.</summary>
public sealed partial class MicaApplication : Application, IXamlMetadataProvider
{
    public static new MicaApplication? Current { get; private set; }
    readonly XamlControlsXamlMetaDataProvider provider = new();
    public DispatcherQueue Dispatcher { get; }
    public Store Store { get; } = Store.Shared;

    public MicaApplication()
    {
        ResourceManagerRequested += (_, e) =>
        {
            var pri = Path.Combine(AppContext.BaseDirectory, "mica.pri");
            if (File.Exists(pri)) e.CustomResourceManager = new Microsoft.Windows.ApplicationModel.Resources.ResourceManager(pri);
        };
        Current = this;
        Dispatcher = DispatcherQueue.GetForCurrentThread();
        UnhandledException += (_, e) => { Diagnostics.Log.Error(e.Exception); e.Handled = Store.Shared.Windows.Count > 0; };
    }

    public IXamlType GetXamlType(Type type) => provider.GetXamlType(type);
    public IXamlType GetXamlType(string fullName) => provider.GetXamlType(fullName);
    public XmlnsDefinition[] GetXmlnsDefinitions() => provider.GetXmlnsDefinitions();

    protected override async void OnLaunched(Microsoft.UI.Xaml.LaunchActivatedEventArgs args)
    {
        Resources.MergedDictionaries.Add(new XamlControlsResources());
        Notifications.Notifier.Shared.Start();
        await Store.StartAsync(LaunchUrls(Program.Arguments));
        if (Program.QA) await Diagnostics.QA.RunAsync(Store);
    }

    /// <summary>A second launch or a protocol activation: open its links in the active window.</summary>
    public void Activate(AppActivationArguments e)
    {
        var urls = new List<string>();
        if (e.Kind == ExtendedActivationKind.Launch && e.Data is ILaunchActivatedEventArgs launch) urls.AddRange(LaunchUrls(SplitArguments(launch.Arguments)));
        else if (e.Kind == ExtendedActivationKind.Protocol && e.Data is IProtocolActivatedEventArgs protocol) urls.Add(protocol.Uri.AbsoluteUri);
        else if (e.Kind == ExtendedActivationKind.File && e.Data is IFileActivatedEventArgs file) urls.AddRange(file.Files.Select(f => new Uri(f.Path).AbsoluteUri));
        else if (e.Kind == ExtendedActivationKind.AppNotification) { Notifications.Notifier.Shared.Activated(e); return; }
        var browser = Store.Active ?? Store.NewWindow();
        foreach (var url in urls) browser.Open(url);
        browser.Window?.Bring();
    }

    public static IEnumerable<string> LaunchUrls(IEnumerable<string> arguments) =>
        arguments.Where(a => !a.StartsWith("--", StringComparison.Ordinal) && Uri.TryCreate(a, UriKind.Absolute, out var u) && (u.Scheme == "http" || u.Scheme == "https"));

    static string[] SplitArguments(string? text) => string.IsNullOrWhiteSpace(text) ? [] :
        System.Text.RegularExpressions.Regex.Matches(text, "\"([^\"]*)\"|(\\S+)").Select(m => m.Groups[1].Success ? m.Groups[1].Value : m.Groups[2].Value).ToArray();
}
