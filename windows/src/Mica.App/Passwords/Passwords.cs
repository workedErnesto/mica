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

/// <summary>The password offer beside a sign-in field of the selected page, as the shell draws it. <see cref="Frame"/> is
/// in window DIPs; <see cref="Page"/> is the page's rectangle, where a click dismisses the offer.</summary>
public sealed record OfferView(Guid Tab, string Origin, PasswordOffer Offer, string Password, OfferRect Frame, OfferEdge Edge, OfferRect Page, int? Selected);

/// <summary>Offers to fill and generate passwords beside the focused field, and to save them after a sign-in (macOS
/// PasswordBridge). WebView2 runs injected scripts in the page's world, so every message is checked here: top-level
/// document, HTTPS, sender origin equal to the address, selected tab, normal window. Only standard forms of the main
/// document are handled. "Not now" for the offer lasts for one focus of the field (PasswordOfferSession); "save
/// password?" after a form was sent stays a card, since the field it would point at is usually gone with the next page.</summary>
public sealed partial class PasswordBridge(Tab tab)
{
    bool presenting;
    readonly PasswordOfferSession session = new();
    Current? current;
    /// <summary>The field the page script was told the offer is showing for; it forwards moves and keys only then.</summary>
    int? scriptField;

    /// <summary>What is offered for the focused field and where the field is, in the page's CSS pixels.</summary>
    sealed class Current
    {
        public required int Field;
        public required string Origin;
        public required PasswordOffer Offer;
        public required string Password;
        public OfferRect Rect;
        public double InnerWidth;
        public int? Selected;
    }

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
        int? id = body.TryGetValue("id", out var idValue) && idValue.ValueKind == JsonValueKind.Number && idValue.TryGetInt32(out var number) ? number : null;
        var store = owner.Store; var manager = store.Passwords;
        switch (kind.GetString())
        {
            case "focus":
            {
                if (id is not { } field || Geometry(body) is not { } geometry) return;
                session.Apply(PasswordOfferEvent.Focus, field);
                // The vault opens on first use; the field may have lost focus by the time it is ready.
                await manager.EnsureLoadedAsync();
                if (session.Field != field || manager.Error is not null || presenting) return;
                var isNew = body.TryGetValue("new", out var n) && n.ValueKind == JsonValueKind.True;
                var max = body.TryGetValue("max", out var m) && m.TryGetInt32(out var v) ? v : -1;
                var offer = PasswordOffer.Decide(manager.Vault, origin, isNew, max, store.Preferences.OfferPasswords, store.Preferences.FillPasswords);
                if (offer is null) { current = null; Render(); return; }
                // The same focus keeps its generated password while the offer follows the field.
                var password = current is { } same && same.Field == field && same.Offer.SameAs(offer) ? same.Password
                    : offer.Kind == PasswordOfferKind.Generate ? PasswordGenerator.Strong(max > 0 ? max : null) : "";
                current = new Current { Field = field, Origin = origin, Offer = offer, Password = password, Rect = geometry.Rect, InnerWidth = geometry.InnerWidth };
                Render();
                break;
            }
            case "move":
                if (id is not { } moved || current is not { } c || c.Field != moved || Geometry(body) is not { } g) return;
                c.Rect = g.Rect; c.InnerWidth = g.InnerWidth;
                Render();
                break;
            case "click":
                if (id is not { } clicked) return;
                session.Apply(PasswordOfferEvent.Click, clicked);
                if (current is { } cc && cc.Field == clicked && Geometry(body) is { } cg) { cc.Rect = cg.Rect; cc.InnerWidth = cg.InnerWidth; }
                Render();
                break;
            case "input":
                if (id is { } typed) { session.Apply(PasswordOfferEvent.Input, typed); Render(); }
                break;
            case "blur":
                if (id is { } left) { session.Apply(PasswordOfferEvent.Blur, left); Render(); }
                break;
            case "key":
                if (id is not { } keyed || keyed != session.Field || !session.Visible || current is not { } k || !body.TryGetValue("key", out var key)) return;
                var count = Choices(k.Offer);
                switch (key.GetString())
                {
                    case "Escape": Choose(-1); break;
                    case "ArrowDown": k.Selected = k.Selected is { } down ? (down + 1) % count : 0; Render(); break;
                    case "ArrowUp": k.Selected = k.Selected is { } up ? (up - 1 + count) % count : count - 1; Render(); break;
                    // The script runs in the page's own world here, so the page could post this message itself and
                    // have a saved password filled without the person; Return must really be held down.
                    case "Enter": if (k.Selected is { } chosen && Win32.IsDown(0x0D)) Choose(chosen); break;
                }
                break;
            case "submit":
            {
                await manager.EnsureLoadedAsync();
                if (manager.Error is not null || presenting) return;
                if (!store.Preferences.OfferPasswords || !body.TryGetValue("password", out var p) || p.GetString() is not { Length: > 0 } password) return;
                var username = body.TryGetValue("username", out var u) ? u.GetString() ?? "" : "";
                var capture = manager.Vault.Capture(origin, username, password);
                if (capture.Kind is CaptureKind.Known or CaptureKind.Blocked) return;
                Leave();
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

    /// <summary>The tab shows another document or goes away: whatever was offered belonged to the old one.</summary>
    public void Leave()
    {
        session.Apply(PasswordOfferEvent.Leave);
        current = null;
        Render();
    }

    /// <summary>A choice in the shell: a row index (accounts, or the generated password then "never for this site"), or
    /// -1 for "not now" (Esc, a click on the page).</summary>
    public async void Choose(int index)
    {
        if (current is not { } c || tab.Owner is not { } owner || tab.Core is not { } core || Origin.Of(core.Source) != c.Origin) return;
        var manager = owner.Store.Passwords;
        if (index < 0) session.Apply(PasswordOfferEvent.Dismiss);
        else if (c.Offer.Kind == PasswordOfferKind.Fill && index < c.Offer.Logins.Count)
        {
            var login = c.Offer.Logins[index];
            session.Apply(PasswordOfferEvent.Accept);
            Render();
            await Fill(core, login.Username, login.Password);
            manager.Update(vault => { if (vault.Logins.FirstOrDefault(l => l.Id == login.Id) is { } item) item.Used = DateTimeOffset.Now; });
            return;
        }
        else if (c.Offer.Kind == PasswordOfferKind.Generate && index == 0)
        {
            session.Apply(PasswordOfferEvent.Accept);
            Render();
            await Fill(core, null, c.Password);
            return;
        }
        else if (c.Offer.Kind == PasswordOfferKind.Generate && index == 1)
        {
            session.Apply(PasswordOfferEvent.Dismiss);
            var origin = c.Origin;
            manager.Update(v => { if (!v.Never.Contains(origin)) v.Never.Add(origin); });
        }
        Render();
    }

    static int Choices(PasswordOffer offer) => offer.Kind == PasswordOfferKind.Fill ? offer.Logins.Count : 2;

    /// <summary>The offer's height for these rows: padding, caption, rows up to <see cref="PasswordOffer.VisibleRows"/>, footer.</summary>
    public static double Height(PasswordOffer offer) => offer.Kind == PasswordOfferKind.Fill
        ? 2 * Radius.PanelPadding + Chrome.OfferHeader + Math.Min(offer.Logins.Count, PasswordOffer.VisibleRows) * Chrome.OfferRow
        : 2 * Radius.PanelPadding + Chrome.OfferHeader + Chrome.OfferRow + Chrome.OfferFooter;

    readonly record struct FieldGeometry(OfferRect Rect, double InnerWidth);

    static FieldGeometry? Geometry(Dictionary<string, JsonElement> body)
    {
        if (!body.TryGetValue("rect", out var r) || r.ValueKind != JsonValueKind.Array || r.GetArrayLength() != 4) return null;
        if (!body.TryGetValue("vw", out var vw) || vw.ValueKind != JsonValueKind.Number || vw.GetDouble() <= 0) return null;
        var values = r.EnumerateArray().Select(x => x.ValueKind == JsonValueKind.Number ? x.GetDouble() : double.NaN).ToArray();
        if (values.Any(x => !double.IsFinite(x)) || values[2] < 0 || values[3] < 0) return null;
        return new FieldGeometry(new OfferRect(values[0], values[1], values[2], values[3]), vw.GetDouble());
    }

    /// <summary>Publishes the offer to the window for the shell, or takes it away. While it is out the shell sits above
    /// the page, so the page keeps the keyboard and only the offer and a click on the page (dismiss) take the mouse.</summary>
    void Render()
    {
        if (tab.Owner is not { } owner) return;
        OfferView? view = null;
        var active = false;
        if (current is { } c && session.Visible && session.Field == c.Field && owner.SelectedId == tab.Id && tab.Core is { } core && Origin.Of(core.Source) == c.Origin
            && tab.WebView is { ActualWidth: > 0 } web && owner.Window?.PageRect is { } page)
        {
            active = true;
            var field = PasswordOfferPlacement.ViewRect(c.Rect, c.InnerWidth, web.ActualWidth);
            // A field scrolled out of the page hides the offer until it is back; the offer itself stays.
            if (PasswordOfferPlacement.Place(field, web.ActualWidth, web.ActualHeight, Chrome.OfferWidth, Height(c.Offer), Chrome.OfferGap, Radius.Gutter) is { } placed)
            {
                var frame = placed.Frame with { X = placed.Frame.X + page.X, Y = placed.Frame.Y + page.Y };
                view = new OfferView(tab.Id, c.Origin, c.Offer, c.Password, frame, placed.Edge, new OfferRect(page.X, page.Y, page.Width, page.Height), c.Selected);
            }
        }
        if (view is not null || owner.PasswordOffer?.Tab == tab.Id) owner.PasswordOffer = view;
        SetScript(active ? current!.Field : null);
    }

    async void SetScript(int? field)
    {
        if (field == scriptField || tab.Core is not { } core) return;
        var previous = scriptField;
        scriptField = field;
        var (id, on) = field is { } shown ? (shown, "true") : (previous ?? 0, "false");
        try { await core.ExecuteScriptAsync($"globalThis.micaOfferActive && globalThis.micaOfferActive({id}, {on})"); }
        catch (Exception) { }
    }

    static async Task Fill(CoreWebView2 core, string? username, string password) =>
        await core.ExecuteScriptAsync($"globalThis.micaFill && globalThis.micaFill({(username is null ? "null" : Tab.Json(username))}, {Tab.Json(password)})");

    /// <summary>Same script as macOS PasswordBridge, posting through chrome.webview. Rectangles are in CSS pixels of the
    /// visual viewport, with vw the layout viewport width, so the host scales them to DIPs under any zoom.</summary>
    const string Script = """
    (() => {
      if (window.top !== window || !window.chrome || !window.chrome.webview) return;
      let target = null, focused = null, field = 0, sequence = 0, active = false, armed = false, typed = false, frame = 0;
      const send = value => window.chrome.webview.postMessage(Object.assign({ micaPasswords: value.type }, value));
      const fields = form => Array.from((form || document).querySelectorAll('input'));
      const userField = form => fields(form).find(x => /^(username|email)$/i.test(x.autocomplete)) || fields(form).find(x => /^(text|email)$/i.test(x.type));
      const passwordFor = x => x.type === 'password' ? x : (x.form && userField(x.form) === x ? fields(x.form).find(i => i.type === 'password' && i.autocomplete !== 'new-password') : null);
      const geometry = () => {
        const r = focused.getBoundingClientRect(), v = window.visualViewport, scale = v ? v.scale : 1, left = v ? v.offsetLeft : 0, top = v ? v.offsetTop : 0;
        return { rect: [(r.left - left) * scale, (r.top - top) * scale, r.width * scale, r.height * scale], vw: window.innerWidth };
      };
      const move = () => {
        if (!active || !focused || frame) return;
        frame = requestAnimationFrame(() => { frame = 0; if (active && focused && focused.isConnected) send(Object.assign({ type: 'move', id: field }, geometry())); });
      };
      const sized = new ResizeObserver(move);
      document.addEventListener('focusin', e => {
        const x = e.target;
        if (!e.isTrusted || !(x instanceof HTMLInputElement) || x.disabled || x.readOnly) return;
        const pass = passwordFor(x);
        if (!pass || pass.disabled || pass.readOnly) return;
        // The page getting the keyboard back refocuses the same field without a blur first: still the same focus.
        if (x === focused) return;
        if (focused) sized.unobserve(focused);
        target = pass; focused = x; field = ++sequence; active = false; armed = false; typed = false;
        sized.observe(x);
        send(Object.assign({ type: 'focus', id: field, new: pass.autocomplete === 'new-password', max: pass.maxLength }, geometry()));
      }, true);
      document.addEventListener('focusout', e => {
        if (!e.isTrusted || e.target !== focused) return;
        const id = field, was = focused;
        // The page losing the keyboard (a click on the offer in the shell) keeps the field active; a real blur ends it.
        setTimeout(() => {
          if (document.activeElement === was || id !== field) return;
          sized.unobserve(was); focused = null; active = false; armed = false;
          send({ type: 'blur', id });
        }, 0);
      }, true);
      document.addEventListener('click', e => { if (e.isTrusted && focused && e.target === focused) { typed = false; send(Object.assign({ type: 'click', id: field }, geometry())); } }, true);
      // Typing hides the offer for this focus; the host hears it once, not for every key.
      document.addEventListener('input', e => { if (e.isTrusted && focused && e.target === focused && !typed) { typed = true; active = false; armed = false; send({ type: 'input', id: field }); } }, true);
      document.addEventListener('keydown', e => {
        if (!e.isTrusted || !active || !focused || e.target !== focused || e.isComposing) return;
        const stop = () => { e.preventDefault(); e.stopImmediatePropagation(); };
        if (e.key === 'Escape') { stop(); active = false; armed = false; send({ type: 'key', id: field, key: 'Escape' }); }
        else if (e.key === 'ArrowDown' || e.key === 'ArrowUp') { stop(); armed = true; send({ type: 'key', id: field, key: e.key }); }
        else if (e.key === 'Enter' && armed) { stop(); armed = false; send({ type: 'key', id: field, key: 'Enter' }); }
      }, true);
      document.addEventListener('scroll', move, { capture: true, passive: true });
      window.addEventListener('resize', move, { passive: true });
      if (window.visualViewport) { visualViewport.addEventListener('scroll', move, { passive: true }); visualViewport.addEventListener('resize', move, { passive: true }); }
      window.addEventListener('pagehide', () => { if (focused) { active = false; send({ type: 'blur', id: field }); } }, true);
      document.addEventListener('submit', e => {
        if (!e.isTrusted || !(e.target instanceof HTMLFormElement)) return;
        const inputs = fields(e.target), newPasswords = inputs.filter(x => x.type === 'password' && x.value && x.autocomplete === 'new-password');
        if (newPasswords.some(x => x.value !== newPasswords[0].value)) return;
        const pass = newPasswords[0] || inputs.find(x => x.type === 'password' && x.value);
        if (!pass) return;
        const user = userField(e.target);
        send({ type: 'submit', username: user ? user.value : '', password: pass.value });
      }, true);
      Object.defineProperty(globalThis, 'micaOfferActive', { value: (id, on) => { if (id === field) { active = on; if (!on) armed = false; else move(); } return active; } });
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
