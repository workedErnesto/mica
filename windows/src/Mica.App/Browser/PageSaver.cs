using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.Web.WebView2.Core;
using Mica.App.Downloads;
using Mica.Core;
using Mica.Design;

namespace Mica.App;

/// <summary>Saves the page of a tab (macOS PageSaver): PDF through WebView2's print engine with the page's print
/// styles, a PNG or JPEG picture of the whole page through DevTools, or one HTML file with the page's images, styles
/// and fonts inside it. The format is picked in mica's own menu, the place in the system save dialog opened on
/// Downloads; the file then appears in downloads with its type, size and folder.</summary>
public static partial class PageSaver
{
    public static string Title(this PageFormat format, BrowserModel browser) => format switch
    {
        PageFormat.Pdf => "PDF",
        PageFormat.Png => browser.Text("картинка PNG", "Картинка PNG"),
        PageFormat.Jpeg => browser.Text("картинка JPEG", "Картинка JPEG"),
        _ => "HTML",
    };

    public static string Symbol(this PageFormat format) => format switch
    {
        PageFormat.Pdf => "doc.text", PageFormat.Png => "photo", PageFormat.Jpeg => "camera", _ => "chevron.left.forwardslash.chevron.right",
    };

    public static bool CanSave(Tab? tab) =>
        tab is { Core: not null, Phase: not TabPhase.Terminated, Url: { } url } && (url.StartsWith("http://", StringComparison.OrdinalIgnoreCase) || url.StartsWith("https://", StringComparison.OrdinalIgnoreCase) || url.StartsWith("file:", StringComparison.OrdinalIgnoreCase));

    /// <summary>The format menu shared by the toolbar button and Ctrl+S.</summary>
    public static IEnumerable<MenuEntry> Entries(Tab tab, BrowserModel browser) =>
        PageFormats.All.Select(format => MenuEntry.Item(format.Title(browser), () => Save(tab, browser, format), format.Symbol()));

    [System.Runtime.InteropServices.LibraryImport("shell32.dll")]
    private static partial int SHGetKnownFolderPath(in Guid id, uint flags, nint token, out nint path);

    /// <summary>The user's Downloads folder (FOLDERID_Downloads), which the user may have moved.</summary>
    public static string DownloadsFolder
    {
        get
        {
            var id = new Guid("374DE290-123F-4565-9164-39C4925E467B");
            if (SHGetKnownFolderPath(id, 0, 0, out var pointer) == 0)
            {
                try { if (System.Runtime.InteropServices.Marshal.PtrToStringUni(pointer) is { Length: > 0 } path) return path; }
                finally { System.Runtime.InteropServices.Marshal.FreeCoTaskMem(pointer); }
            }
            return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads");
        }
    }

    public static async void Save(Tab tab, BrowserModel browser, PageFormat format)
    {
        if (!CanSave(tab) || tab.Core is not { } core || tab.Url is not { } page) return;
        // A PDF or picture opened in the tab is already the file to keep: an ordinary download of it.
        var type = await Evaluate(core, "document.contentType");
        if (type is { } t && t is not ("text/html" or "application/xhtml+xml"))
        {
            await core.ExecuteScriptAsync("(() => { const a = document.createElement('a'); a.href = location.href; a.download = ''; document.body.appendChild(a); a.click(); a.remove(); })()");
            return;
        }
        if (await Choose(tab, page, browser, format) is not { } destination) return;
        var item = new DownloadItem(browser.Downloads, destination, tab);
        browser.Downloads.AddSaved(item);
        Run(item, tab, browser, format);
    }

    /// <summary>The system save dialog of Explorer (macOS: the expanded save panel), opened on Downloads with the page
    /// title as a free name there. The format was chosen in mica's menu, so the dialog offers only that type.</summary>
    static async Task<string?> Choose(Tab tab, string page, BrowserModel browser, PageFormat format)
    {
        var folder = DownloadsFolder;
        var proposed = PageExport.AvailableName(PageExport.FileName(tab.Title, page, format), n => File.Exists(Path.Combine(folder, n)));
        var picker = new Windows.Storage.Pickers.FileSavePicker { SuggestedStartLocation = Windows.Storage.Pickers.PickerLocationId.Downloads, SuggestedFileName = Path.GetFileNameWithoutExtension(proposed) };
        picker.FileTypeChoices.Add(format.Title(browser), ["." + format.Extension()]);
        if (browser.Window is { } window) WinRT.Interop.InitializeWithWindow.Initialize(picker, Win32.Handle(window));
        try { return (await picker.PickSaveFileAsync())?.Path; }
        catch (Exception error) { browser.Show(browser.Text("не удалось сохранить страницу", "Не удалось сохранить страницу") + ": " + error.Message); return null; }
    }

    static async void Run(DownloadItem item, Tab tab, BrowserModel browser, PageFormat format)
    {
        item.SaveAgain = () => { item.SavingStarted(); Run(item, tab, browser, format); };
        var work = new CancellationTokenSource();
        item.Work = work;
        var destination = item.Destination!;
        try
        {
            if (tab.Core is not { } core) throw new SaveFailure();
            await Write(core, tab, format, destination, item.SavingProgress, work.Token);
            work.Token.ThrowIfCancellationRequested();
            item.SavingFinished();
            browser.Panel = LibraryPanel.Downloads;
        }
        catch (Exception error)
        {
            // Only the empty placeholder the dialog created is removed; a file the user agreed to replace stays as it was.
            try { if (File.Exists(destination) && new FileInfo(destination).Length == 0) File.Delete(destination); } catch (IOException) { } catch (UnauthorizedAccessException) { }
            if (error is OperationCanceledException || item.State == DownloadState.Cancelled) return;
            item.SavingFailed(error is SaveFailure or JsonException or System.Runtime.InteropServices.COMException ? browser.Text("не удалось сохранить страницу", "Не удалось сохранить страницу") : error.Message);
            browser.Panel = LibraryPanel.Downloads;
        }
    }

    /// <summary>Something on the way gave nothing back; the row shows a plain sentence instead of an internal reason.</summary>
    sealed class SaveFailure : Exception;

    static async Task Write(CoreWebView2 core, Tab tab, PageFormat format, string destination, Action<double> progress, CancellationToken cancel)
    {
        // Images marked lazy below the visible part are asked to load now, with a three-second limit.
        await Cdp(core, "Runtime.evaluate", new JsonObject { ["expression"] = "(async () => {" + PageExport.PrepareScript + "})()", ["awaitPromise"] = true });
        progress(0.25);
        switch (format)
        {
            case PageFormat.Pdf:
            {
                var settings = core.Environment.CreatePrintSettings();
                // A4 where the region measures in metres, Letter otherwise, like the system default of a new printer.
                if (System.Globalization.RegionInfo.CurrentRegion.IsMetric) { settings.PageWidth = 8.27; settings.PageHeight = 11.69; }
                settings.ShouldPrintBackgrounds = false;
                settings.ShouldPrintHeaderAndFooter = false;
                // The print engine writes into a temporary file; the chosen file is written only once it is complete.
                var temporary = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N") + ".pdf");
                try
                {
                    if (!await core.PrintToPdfAsync(temporary, settings)) throw new SaveFailure();
                    cancel.ThrowIfCancellationRequested();
                    File.Copy(temporary, destination, overwrite: true);
                }
                finally { try { File.Delete(temporary); } catch (IOException) { } }
                break;
            }
            case PageFormat.Png:
            case PageFormat.Jpeg:
            {
                var metrics = await Cdp(core, "Page.getLayoutMetrics", new JsonObject());
                var width = metrics?["cssLayoutViewport"]?["clientWidth"]?.GetValue<double>() ?? 0;
                var height = metrics?["cssContentSize"]?["height"]?.GetValue<double>() ?? 0;
                var scale = tab.Owner?.Window?.Content?.XamlRoot?.RasterizationScale ?? 1;
                if (PageExport.ImagePixels(width, height, scale) is not { } size) throw new SaveFailure();
                progress(0.5);
                // DevTools multiplies the clip by the device scale itself, so the clip scale carries only the reduction.
                var request = new JsonObject
                {
                    ["format"] = format == PageFormat.Png ? "png" : "jpeg",
                    ["captureBeyondViewport"] = true,
                    ["fromSurface"] = true,
                    ["clip"] = new JsonObject { ["x"] = 0, ["y"] = 0, ["width"] = width, ["height"] = height, ["scale"] = size.Width / width / scale },
                };
                if (format == PageFormat.Jpeg) request["quality"] = 90;
                var shot = await Cdp(core, "Page.captureScreenshot", request);
                if (shot?["data"]?.GetValue<string>() is not { } data) throw new SaveFailure();
                cancel.ThrowIfCancellationRequested();
                await File.WriteAllBytesAsync(destination, Convert.FromBase64String(data), cancel);
                break;
            }
            default:
            {
                var json = await core.ExecuteScriptAsync("(() => {" + PageExport.SerializeScript + "})()");
                var page = JsonNode.Parse(json);
                if (page?["html"]?.GetValue<string>() is not { } html || page["base"]?.GetValue<string>() is not { } @base) throw new SaveFailure();
                progress(0.45);
                var resources = await Resources(core, cancel);
                progress(0.65);
                var text = await Task.Run(() => SingleFilePage.Build(html, @base, resources), cancel);
                cancel.ThrowIfCancellationRequested();
                await File.WriteAllTextAsync(destination, text, new UTF8Encoding(false), cancel);
                break;
            }
        }
        progress(1);
    }

    /// <summary>Files of the main frame the page loaded, from the DevTools resource tree. Frames keep their own
    /// addresses, as on macOS.</summary>
    static async Task<List<PageResource>> Resources(CoreWebView2 core, CancellationToken cancel)
    {
        await Cdp(core, "Page.enable", new JsonObject());
        var tree = await Cdp(core, "Page.getResourceTree", new JsonObject());
        var frame = tree?["frameTree"]?["frame"]?["id"]?.GetValue<string>();
        var list = new List<PageResource>();
        if (frame is null || tree?["frameTree"]?["resources"] is not JsonArray resources) return list;
        foreach (var resource in resources)
        {
            cancel.ThrowIfCancellationRequested();
            var url = resource?["url"]?.GetValue<string>();
            var kind = resource?["type"]?.GetValue<string>();
            if (url is null || kind is not ("Image" or "Stylesheet" or "Font" or "Media")) continue;
            var content = await Cdp(core, "Page.getResourceContent", new JsonObject { ["frameId"] = frame, ["url"] = url });
            if (content?["content"]?.GetValue<string>() is not { } body) continue;
            var bytes = content["base64Encoded"]?.GetValue<bool>() == true ? Convert.FromBase64String(body) : Encoding.UTF8.GetBytes(body);
            list.Add(new PageResource(url, resource?["mimeType"]?.GetValue<string>() ?? "", bytes));
        }
        return list;
    }

    static async Task<JsonNode?> Cdp(CoreWebView2 core, string method, JsonObject parameters)
    {
        try
        {
            var result = JsonNode.Parse(await core.CallDevToolsProtocolMethodAsync(method, parameters.ToJsonString()));
            return method == "Runtime.evaluate" ? result?["result"] : result;
        }
        catch (Exception) when (method is "Runtime.evaluate" or "Page.getResourceContent") { return null; }
    }

    static async Task<string?> Evaluate(CoreWebView2 core, string expression)
    {
        try { return JsonNode.Parse(await core.ExecuteScriptAsync(expression))?.GetValue<string>(); }
        catch (Exception) { return null; }
    }
}
