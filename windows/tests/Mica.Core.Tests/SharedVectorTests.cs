using System.Text.Json;
using System.Text.Json.Nodes;
using Mica.Core;
using Xunit;

namespace Mica.Core.Tests;

/// <summary>Same file as macos/Tests/MicaCoreTests/SharedVectorTests.swift; macOS fills the expectations.</summary>
public class SharedVectorTests
{
    static JsonNode? Actual(string section, JsonObject c)
    {
        string S(string key) => c[key]!.GetValue<string>();
        bool B(string key) => c[key]!.GetValue<bool>();
        int I(string key) => c[key]!.GetValue<int>();
        SearchEngine Engine() => SearchEngines.Parse(c["engine"]?.GetValue<string>()) ?? SearchEngine.DuckDuckGo;
        Language Lang() => S("language") == "en" ? Language.En : Language.Ru;
        switch (section)
        {
            case "address":
                var target = AddressParser.Resolve(S("input"), Engine());
                return target.Kind switch { AddressKind.Web => "web:" + target.Value, AddressKind.External => "external:" + target.Value, _ => "rejected:" + target.Value };
            case "blockingExceptions": return new JsonArray([.. DomainBlocker.MatchingExceptions(S("host"), c["exceptions"]!.AsArray().Select(x => x!.GetValue<string>())).Select(x => (JsonNode)JsonValue.Create(x))]);
            case "navigation": return AddressParser.Navigable(S("url"), B("mainFrame"));
            case "origin": return Origin.Of(S("url"));
            case "localFile": return AddressParser.OpenableFile(S("url"));
            case "externalScheme": return AddressParser.External(S("url"));
            case "appLinkAllowed":
                var allowed = c["allowed"]!.AsArray().Select(x => new AppLinkPermission { Origin = x![0]!.GetValue<string>(), Scheme = x[1]!.GetValue<string>() }).ToList();
                return AppLinkPermission.Allows(allowed, c["origin"]?.GetValue<string>(), S("url"));
            case "version":
                var a = AppVersion.Parse(S("a")); var b = AppVersion.Parse(S("b"));
                return a is null || b is null ? "invalid" : Math.Sign(a.CompareTo(b));
            case "checksum": return UpdatePolicy.ParseChecksum(S("text"));
            case "filename": return DownloadSafety.Filename(S("name"), windows: false);
            case "downloadKind": return DownloadKinds.Name(DownloadKinds.Of(S("name")));
            case "copy": return Copy.Text(S("low"), S("regular"), B("lowercase"), Lang());
            case "greeting":
                var p = new Preferences { UserName = S("name"), GreetByName = B("greet"), Language = Lang(), Lowercase = B("lowercase") };
                return Greeting.Text(p, I("hour"), I("seed"));
            case "period":
                var now = DateTimeOffset.FromUnixTimeSeconds(1_800_000_000);
                var period = Enum.Parse<ClearPeriod>(S("period"), ignoreCase: true);
                return period == ClearPeriod.All ? null : (int)(now - period.Start(now)).TotalSeconds;
            case "notification":
                var n = WebNotification.Parse(S("id"), S("title"), S("body"), S("tag"), B("silent"));
                return n is null ? null : new JsonObject { ["title"] = n.Title, ["body"] = n.Body, ["tag"] = n.Tag, ["silent"] = n.Silent };
            case "chromeId": return ChromeStore.ExtensionId(S("input"));
            case "luminance": return HexColor.Luminance(S("hex")) is { } l ? Math.Round(l * 10000, MidpointRounding.AwayFromZero) / 10000 : null;
            case "shortcut": return StartPage.ShortcutUrl(S("input"), Engine());
            case "profileName": return Profiles.Name(S("input"));
            case "profileNext":
                var icons = c["icons"]!.AsArray().Select(x => x!.GetValue<string>()).ToList();
                var backgrounds = c["backgrounds"]!.AsArray().Select(x => x!.GetValue<string>()).ToList();
                var list = icons.Zip(backgrounds, (i, b) => new Profile { Name = "x", Icon = i, Background = b }).ToList();
                var next = Profiles.Next(list, "", new ProfileLook());
                return new JsonObject { ["icon"] = next.Icon, ["background"] = next.Background };
            case "profileText":
                // A profile without its own language or case takes the application-wide ones.
                var look = new ProfileLook
                {
                    Language = c["lookLanguage"]?.GetValue<string>() is { } own ? (own == "en" ? Language.En : Language.Ru) : null,
                    Lowercase = c["lookLowercase"]?.GetValue<bool>(),
                };
                var global = new Preferences { Language = S("language") == "en" ? Language.En : Language.Ru, Lowercase = c["lowercase"]!.GetValue<bool>() };
                var applied = look.AppliedTo(global);
                return (applied.Language == Language.En ? "en" : "ru") + (applied.Lowercase ? "-low" : "-regular");
            case "addressDisplay":
                // Quieter parts are marked with a leading ~.
                bool O(string key) => c[key]?.GetValue<bool>() ?? false;
                var style = new AddressStyle { Full = O("full"), DimSubdomain = O("dimSubdomain"), DimPath = O("dimPath") };
                return new JsonArray([.. AddressDisplay.Parts(S("url"), style).Select(p => (JsonNode)JsonValue.Create((p.Dim ? "~" : "") + p.Text))]);
            case "faviconRemote": return FaviconDiscovery.RemoteURL(S("page"));
            case "faviconCatalog": return FaviconDiscovery.BundledFile(S("page"));
            case "faviconDiscovery":
                return new JsonArray([.. FaviconDiscovery.Candidates(FaviconDiscovery.Links(S("html"), S("page")).Where(l => l.Dark == (c["dark"]?.GetValue<bool>() ?? false)), S("page"), c["fallback"]?.GetValue<bool>() ?? true).Select(s => (JsonNode)JsonValue.Create(s))]);
            case "faviconTone":
                // "ink" when the glyph is redrawn in the shell's ink, "keep" when its own colour reads, "image" for icons that are not a glyph.
                var pixels = S("pixels").Split(' ').SelectMany(t => { var v = Convert.ToUInt32(t, 16); return new[] { (byte)(v >> 24), (byte)(v >> 16), (byte)(v >> 8), (byte)v }; }).ToArray();
                return FaviconTone.Glyph(pixels) is { } glyph ? (FaviconTone.NeedsInk(glyph, HexColor.Luminance(S("background"))!.Value) ? "ink" : "keep") : "image";
            case "pageFileName": return PageExport.FileName(S("title"), c["url"]?.GetValue<string>(), PageFormats.Parse(S("format"))!.Value);
            case "pageImage":
                double D(string key) => c[key]!.GetValue<double>();
                return PageExport.ImagePixels(D("width"), D("height"), D("scale")) is { } size ? new JsonArray(size.Width, size.Height) : null;
            case "availableName":
                var takenNames = c["taken"]!.AsArray().Select(x => x!.GetValue<string>()).ToHashSet();
                return PageExport.AvailableName(S("name"), takenNames.Contains);
            case "webAddress": return WebAddress.Resolve(S("ref"), S("base"));
            case "singleFilePage":
                var resources = c["resources"]!.AsArray().Select(r => new PageResource(r!["url"]!.GetValue<string>(), r["mime"]!.GetValue<string>(),
                    r["text"] is { } text ? System.Text.Encoding.UTF8.GetBytes(text.GetValue<string>()) : Convert.FromBase64String(r["base64"]!.GetValue<string>())));
                return SingleFilePage.Build(S("html"), S("base"), resources);
            case "profileGlyph": return Profiles.LightGlyph(S("hex"), c["glyph"]?.GetValue<string>() switch { "light" => ProfileGlyph.Light, "dark" => ProfileGlyph.Dark, _ => ProfileGlyph.Auto }) ? "light" : "dark";
            case "passwordOffer":
                // Saved logins carry seconds since 2026 for their update and last use, so the order is defined.
                var start2026 = DateTimeOffset.FromUnixTimeSeconds(1_767_225_600);
                var vault = new Vault { Never = c["never"]?.AsArray().Select(x => x!.GetValue<string>()).ToList() ?? [] };
                foreach (var item in c["logins"]!.AsArray())
                    vault.Logins.Add(new SavedLogin
                    {
                        Origin = item!["origin"]!.GetValue<string>(), Username = item["username"]!.GetValue<string>(), Password = "p", Created = start2026,
                        Updated = start2026.AddSeconds(item["updated"]!.GetValue<double>()), Used = item["used"] is { } used ? start2026.AddSeconds(used.GetValue<double>()) : null,
                    });
                var offer = PasswordOffer.Decide(vault, S("origin"), B("new"), I("max"), c["offerPasswords"]?.GetValue<bool>() ?? true, c["fillPasswords"]?.GetValue<bool>() ?? true);
                return offer is null ? "none" : offer.Kind == PasswordOfferKind.Generate ? "generate" : "fill:" + string.Join(",", offer.Logins.Select(l => l.Username));
            case "passwordOfferSession":
                // Events as "focus:1", "click:1", "input:1", "blur:1", "dismiss", "accept", "leave"; visibility after each.
                var session = new PasswordOfferSession();
                var shown = new JsonArray();
                foreach (var text in c["events"]!.AsArray().Select(x => x!.GetValue<string>()))
                {
                    var parts = text.Split(':');
                    var id = parts.Length > 1 ? int.Parse(parts[1]) : 0;
                    session.Apply(parts[0] switch
                    {
                        "focus" => PasswordOfferEvent.Focus, "click" => PasswordOfferEvent.Click, "input" => PasswordOfferEvent.Input, "blur" => PasswordOfferEvent.Blur,
                        "dismiss" => PasswordOfferEvent.Dismiss, "accept" => PasswordOfferEvent.Accept, _ => PasswordOfferEvent.Leave,
                    }, id);
                    shown.Add(session.Visible);
                }
                return shown;
            case "passwordOfferPlace":
                double[] N(string key) => c[key]!.AsArray().Select(x => x!.GetValue<double>()).ToArray();
                var f = N("field"); var viewSize = N("view"); var panelSize = N("panel");
                var fieldRect = PasswordOfferPlacement.ViewRect(new OfferRect(f[0], f[1], f[2], f[3]), c["innerWidth"]!.GetValue<double>(), viewSize[0]);
                var placed = PasswordOfferPlacement.Place(fieldRect, viewSize[0], viewSize[1], panelSize[0], panelSize[1], c["gap"]!.GetValue<double>(), c["margin"]!.GetValue<double>());
                return placed is { } p2 ? new JsonArray(p2.Frame.X, p2.Frame.Y, p2.Frame.Width, p2.Frame.Height, p2.Edge == OfferEdge.Above ? "above" : "below") : null;
            default: throw new InvalidOperationException(section);
        }
    }

    public static IEnumerable<object[]> Cases()
    {
        var root = JsonNode.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "vectors.json")))!.AsObject();
        foreach (var (section, value) in root)
        {
            if (section.StartsWith('$')) continue;
            var index = 0;
            foreach (var item in value!.AsArray()) yield return [section, index++, item!.ToJsonString()];
        }
    }

    [Theory]
    [MemberData(nameof(Cases))]
    public void MatchesMacOS(string section, int index, string json)
    {
        var c = JsonNode.Parse(json)!.AsObject();
        var expected = c["expect"];
        var actual = Actual(section, c);
        Assert.True(JsonNode.DeepEquals(Normalize(expected), Normalize(actual)), $"{section}[{index}] expected {expected?.ToJsonString() ?? "null"}, got {actual?.ToJsonString() ?? "null"}");
    }

    // Numbers compare by value: 0.3 written by Foundation and by System.Text.Json may differ in spelling.
    static JsonNode? Normalize(JsonNode? node) => node switch
    {
        JsonValue v when v.TryGetValue<double>(out var d) => JsonValue.Create(Math.Round(d, 6)),
        JsonValue v when v.TryGetValue<int>(out var i) => JsonValue.Create((double)i),
        JsonObject o => new JsonObject(o.Select(kv => KeyValuePair.Create(kv.Key, Normalize(kv.Value)))),
        _ => node?.DeepClone(),
    };
}
