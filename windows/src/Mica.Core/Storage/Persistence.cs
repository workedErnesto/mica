using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.Json.Serialization.Metadata;

namespace Mica.Core;

/// <summary>Reflection-free JSON for every file mica writes, so the app stays compatible with Native AOT and trimming.
/// Keys and enum spellings follow the macOS files (camelCase keys, lowercase enum values, engine names as written).</summary>
[JsonSourceGenerationOptions(PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase, WriteIndented = true,
    DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull, ReadCommentHandling = JsonCommentHandling.Skip, AllowTrailingCommas = true,
    Converters = [typeof(SearchEngineConverter), typeof(LowerEnum<TabLayout>), typeof(LowerEnum<Theme>), typeof(LowerEnum<Language>),
        typeof(LowerEnum<ClearPeriod>), typeof(LowerEnum<StartSection>), typeof(LowerEnum<ToolbarControl>), typeof(LowerEnum<ToolbarZone>),
        typeof(LowerEnum<SiteCapability>), typeof(LowerEnum<Decision>)])]
[JsonSerializable(typeof(Preferences))]
[JsonSerializable(typeof(Session))]
[JsonSerializable(typeof(List<Visit>))]
[JsonSerializable(typeof(List<SitePermission>))]
[JsonSerializable(typeof(List<DownloadRecord>))]
[JsonSerializable(typeof(List<ExtensionRecord>))]
[JsonSerializable(typeof(Vault))]
[JsonSerializable(typeof(Release))]
[JsonSerializable(typeof(KeymapFile))]
[JsonSerializable(typeof(GlyphFile))]
[JsonSerializable(typeof(Dictionary<string, string>))]
[JsonSerializable(typeof(string))]
[JsonSerializable(typeof(List<string>))]
[JsonSerializable(typeof(JsonElement))]
public sealed partial class MicaJson : JsonSerializerContext
{
    /// <summary>Enum values are written in lowercase camel case, matching the macOS raw values (left, hour, ask, newTab).</summary>
    public static JsonTypeInfo<T> Info<T>() => (JsonTypeInfo<T>)Default.GetTypeInfo(typeof(T))!;
}

public sealed class LowerEnum<T>() : JsonStringEnumConverter<T>(JsonNamingPolicy.CamelCase, allowIntegerValues: false) where T : struct, Enum;

public sealed class SearchEngineConverter : JsonConverter<SearchEngine>
{
    public override SearchEngine Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options) =>
        SearchEngines.Parse(reader.TokenType == JsonTokenType.String ? reader.GetString() : null) ?? SearchEngine.DuckDuckGo;
    public override void Write(Utf8JsonWriter writer, SearchEngine value, JsonSerializerOptions options) => writer.WriteStringValue(value.RawValue());
}

public static class Persistence
{
    public static T Read<T>(string path) => JsonSerializer.Deserialize(File.ReadAllBytes(path), MicaJson.Info<T>()) ?? throw new InvalidDataException(Path.GetFileName(path));

    /// <summary>Atomic replace: write a sibling temp file, flush it to disk, then move over the original.</summary>
    public static void Write<T>(T value, string path)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        WriteBytes(JsonSerializer.SerializeToUtf8Bytes(value, MicaJson.Info<T>()), path);
    }

    public static void WriteBytes(byte[] bytes, string path)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var temp = path + "." + Guid.NewGuid().ToString("N")[..8] + ".tmp";
        using (var stream = new FileStream(temp, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough))
        {
            stream.Write(bytes);
            stream.Flush(true);
        }
        File.Move(temp, path, overwrite: true);
    }
}
