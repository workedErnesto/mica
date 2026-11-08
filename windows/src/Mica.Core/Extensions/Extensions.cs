using System.Security.Cryptography;
using System.Text;

namespace Mica.Core;

public sealed class ExtensionRecord
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Name { get; set; } = "";
    public string Version { get; set; } = "";
    public bool Enabled { get; set; }
    public string Digest { get; set; } = "";
    public string Source { get; set; } = "";
    public List<string> Permissions { get; set; } = [];
    public List<string> Hosts { get; set; } = [];
    /// <summary>Id WebView2 assigned when the extension was added to the profile.</summary>
    public string? EngineId { get; set; }
}

public static class PackageSafety
{
    public static bool SafeEntry(string name) =>
        !name.StartsWith('/') && !name.Contains('\\') && !name.Split('/').Contains("..") && !name.Contains('\0') && !(name.Length > 1 && name[1] == ':');
}

/// <summary>Chrome Web Store packages: a signed CRX3 protobuf header followed by a ZIP archive.</summary>
public static class ChromeStore
{
    public const string ProductVersion = "142.0.0.0";

    public static string? ExtensionId(string input)
    {
        var text = input.Trim();
        if (IsId(text)) return text;
        if (!Uri.TryCreate(text.Contains("://") ? text : "https://" + text, UriKind.Absolute, out var url)) return null;
        var host = url.Host.ToLowerInvariant();
        if (host != "chromewebstore.google.com" && !(host == "chrome.google.com" && url.AbsolutePath.StartsWith("/webstore", StringComparison.Ordinal))) return null;
        return url.AbsolutePath.Split('/', StringSplitOptions.RemoveEmptyEntries).LastOrDefault(IsId);
    }

    public static bool IsId(string text) => text.Length == 32 && text.All(c => c >= 'a' && c <= 'p');
    public static bool IsDetailPage(string? url) => url is not null && ExtensionId(url) is not null;

    public static string DownloadUrl(string id) =>
        "https://clients2.google.com/service/update2/crx?response=redirect&prodversion=" + ProductVersion +
        "&acceptformat=crx3&x=" + Uri.EscapeDataString($"id={id}&installsource=ondemand&uc");

    /// <summary>First 16 bytes of the key's SHA-256, each nibble written as a letter a to p.</summary>
    public static string IdForPublicKey(byte[] key) => Letters(SHA256.HashData(key).AsSpan(0, 16));

    internal static string Letters(ReadOnlySpan<byte> bytes)
    {
        var builder = new StringBuilder(bytes.Length * 2);
        foreach (var b in bytes) { builder.Append((char)('a' + (b >> 4))); builder.Append((char)('a' + (b & 0x0f))); }
        return builder.ToString();
    }
}

public sealed class CrxException(string message) : Exception(message);

public sealed class CrxPackage
{
    public sealed record Proof(byte[] PublicKey, byte[] Signature, bool Ecdsa);
    public List<Proof> Proofs { get; } = [];
    public byte[] SignedHeader { get; }
    public string CrxId { get; }
    public byte[] Archive { get; }

    public CrxPackage(byte[] bytes)
    {
        if (bytes.Length <= 12 || bytes[0] != 0x43 || bytes[1] != 0x72 || bytes[2] != 0x32 || bytes[3] != 0x34) throw new CrxException("not a CRX package");
        uint U32(int at) => (uint)(bytes[at] | bytes[at + 1] << 8 | bytes[at + 2] << 16 | bytes[at + 3] << 24);
        var version = U32(4);
        if (version != 3) throw new CrxException($"CRX version {version} is not supported");
        var headerSize = (int)U32(8);
        if (headerSize <= 0 || 12 + headerSize >= bytes.Length) throw new CrxException("CRX header is damaged");
        var header = bytes[12..(12 + headerSize)];
        byte[]? signed = null;
        foreach (var field in Protobuf.Fields(header).Where(f => f.Wire == 2))
        {
            if (field.Number is 2 or 3)
            {
                byte[]? key = null, signature = null;
                foreach (var inner in Protobuf.Fields(field.Bytes).Where(f => f.Wire == 2))
                {
                    if (inner.Number == 1) key = inner.Bytes; else if (inner.Number == 2) signature = inner.Bytes;
                }
                if (key is not null && signature is not null) Proofs.Add(new Proof(key, signature, field.Number == 3));
            }
            else if (field.Number == 10000) signed = field.Bytes;
        }
        var idBytes = signed is null ? null : Protobuf.Fields(signed).FirstOrDefault(f => f.Number == 1 && f.Wire == 2)?.Bytes;
        if (signed is null || idBytes is null || idBytes.Length != 16) throw new CrxException("CRX header is damaged");
        SignedHeader = signed;
        CrxId = ChromeStore.Letters(idBytes);
        Archive = bytes[(12 + headerSize)..];
        if (Archive.Length < 2 || Archive[0] != 0x50 || Archive[1] != 0x4b) throw new CrxException("CRX header is damaged");
    }

    /// <summary>The signed header must name the expected id, and the key that produces this id must have signed the package.</summary>
    public void Verify(string expectedId)
    {
        if (CrxId != expectedId) throw new CrxException($"package ID {CrxId} does not match {expectedId}");
        var message = new List<byte>(Encoding.ASCII.GetBytes("CRX3 SignedData")) { 0 };
        message.AddRange(BitConverter.GetBytes((uint)SignedHeader.Length));
        message.AddRange(SignedHeader); message.AddRange(Archive);
        var data = message.ToArray();
        var developer = Proofs.Where(p => ChromeStore.IdForPublicKey(p.PublicKey) == CrxId).ToList();
        if (developer.Count == 0 || !developer.All(p => Check(p, data))) throw new CrxException("CRX signature check failed");
    }

    static bool Check(Proof proof, byte[] message)
    {
        try
        {
            if (proof.Ecdsa)
            {
                using var ec = ECDsa.Create();
                ec.ImportSubjectPublicKeyInfo(proof.PublicKey, out _);
                return ec.VerifyData(message, proof.Signature, HashAlgorithmName.SHA256, DSASignatureFormat.Rfc3279DerSequence);
            }
            using var rsa = RSA.Create();
            rsa.ImportSubjectPublicKeyInfo(proof.PublicKey, out _);
            return rsa.VerifyData(message, proof.Signature, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
        }
        catch (CryptographicException) { return false; }
    }
}

/// <summary>Minimal protobuf reader: enough for CRX headers (varint and length-delimited fields).</summary>
static class Protobuf
{
    public sealed record Field(int Number, int Wire, byte[] Bytes);
    public static List<Field> Fields(byte[] data)
    {
        var result = new List<Field>();
        var i = 0;
        ulong Varint()
        {
            ulong value = 0; var shift = 0;
            while (true)
            {
                if (i >= data.Length || shift >= 64) throw new CrxException("CRX header is damaged");
                var b = data[i++];
                value |= (ulong)(b & 0x7f) << shift;
                if ((b & 0x80) == 0) return value;
                shift += 7;
            }
        }
        while (i < data.Length)
        {
            var tag = Varint();
            int number = (int)(tag >> 3), wire = (int)(tag & 7);
            switch (wire)
            {
                case 0: Varint(); result.Add(new Field(number, 0, [])); break;
                case 2:
                    var length = Varint();
                    if (length > (ulong)(data.Length - i)) throw new CrxException("CRX header is damaged");
                    result.Add(new Field(number, 2, data[i..(i + (int)length)])); i += (int)length; break;
                case 1: if (data.Length - i < 8) throw new CrxException("CRX header is damaged"); i += 8; break;
                case 5: if (data.Length - i < 4) throw new CrxException("CRX header is damaged"); i += 4; break;
                default: throw new CrxException("CRX header is damaged");
            }
        }
        return result;
    }
}
