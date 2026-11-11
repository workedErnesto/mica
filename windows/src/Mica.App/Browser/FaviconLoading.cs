using System.Runtime.InteropServices.WindowsRuntime;
using Mica.Core;

namespace Mica.App;

public sealed partial class Favicons
{
    readonly HashSet<string> loadingIcons = [];
    readonly Dictionary<string, DateTimeOffset> attempted = [];
    readonly SemaphoreSlim downloads = new(4);
    CancellationTokenSource cancellation = new();
    static readonly System.Net.Http.HttpClient iconHttp = new(new System.Net.Http.HttpClientHandler { UseCookies = false }) { Timeout = TimeSpan.FromSeconds(10) };

    void Prefetch(string? url)
    {
        if (Key(url) is not { } key || icons.ContainsKey(key) || !Uri.TryCreate(url, UriKind.Absolute, out var page) || page.Scheme is not ("http" or "https") ||
            (attempted.TryGetValue(key, out var last) && DateTimeOffset.UtcNow - last < TimeSpan.FromMinutes(1)) || !loadingIcons.Add(key)) return;
        _ = DiscoverAsync(key, page, generation, cancellation.Token);
    }

    async Task DiscoverAsync(string key, Uri page, int expected, CancellationToken token)
    {
        await Task.Yield(); // Icon is called while the shell is rendering.
        var entered = false;
        try
        {
            await downloads.WaitAsync(token); entered = true;
            if (diskReads.TryGetValue(key, out var read)) await read;
            if (expected != generation || icons.ContainsKey(key)) return;
            if (FaviconDiscovery.BundledFile(page.AbsoluteUri) is { } bundled)
            {
                var file = Path.Combine(AppContext.BaseDirectory, "Assets", "Favicons", bundled);
                if (System.IO.File.Exists(file))
                {
                    var png = await System.IO.File.ReadAllBytesAsync(file, token);
                    if (expected != generation || icons.ContainsKey(key)) return;
                    await SetAsync(page.AbsoluteUri, png);
                    return;
                }
            }
            var root = new UriBuilder(page) { Path = "/", Query = "", Fragment = "", UserName = "", Password = "" }.Uri;
            foreach (var delay in new[] { 0, 2, 8 })
            {
                if (delay > 0) await Task.Delay(TimeSpan.FromSeconds(delay), token);
                if (expected != generation || icons.ContainsKey(key)) return;
                var document = await Fetch(root, html: true, token);
                var resolved = document?.Url ?? root;
                var links = document is { } doc ? FaviconDiscovery.Links(System.Text.Encoding.UTF8.GetString(doc.Bytes), resolved.AbsoluteUri) : [];
                var candidates = FaviconDiscovery.Candidates(links.Where(l => !l.Dark), resolved.AbsoluteUri);
                if (FaviconDiscovery.RemoteURL(page.AbsoluteUri) is { } remote) candidates.Add(remote);
                foreach (var candidate in candidates)
                {
                    var data = await Fetch(new Uri(candidate), html: false, token);
                    if (data is null) continue;
                    try
                    {
                        if (expected != generation || icons.ContainsKey(key)) return;
                        await SetAsync(page.AbsoluteUri, data.Value.Bytes);
                        return;
                    }
                    catch (Exception e) { Diagnostics.Log.Error(e); }
                }
            }
        }
        catch (OperationCanceledException) { }
        catch (Exception e) { Diagnostics.Log.Error(e); }
        finally
        {
            if (entered) downloads.Release();
            if (expected == generation) { loadingIcons.Remove(key); attempted[key] = DateTimeOffset.UtcNow; }
        }
    }

    static async Task<(byte[] Bytes, Uri Url)?> Fetch(Uri url, bool html, CancellationToken token)
    {
        try
        {
            if (url.Scheme == "data")
            {
                var text = url.OriginalString; var comma = text.IndexOf(',');
                if (comma < 0 || text.Length > ByteLimit * 4 / 3 + 100) return null;
                var payload = Uri.UnescapeDataString(text[(comma + 1)..]);
                var bytes = text[..comma].EndsWith(";base64", StringComparison.OrdinalIgnoreCase) ? Convert.FromBase64String(payload) : System.Text.Encoding.UTF8.GetBytes(payload);
                return bytes.Length <= ByteLimit ? (bytes, url) : null;
            }
            using var request = new System.Net.Http.HttpRequestMessage(System.Net.Http.HttpMethod.Get, url);
            request.Headers.TryAddWithoutValidation("Accept", html ? "text/html,application/xhtml+xml" : "image/*");
            using var response = await iconHttp.SendAsync(request, System.Net.Http.HttpCompletionOption.ResponseHeadersRead, token);
            var mime = response.Content.Headers.ContentType?.MediaType ?? "";
            var final = response.RequestMessage?.RequestUri ?? url;
            if (!response.IsSuccessStatusCode || final.Scheme is not ("http" or "https") || response.Content.Headers.ContentLength > ByteLimit ||
                (html ? mime is not ("text/html" or "application/xhtml+xml") : mime.StartsWith("text/html", StringComparison.OrdinalIgnoreCase))) return null;
            using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
            deadline.CancelAfter(TimeSpan.FromSeconds(15));
            await using var stream = await response.Content.ReadAsStreamAsync(deadline.Token);
            using var memory = new MemoryStream(); var buffer = new byte[8192];
            int read;
            while ((read = await stream.ReadAsync(buffer, deadline.Token)) > 0)
            {
                if (memory.Length + read > ByteLimit) return null;
                memory.Write(buffer, 0, read);
            }
            return (memory.ToArray(), final);
        }
        catch { return null; }
    }

    static async Task<byte[]> Normalize(byte[] bytes)
    {
        using var input = new MemoryStream(bytes).AsRandomAccessStream();
        var decoder = await Windows.Graphics.Imaging.BitmapDecoder.CreateAsync(input);
        var scale = Math.Min(1, 64.0 / Math.Max(decoder.PixelWidth, decoder.PixelHeight));
        using var bitmap = await decoder.GetSoftwareBitmapAsync(Windows.Graphics.Imaging.BitmapPixelFormat.Bgra8,
            Windows.Graphics.Imaging.BitmapAlphaMode.Premultiplied,
            new Windows.Graphics.Imaging.BitmapTransform { ScaledWidth = Math.Max(1, (uint)(decoder.PixelWidth * scale)), ScaledHeight = Math.Max(1, (uint)(decoder.PixelHeight * scale)) },
            Windows.Graphics.Imaging.ExifOrientationMode.IgnoreExifOrientation, Windows.Graphics.Imaging.ColorManagementMode.ColorManageToSRgb);
        var pixels = new byte[bitmap.PixelWidth * bitmap.PixelHeight * 4];
        bitmap.CopyToBuffer(pixels.AsBuffer());
        if (!Enumerable.Range(0, pixels.Length / 4).Any(i => pixels[i * 4 + 3] >= 26)) throw new InvalidDataException("Transparent favicon");
        using var output = new Windows.Storage.Streams.InMemoryRandomAccessStream();
        var encoder = await Windows.Graphics.Imaging.BitmapEncoder.CreateAsync(Windows.Graphics.Imaging.BitmapEncoder.PngEncoderId, output);
        encoder.SetSoftwareBitmap(bitmap); await encoder.FlushAsync();
        output.Seek(0); using var reader = new Windows.Storage.Streams.DataReader(output);
        await reader.LoadAsync((uint)output.Size); var png = new byte[(int)output.Size]; reader.ReadBytes(png);
        return png;
    }
}
