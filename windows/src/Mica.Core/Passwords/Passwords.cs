using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace Mica.Core;

/// <summary>One saved sign-in. Origin is scheme, host and a non-default port, as <see cref="Mica.Core.Origin"/> builds it.</summary>
public sealed class SavedLogin
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Origin { get; set; } = "";
    public string Username { get; set; } = "";
    public string Password { get; set; } = "";
    public DateTimeOffset Created { get; set; } = DateTimeOffset.Now;
    public DateTimeOffset Updated { get; set; } = DateTimeOffset.Now;
    public DateTimeOffset? Used { get; set; }
    public string Host => AddressParser.Host(Origin) ?? Origin;
}

public enum CaptureKind { New, Changed, Known, Blocked }

/// <summary>Everything the password store keeps. Encrypted as one blob, so the file reveals neither sites nor names.</summary>
public sealed class Vault
{
    public int Version { get; set; } = 1;
    public List<SavedLogin> Logins { get; set; } = [];
    /// <summary>Origins where the user chose "never for this site".</summary>
    public List<string> Never { get; set; } = [];

    public (CaptureKind Kind, SavedLogin? Existing) Capture(string origin, string username, string password)
    {
        if (Never.Contains(origin)) return (CaptureKind.Blocked, null);
        var existing = Logins.FirstOrDefault(l => l.Origin == origin && l.Username == username);
        if (existing is null) return (CaptureKind.New, null);
        return (existing.Password == password ? CaptureKind.Known : CaptureKind.Changed, existing);
    }

    /// <summary>Only the exact origin may receive a saved credential.</summary>
    public List<SavedLogin> Matches(string origin)
    {
        var canonical = Core.Origin.Of(origin);
        if (canonical is null || canonical != origin) return [];
        return Logins.Where(l => l.Origin == canonical).OrderByDescending(l => l.Used ?? l.Updated).ToList();
    }

    public SavedLogin Save(string origin, string username, string password, DateTimeOffset? now = null)
    {
        var time = now ?? DateTimeOffset.Now;
        var existing = Logins.FirstOrDefault(l => l.Origin == origin && l.Username == username);
        if (existing is not null) { existing.Password = password; existing.Updated = time; return existing; }
        var login = new SavedLogin { Origin = origin, Username = username, Password = password, Created = time, Updated = time };
        Logins.Add(login);
        return login;
    }

    public Vault Clone() => JsonSerializer.Deserialize(JsonSerializer.SerializeToUtf8Bytes(this, MicaJson.Info<Vault>()), MicaJson.Info<Vault>())!;
}

/// <summary>File layout shared with macOS: "MICAPW1", then nonce (12), cipher text, tag (16), as AES.GCM.SealedBox.combined.</summary>
public static class VaultCrypto
{
    static readonly byte[] Magic = Encoding.ASCII.GetBytes("MICAPW1");

    public static byte[] NewKey() => RandomNumberGenerator.GetBytes(32);

    public static byte[] Seal(Vault vault, byte[] key)
    {
        var plain = JsonSerializer.SerializeToUtf8Bytes(vault, MicaJson.Info<Vault>());
        var nonce = RandomNumberGenerator.GetBytes(12);
        var cipher = new byte[plain.Length];
        var tag = new byte[16];
        using (var aes = new AesGcm(key, 16)) aes.Encrypt(nonce, plain, cipher, tag);
        CryptographicOperations.ZeroMemory(plain);
        return [.. Magic, .. nonce, .. cipher, .. tag];
    }

    public static Vault Open(byte[] data, byte[] key)
    {
        if (data.Length < Magic.Length + 28 || !data.AsSpan(0, Magic.Length).SequenceEqual(Magic)) throw new CryptographicException("vault damaged");
        var body = data.AsSpan(Magic.Length);
        var nonce = body[..12];
        var tag = body[^16..];
        var cipher = body[12..^16];
        var plain = new byte[cipher.Length];
        using (var aes = new AesGcm(key, 16)) aes.Decrypt(nonce, cipher, tag, plain);
        var vault = JsonSerializer.Deserialize(plain, MicaJson.Info<Vault>()) ?? throw new CryptographicException("vault damaged");
        CryptographicOperations.ZeroMemory(plain);
        if (vault.Version != 1) throw new CryptographicException("vault damaged");
        return vault;
    }
}

/// <summary>Where the 32-byte vault key lives. Windows protects it with DPAPI for the signed-in user; tests use memory.</summary>
public interface IVaultKeyStore
{
    byte[]? Load();
    void Save(byte[] key);
}

/// <summary>An encrypted vault. A missing key for an existing file is an error, never a new empty vault.</summary>
public sealed class VaultStore
{
    public string Path { get; }
    readonly byte[] key;
    public Vault Vault { get; private set; }

    public VaultStore(string path, IVaultKeyStore keys)
    {
        Path = path;
        var exists = File.Exists(path);
        var stored = keys.Load();
        if (stored is null)
        {
            if (exists) throw new InvalidOperationException("missing key");
            stored = VaultCrypto.NewKey();
            keys.Save(stored);
        }
        if (stored.Length != 32) throw new InvalidOperationException("invalid key");
        key = stored;
        Vault = exists ? VaultCrypto.Open(File.ReadAllBytes(path), key) : new Vault();
    }

    /// <summary>The in-memory value changes only after the encrypted file is written successfully.</summary>
    public void Update(Action<Vault> change)
    {
        var next = Vault.Clone();
        change(next);
        Persistence.WriteBytes(VaultCrypto.Seal(next, key), Path);
        Vault = next;
    }
}

/// <summary>Three groups of six letters and digits joined by hyphens, with a capital and a digit. About 71 bits.</summary>
public static class PasswordGenerator
{
    const string Lower = "abcdefghijkmnopqrstuvwxyz", Upper = "ABCDEFGHJKLMNPQRSTUVWXYZ", Digits = "23456789";

    static char Pick(string set) => set[RandomNumberGenerator.GetInt32(set.Length)];

    static int[] Shuffled(int count)
    {
        var slots = Enumerable.Range(0, count).ToArray();
        RandomNumberGenerator.Shuffle(slots.AsSpan());
        return slots;
    }

    public static string Strong(int? maxLength = null)
    {
        if (maxLength is > 0 and < 20)
        {
            var length = maxLength.Value;
            var all = Lower + Upper + Digits;
            var chars = Enumerable.Range(0, length).Select(_ => Pick(all)).ToArray();
            var slots = new Stack<int>(Shuffled(length));
            if (slots.Count > 0) chars[slots.Pop()] = Pick(Upper);
            if (slots.Count > 0) chars[slots.Pop()] = Pick(Digits);
            if (slots.Count > 0) chars[slots.Pop()] = Pick(Lower);
            return new string(chars);
        }
        var grouped = Enumerable.Range(0, 18).Select(_ => Pick(Lower)).ToArray();
        var positions = new Stack<int>(Shuffled(18));
        grouped[positions.Pop()] = Pick(Upper);
        grouped[positions.Pop()] = Pick(Digits);
        var text = new string(grouped);
        return text[..6] + "-" + text[6..12] + "-" + text[12..];
    }
}
