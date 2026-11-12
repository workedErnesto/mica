using System.Text.Json;
using Mica.App;
using Xunit;

namespace Mica.Core.Tests;

public class ContentRulesTests
{
    ContentRules Rules()
    {
        using var document = JsonDocument.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "blocking-compiled.json")));
        var reader = new Utf8JsonReader(System.Text.Encoding.UTF8.GetBytes(document.RootElement.GetProperty("windows").GetRawText()));
        reader.Read();
        return new ContentRules(ref reader, "com\nco.uk\n*.ck\n!www.ck\n");
    }
    [Theory]
    [InlineData("https://ads.example/banner.js", "https://news.test/", "script", true)]
    [InlineData("https://sub.ads.example/banner.js", "https://news.test/", "script", true)]
    [InlineData("https://notads.example/banner.js", "https://news.test/", "script", false)]
    [InlineData("https://ads.example/banner.js", "https://www.ads.example/", "script", false)]
    [InlineData("https://ads.example/allowed.js", "https://news.test/", "script", false)]
    [InlineData("https://ads.example/allowed.js", "https://news.test/", "image", true)]
    public void EvaluatesActualCompilerOutput(string url, string top, string type, bool expected) => Assert.Equal(expected, Rules().ShouldBlock(url, top, type, false, []));
    [Fact]
    public void ExcludingTopSiteAlsoExcludesItsSubdomains() => Assert.False(Rules().ShouldBlock("https://ads.example/a.js", "https://sub.news.test/", "script", false, ["news.test"]));
    [Fact]
    public void PublicSuffixDistinguishesSeparateCoUkSites()
    {
        using var document = JsonDocument.Parse("""[{"trigger":{"url-filter":".*","load-type":["third-party"]},"action":{"type":"block"}}]""");
        var rules = new ContentRules(document.RootElement, "co.uk\n*.ck\n!www.ck\n");
        Assert.True(rules.ShouldBlock("https://ads.co.uk/x", "https://news.co.uk/", "script", false, []));
        Assert.False(rules.ShouldBlock("https://img.news.co.uk/x", "https://news.co.uk/", "image", false, []));
        Assert.True(rules.ShouldBlock("https://127.0.0.1/x", "https://192.168.0.1/", "script", false, []));
        Assert.True(rules.ShouldBlock("https://a.ck/x", "https://b.ck/", "script", false, []));
        Assert.False(rules.ShouldBlock("https://img.www.ck/x", "https://www.ck/", "image", false, []));
    }
}
