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
            case "origin": return Origin.Of(S("url"));
            case "localFile": return AddressParser.OpenableFile(S("url"));
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
            case "profileGlyph": return Profiles.LightGlyph(S("hex"), c["glyph"]?.GetValue<string>() switch { "light" => ProfileGlyph.Light, "dark" => ProfileGlyph.Dark, _ => ProfileGlyph.Auto }) ? "light" : "dark";
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
