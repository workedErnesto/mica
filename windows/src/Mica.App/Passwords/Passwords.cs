using System.Text.Json;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.Web.WebView2.Core;
using Mica.Core;
using Mica.Design;
using Windows.ApplicationModel.DataTransfer;
using Windows.Security.Credentials.UI;
using Windows.Security.Cryptography;
using Windows.Security.Cryptography.DataProtection;

namespace Mica.App.Passwords;

/// <summary>The vault key protected by Windows DPAPI for the signed-in user (macOS keeps it in the Keychain). The
/// file format is the same AES-GCM vault; losing the key makes it unreadable and mica never replaces it silently.</summary>
public sealed class DpapiKeyStore(string path) : IVaultKeyStore
{
    public byte[]? Load()
    {
        if (!File.Exists(path)) return null;
        var provider = new DataProtectionProvider();
        var plain = provider.UnprotectAsync(CryptographicBuffer.CreateFromByteArray(File.ReadAllBytes(path))).AsTask().GetAwaiter().GetResult();
        CryptographicBuffer.CopyToByteArray(plain, out var key);
        return key;
    }

    public void Save(byte[] key)
    {
        var provider = new DataProtectionProvider("LOCAL=user");
        var sealedKey = provider.ProtectAsync(CryptographicBuffer.CreateFromByteArray(key)).AsTask().GetAwaiter().GetResult();
        CryptographicBuffer.CopyToByteArray(sealedKey, out var bytes);
        Persistence.WriteBytes(bytes, path);
    }
}

public sealed partial class PasswordManager(Store store)
{
    VaultStore? storage;
    public Vault Vault => storage?.Vault ?? new Vault();
    public string? Error { get; private set; }
    public bool Loading { get; private set; }
    public event Action? Changed;
    Task? loading;
    string VaultPath => Path.Combine(store.Root, "passwords.vault");
    string KeyPath => Path.Combine(store.Root, "passwords.key");

    public Task EnsureLoadedAsync()
    {
        if (storage is not null || Error is not null) return Task.CompletedTask;
        if (!File.Exists(VaultPath)) return Task.CompletedTask;
        return loading ??= Load();
    }

    async Task Load()
    {
        Loading = true; Changed?.Invoke();
        try { storage = await Task.Run(() => new VaultStore(VaultPath, new DpapiKeyStore(KeyPath))); }
        catch (Exception e) { Error = e.Message; }
        Loading = false; Changed?.Invoke();
    }

    public async void Update(Action<Vault> change)
    {
        await EnsureLoadedAsync();
        if (Error is not null) return;
        try
        {
            storage ??= await Task.Run(() => new VaultStore(VaultPath, new DpapiKeyStore(KeyPath)));
            storage.Update(change);
        }
        catch (Exception e) { Error = e.Message; }
        Changed?.Invoke();
    }

    /// <summary>Windows Hello (face, fingerprint or PIN) confirms the owner before a password is shown or copied.</summary>
    public async Task<bool> AuthenticateAsync(BrowserWindow? window)
    {
        var availability = await UserConsentVerifier.CheckAvailabilityAsync();
        if (availability != UserConsentVerifierAvailability.Available)
        {
            await Dialogs.Show(window, store.Text("для просмотра паролей включите Windows Hello или ПИН-код в параметрах windows, раздел «учётные записи», «варианты входа».", "Для просмотра паролей включите Windows Hello или ПИН-код в параметрах Windows, раздел «Учётные записи», «Варианты входа»."));
            return false;
        }
        var result = await UserConsentVerifier.RequestVerificationAsync(store.Text("подтвердите доступ к паролю", "Подтвердите доступ к паролю"));
        return result == UserConsentVerificationResult.Verified;
    }
}

/// <summary>Offers to save, fill and generate passwords (macOS PasswordBridge). WebView2 runs injected scripts in the
/// page's world, so every message is checked here: top-level document, HTTPS, sender origin equal to the address,
/// selected tab, normal window. Only standard forms of the main document are handled.</summary>
public sealed partial class PasswordBridge(Tab tab)
{
    bool presenting;

    public async Task InstallAsync(CoreWebView2 core) => await core.AddScriptToExecuteOnDocumentCreatedAsync(Script);

    public async void Received(CoreWebView2WebMessageReceivedEventArgs e)
    {
        if (tab.Owner is not { PrivateMode: false } owner || owner.SelectedId != tab.Id || tab.Core is not { } core) return;
        var origin = Origin.Of(e.Source);
        if (origin is null || !Origin.Secure(origin) || origin != Origin.Of(core.Source)) return;
        string json;
        try { json = e.WebMessageAsJson; } catch (ArgumentException) { return; }
        Dictionary<string, JsonElement>? body;
        try { body = JsonSerializer.Deserialize(json, PasswordJson.Default.DictionaryStringJsonElement); } catch (JsonException) { return; }
        if (body is null || !body.TryGetValue("micaPasswords", out var kind) || kind.ValueKind != JsonValueKind.String) return;
        var store = owner.Store; var manager = store.Passwords;
        await manager.EnsureLoadedAsync();
        if (manager.Error is not null || presenting) return;
        switch (kind.GetString())
        {
            case "focus":
            {
                var isNew = body.TryGetValue("new", out var n) && n.ValueKind == JsonValueKind.True;
                var max = body.TryGetValue("max", out var m) && m.TryGetInt32(out var v) ? v : -1;
                if (isNew && store.Preferences.OfferPasswords && (max < 0 || max >= 8))
                {
                    var password = PasswordGenerator.Strong(max > 0 ? max : null);
                    presenting = true;
                    var answer = await Dialogs.Ask(owner.Window, owner.Text("создать стойкий пароль?", "Создать стойкий пароль?"), password, [owner.Text("не сейчас", "Не сейчас"), owner.Text("использовать", "Использовать")], password: new PasswordCard(origin, Secret: password));
                    presenting = false;
                    if (answer == 1 && Origin.Of(core.Source) == origin) await Fill(core, null, password);
                }
                else if (!isNew && store.Preferences.FillPasswords)
                {
                    var matches = manager.Vault.Matches(origin);
                    if (matches.Count == 0) return;
                    presenting = true;
                    var index = await DialogChoices.Choose(owner.Window, owner.Text("заполнить учётную запись?", "Заполнить учётную запись?"), origin,
                        matches.Select(l => l.Username).ToList(), owner.Text("заполнить", "Заполнить"), owner.Text("не сейчас", "Не сейчас"), new PasswordCard(origin));
                    presenting = false;
                    if (index < 0 || Origin.Of(core.Source) != origin) return;
                    var login = matches[index];
                    await Fill(core, login.Username, login.Password);
                    manager.Update(vault => { if (vault.Logins.FirstOrDefault(l => l.Id == login.Id) is { } item) item.Used = DateTimeOffset.Now; });
                }
                break;
            }
            case "submit":
            {
                if (!store.Preferences.OfferPasswords || !body.TryGetValue("password", out var p) || p.GetString() is not { Length: > 0 } password) return;
                var username = body.TryGetValue("username", out var u) ? u.GetString() ?? "" : "";
                var capture = manager.Vault.Capture(origin, username, password);
                if (capture.Kind is CaptureKind.Known or CaptureKind.Blocked) return;
                // A form submission alone does not prove the sign-in worked.
                await Task.Delay(1000);
                if (owner.SelectedId != tab.Id || presenting) return;
                presenting = true;
                var answer = await Dialogs.Ask(owner.Window, owner.Text("сохранить пароль?", "Сохранить пароль?"), origin + (username.Length == 0 ? "" : "\n" + username), [owner.Text("не сейчас", "Не сейчас"), owner.Text("никогда для этого сайта", "Никогда для этого сайта"), owner.Text("сохранить", "Сохранить")], password: new PasswordCard(origin, Account: username));
                presenting = false;
                if (answer == 2) manager.Update(v => v.Save(origin, username, password));
                else if (answer == 1) manager.Update(v => { if (!v.Never.Contains(origin)) v.Never.Add(origin); });
                break;
            }
        }
    }

    static async Task Fill(CoreWebView2 core, string? username, string password) =>
        await core.ExecuteScriptAsync($"globalThis.micaFill && globalThis.micaFill({(username is null ? "null" : Tab.Json(username))}, {Tab.Json(password)})");

    const string Script = """
    (() => {
      if (window.top !== window || !window.chrome || !window.chrome.webview) return;
      let target = null;
      const send = value => window.chrome.webview.postMessage(Object.assign({ micaPasswords: value.type }, value));
      const fields = form => Array.from((form || document).querySelectorAll('input'));
      const userField = form => fields(form).find(x => /^(username|email)$/i.test(x.autocomplete)) || fields(form).find(x => /^(text|email)$/i.test(x.type));
      document.addEventListener('focusin', e => {
        const x = e.target;
        if (!e.isTrusted || !(x instanceof HTMLInputElement) || x.disabled || x.readOnly) return;
        const pass = x.type === 'password' ? x : (x.form && userField(x.form) === x ? fields(x.form).find(i => i.type === 'password' && i.autocomplete !== 'new-password') : null);
        if (!pass || pass.disabled || pass.readOnly) return;
        target = pass;
        send({ type: 'focus', new: pass.autocomplete === 'new-password', max: pass.maxLength });
      }, true);
      document.addEventListener('submit', e => {
        if (!e.isTrusted || !(e.target instanceof HTMLFormElement)) return;
        const inputs = fields(e.target), newPasswords = inputs.filter(x => x.type === 'password' && x.value && x.autocomplete === 'new-password');
        if (newPasswords.some(x => x.value !== newPasswords[0].value)) return;
        const pass = newPasswords[0] || inputs.find(x => x.type === 'password' && x.value);
        if (!pass) return;
        const user = userField(e.target);
        send({ type: 'submit', username: user ? user.value : '', password: pass.value });
      }, true);
      Object.defineProperty(globalThis, 'micaFill', { value: (username, password) => {
        if (!target || !target.isConnected || target.type !== 'password' || target.disabled || target.readOnly) return false;
        const set = (el, value) => { Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(el, value); el.dispatchEvent(new Event('input', { bubbles: true })); el.dispatchEvent(new Event('change', { bubbles: true })); };
        const user = target.form ? userField(target.form) : null;
        if (username !== null && user && !user.disabled && !user.readOnly) set(user, username);
        set(target, password);
        if (target.autocomplete === 'new-password' && target.form) for (const other of fields(target.form)) if (other !== target && other.type === 'password' && other.autocomplete === 'new-password' && !other.value && !other.disabled && !other.readOnly) set(other, password);
        return true;
      } });
    })();
    """;
}

[System.Text.Json.Serialization.JsonSerializable(typeof(Dictionary<string, JsonElement>))]
internal sealed partial class PasswordJson : System.Text.Json.Serialization.JsonSerializerContext;
