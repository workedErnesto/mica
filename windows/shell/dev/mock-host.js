// Development stand-in for the native host, used only when the shell is opened outside WebView2 (the assistant's
// preview pane). It keeps a fake window state and answers the same commands as Mica.App's ShellBridge, so layouts,
// animations and themes can be checked without Windows. It never ships as a feature: the host ignores this file.

const id = () => Math.random().toString(36).slice(2, 10);
const now = Date.now();

function tab(url, title, extra) {
  const host = url ? new URL(url).hostname : null;
  return { id: id(), url, title: title || '', host, start: !url, pinned: false, loading: false, progress: 0, phase: url ? 'live' : 'fresh', canBack: !!url, canForward: false, secure: !!url && url.startsWith('https'), canSave: !!url, pinnable: !!url, address: url ? parts(url) : null, icon: null, ...extra };
}

function parts(url) {
  const u = new URL(url), host = u.hostname.replace(/^www\./, '');
  const labels = host.split('.');
  const domain = labels.slice(-2).join('.');
  const sub = labels.slice(0, -2).join('.');
  return sub ? [{ text: sub + '.', dim: true }, { text: domain, dim: false }] : [{ text: domain, dim: false }];
}

const profiles = [
  { id: 'p1', name: 'основной', icon: 'person', background: '#8D7B6A', lightGlyph: true, standard: true, open: true, glyph: 'auto' },
  { id: 'p2', name: 'работа', icon: 'briefcase', background: '#3E7BFA', lightGlyph: true, standard: false, open: false, glyph: 'auto' },
];

export class MockHost {
  constructor() {
    const params = new URLSearchParams(location.search);
    const tabs = [tab(null), tab('https://www.wikipedia.org/', 'Wikipedia'), tab('https://github.com/WebKit/WebKit', 'GitHub: WebKit'), tab('https://news.ycombinator.com/', 'Hacker News')];
    tabs[2].pinned = true;
    this.state = {
      system: { captionInset: 138, captionHeight: 48, reducedMotion: params.has('reduced') },
      window: { isPrivate: params.has('private'), fullScreen: false },
      appearance: { dark: params.get('theme') === 'dark', contrast: false, glass: true, shellAlpha: 0.92 - 0.55 * 0.72, startAlpha: 1 - 0.55 * 0.55, accent: null, onAccent: '#fff', accentTint: 0.3 },
      text: { language: params.get('lang') || 'ru', lowercase: !params.has('regular') },
      profile: profiles[0], profiles, profileLimit: 24,
      prefs: {
        layout: params.get('layout') || 'left', theme: 'system', customBase: 'system', accent: '#6E56CF', customTint: 0.3, frosted: true, transparency: 0.55,
        userName: params.get('name') || '', greetByName: true, sidebarCollapsed: params.has('collapsed'), sidebarWidth: 248,
        toolbar: { leading: ['sidebar', 'back', 'forward', 'reload'], leadingInner: [], trailingInner: ['save'], trailing: [], sidebar: ['profile', 'bookmarks', 'history', 'downloads', 'extensions', 'incognito', 'settings'], addressWidth: 560 },
        address: { full: false, dimSubdomain: false, dimPath: false },
        start: { wordmark: true, sections: ['custom', 'frequent'], frequentCount: 8, shortcuts: [{ id: 's1', title: 'GitHub', url: 'https://github.com/', host: 'github.com' }, { id: 's2', title: '', url: 'https://news.ycombinator.com/', host: 'news.ycombinator.com' }], hiddenHosts: [] },
        language: 'ru', lowercase: true,
      },
      toolbarIsDefault: true,
      tabs, selectedId: tabs[0].id, closedCount: 1, panel: params.get('panel'), saving: null,
      overlay: { commandBar: false, find: false, settings: params.has('settings'), onboarding: params.has('onboarding'), onboardingStep: 0, clearData: false, profilePrompt: null, alert: null, customizingToolbar: false, customizingStart: false, quitHold: null },
      start: { greeting: null, searchTitle: 'DuckDuckGo', isDefault: true, sections: [] },
      site: null, findResult: null, clearData: null,
      library: {},
      settings: null,
    };
    if (params.get('select') === 'site') this.state.selectedId = tabs[1].id;
    this.refreshStart(); this.refreshLibrary(); this.refreshSettings();
  }
  attach(receive) {
    this.deliver = receive;
    // A desktop for the glass to show, as DesktopAcrylic shows the wallpaper on Windows.
    document.documentElement.style.background = 'radial-gradient(circle at 20% 30%, #c9a27a, transparent 45%), radial-gradient(circle at 80% 70%, #5f7fa8, transparent 50%), linear-gradient(135deg, #6b7a8f, #b7a48f)';
    document.body.style.backdropFilter = 'blur(40px) saturate(1.2)';
    // The host draws the site's WebView2 in the hole; here a white sheet stands in for it.
    const style = document.createElement('style');
    // Windows draws its caption buttons over the right end of the first row; the shell leaves that room to them.
    const caption = document.createElement('div');
    caption.setAttribute('aria-hidden', 'true');
    caption.style.cssText = 'position:fixed;top:0;right:0;width:138px;height:48px;display:flex;z-index:2000;pointer-events:none;font:300 15px "Segoe Fluent Icons",system-ui;color:var(--ink)';
    caption.innerHTML = ['–', '□', '✕'].map(c => `<span style="flex:1;display:flex;align-items:center;justify-content:center">${c}</span>`).join('');
    document.body.appendChild(caption);
    style.textContent = '.page-hole{background:#fff;display:flex;align-items:center;justify-content:center;color:#999;font:13px system-ui}.page-hole::after{content:"web page (WebView2)"}';
    document.head.appendChild(style);
    setTimeout(() => this.push(), 0);
  }
  push() { this.deliver({ type: 'state', state: JSON.parse(JSON.stringify(this.state)) }); }
  event(name, args) { this.deliver({ type: 'event', name, args }); }
  reply(id, result) { setTimeout(() => this.deliver({ type: 'reply', id, result }), 30); }

  refreshStart() {
    const s = this.state, start = s.prefs.start;
    s.start.greeting = s.prefs.userName && s.prefs.greetByName ? (s.text.lowercase ? 'добрый день, ' : 'Добрый день, ') + s.prefs.userName : null;
    s.start.sections = [
      { section: 'custom', sites: start.shortcuts.slice(0, start.frequentCount).map(sc => ({ id: sc.id, title: sc.title, url: sc.url, host: sc.host, shortcut: sc.id })) },
      { section: 'frequent', sites: s.window.isPrivate ? [] : ['wikipedia.org', 'youtube.com', 'mail.google.com', 'apple.com', 'vercel.com'].filter(h => !start.hiddenHosts.includes(h)).slice(0, start.frequentCount).map(h => ({ id: 'f-' + h, title: '', url: 'https://' + h + '/', host: h })) },
      { section: 'bookmarks', sites: [] },
    ];
  }
  refreshLibrary() {
    const day = 86400000;
    this.state.library = {
      history: [
        { id: 'h1', url: 'https://www.wikipedia.org/', title: 'Wikipedia', host: 'www.wikipedia.org', time: now - 600000, profile: 'p1' },
        { id: 'h2', url: 'https://github.com/WebKit/WebKit', title: 'GitHub: WebKit', host: 'github.com', time: now - 3600000, profile: 'p2' },
        { id: 'h3', url: 'https://news.ycombinator.com/', title: 'Hacker News', host: 'news.ycombinator.com', time: now - day - 4000, profile: 'p1' },
        { id: 'h4', url: 'https://developer.apple.com/documentation/webkit', title: 'WebKit documentation', host: 'developer.apple.com', time: now - 3 * day, profile: 'p1' },
      ],
      bookmarks: [{ id: 'b1', url: 'https://github.com/', title: 'GitHub', host: 'github.com' }],
      downloads: [
        { id: 'd1', name: 'report-2026.pdf', kind: 'document', ext: 'pdf', state: 'running', active: true, bytes: 1200000, total: 5000000, fraction: 0.24, time: now - 5000 },
        { id: 'd2', name: 'photo.png', kind: 'image', ext: 'png', state: 'complete', active: false, size: 820000, time: now - 200000, folder: this.state.text.lowercase ? 'загрузки' : 'Загрузки', source: 'https://example.com/photo.png' },
        { id: 'd3', name: 'archive.zip', kind: 'archive', ext: 'zip', state: 'failed', active: false, failure: 'Сеть недоступна', time: now - 2 * day },
      ],
      extensions: { records: [{ id: 'e1', name: 'uBlock Origin Lite', version: '2025.1', enabled: true, source: 'cws:ddkjiahejlhfcafbddmgiahcphecmpfh', permissions: ['declarativeNetRequest', 'storage'], hosts: [] }], status: '', busy: false },
    };
  }
  refreshSettings() {
    const s = this.state;
    s.settings = {
      section: (s.settings && s.settings.section) || new URLSearchParams(location.search).get('section') || 'space',
      isDefault: false, addressSample: [{ text: 'shop.', dim: s.prefs.address.dimSubdomain }, { text: 'example.com', dim: false }].concat(s.prefs.address.full ? [{ text: '/shoes/running?size=42', dim: s.prefs.address.dimPath }] : []),
      engines: [['duckDuckGo', 'DuckDuckGo', 'duckduckgo.com'], ['google', 'Google', 'google.com'], ['yandex', 'Яндекс', 'ya.ru'], ['kagi', 'Kagi', 'kagi.com'], ['bing', 'Bing', 'bing.com']].map(([id, title, host]) => ({ id, title, host })),
      search: 'duckDuckGo', blocking: true, blockerCount: 3512, blockerStatus: '', blockerUpdating: false, blockingExceptions: [],
      restore: true, lazyRestore: true, eagerHosts: [], notificationRequests: true, permissions: [{ origin: 'https://meet.example.com', capability: 'camera', decision: 'allow' }],
      offerPasswords: true, fillPasswords: true, passwords: { logins: [{ id: 'l1', origin: 'https://github.com', username: 'whoa' }], never: [] },
      importer: { browsers: [{ id: 'chrome', name: 'Google Chrome', profiles: [{ path: 'Default', name: 'Default' }], selected: 'Default' }, { id: 'edge', name: 'Microsoft Edge', profiles: [{ path: 'Default', name: 'Default' }, { path: 'Profile 1', name: 'Work' }], selected: 'Default' }] },
      version: '0.3.0', engine: '142.0.3595.0', updateChecks: true, profileOpening: 'ask', editingProfile: s.profile.id,
      appIcons: [],
    };
  }
  selected() { return this.state.tabs.find(t => t.id === this.state.selectedId); }

  receive(message) {
    const s = this.state, a = message.args || {};
    const done = () => { this.refreshStart(); this.refreshSettings(); this.push(); };
    switch (message.name) {
      case 'shell.hello': case 'shell.ready': case 'layout': case 'settings.draft': return;
      case 'key': return this.receive({ name: 'command', args: { name: a.command } });
      case 'tab.new': { const t = tab(null); s.tabs.push(t); s.selectedId = t.id; return done(); }
      case 'tab.select': s.selectedId = a.id; return done();
      case 'tab.close': {
        const index = s.tabs.findIndex(t => t.id === a.id); if (index < 0) return;
        s.tabs.splice(index, 1); s.closedCount++;
        if (!s.tabs.length) s.tabs.push(tab(null));
        if (s.selectedId === a.id) s.selectedId = s.tabs[Math.min(index, s.tabs.length - 1)].id;
        return done();
      }
      case 'tab.move': { const from = s.tabs.findIndex(t => t.id === a.id); const moving = s.tabs.splice(from, 1)[0]; const to = s.tabs.findIndex(t => t.id === a.before); s.tabs.splice(to, 0, moving); return done(); }
      case 'tab.pin': { const t = s.tabs.find(x => x.id === a.id); t.pinned = !t.pinned; s.tabs.sort((x, y) => (y.pinned ? 1 : 0) - (x.pinned ? 1 : 0)); return done(); }
      case 'tab.reload': { const t = s.tabs.find(x => x.id === a.id) || this.selected(); t.loading = true; t.progress = 0.1; this.push(); let p = 0.1; const timer = setInterval(() => { p += 0.2; t.progress = Math.min(1, p); if (p >= 1) { t.loading = false; clearInterval(timer); } this.push(); }, 250); return; }
      case 'tab.stop': { const t = s.tabs.find(x => x.id === a.id); t.loading = false; return done(); }
      case 'tab.closeAll': { s.tabs = s.tabs.filter(t => t.pinned); const t = tab(null); s.tabs.push(t); s.selectedId = t.id; return done(); }
      case 'tab.closeOthers': s.tabs = s.tabs.filter(t => t.pinned || t.id === a.id); return done();
      case 'panel.set': s.panel = a.panel; return done();
      case 'prefs.set': {
        const path = a.path.split('.'); let target = s.prefs;
        for (const key of path.slice(0, -1)) target = target[key];
        target[path[path.length - 1]] = a.value;
        if (a.path === 'language') s.text.language = a.value;
        if (a.path === 'lowercase') s.text.lowercase = a.value;
        if (a.path === 'theme' || a.path === 'customBase' || a.path === 'accent' || a.path === 'customTint') {
          const custom = s.prefs.theme === 'custom', base = custom ? s.prefs.customBase : s.prefs.theme;
          s.appearance.dark = base === 'dark' || (base === 'system' && matchMedia('(prefers-color-scheme: dark)').matches);
          s.appearance.accent = custom ? s.prefs.accent : null; s.appearance.accentTint = s.prefs.customTint;
        }
        if (a.path === 'frosted') s.appearance.glass = a.value;
        if (a.path === 'transparency') { s.appearance.shellAlpha = 0.92 - a.value * 0.72; s.appearance.startAlpha = 1 - a.value * 0.55; }
        return done();
      }
      case 'commandBar': s.overlay.commandBar = a.on; return done();
      case 'customize.toolbar': s.overlay.customizingToolbar = a.on; s.overlay.settings = false; return done();
      case 'customize.start': s.overlay.customizingStart = a.on; return done();
      case 'toolbar.move': {
        const t = s.prefs.toolbar;
        for (const zone of ['leading', 'leadingInner', 'trailingInner', 'trailing', 'sidebar']) t[zone] = t[zone].filter(x => x !== a.item);
        if (a.zone !== 'hidden') { const list = t[a.zone]; const at = a.before ? list.indexOf(a.before) : -1; if (at >= 0) list.splice(at, 0, a.item); else list.push(a.item); }
        s.toolbarIsDefault = false; return done();
      }
      case 'toolbar.addressWidth': s.prefs.toolbar.addressWidth = a.value; return done();
      case 'settings.open': s.overlay.settings = true; if (a.section) s.settings.section = a.section; return done();
      case 'settings.close': s.overlay.settings = false; return done();
      case 'settings.set': s.settings[a.key] = a.value; this.push(); return;
      case 'settings.search': s.settings.search = a.engine; this.push(); return;
      case 'onboarding.step': s.overlay.onboardingStep = a.step; return done();
      case 'onboarding.finish': s.overlay.onboarding = false; return done();
      case 'onboarding.open': s.overlay.settings = false; s.overlay.onboarding = true; s.overlay.onboardingStep = 0; return done();
      case 'clearData.open': s.overlay.clearData = true; s.clearData = { period: 'hour', history: true, siteData: false, cache: true, permissions: false, visits: 4, working: false }; return done();
      case 'clearData.set': s.clearData[a.key] = a.value; return done();
      case 'clearData.close': case 'clearData.run': s.overlay.clearData = false; return done();
      case 'profile.open': if (a.where) { s.overlay.profilePrompt = null; } else s.overlay.profilePrompt = a.id; return done();
      case 'profilePrompt.close': s.overlay.profilePrompt = null; return done();
      case 'start.setVisible': { const st = s.prefs.start; st.sections = a.on ? st.sections.concat(st.sections.includes(a.section) ? [] : [a.section]) : st.sections.filter(x => x !== a.section); return done(); }
      case 'start.wordmark': s.prefs.start.wordmark = a.on; return done();
      case 'start.frequentCount': s.prefs.start.frequentCount = a.value; return done();
      case 'start.removeShortcut': s.prefs.start.shortcuts = s.prefs.start.shortcuts.filter(x => x.id !== a.id); return done();
      case 'start.saveShortcut': { if (!/\./.test(a.address)) return this.reply(message.id, false); const url = a.address.includes('://') ? a.address : 'https://' + a.address; s.prefs.start.shortcuts.push({ id: id(), title: a.title, url, host: new URL(url).hostname }); this.reply(message.id, true); return done(); }
      case 'start.moveShortcut': { const list = s.prefs.start.shortcuts; const from = list.findIndex(x => x.id === a.id); const item = list.splice(from, 1)[0]; list.splice(list.findIndex(x => x.id === a.before), 0, item); return done(); }
      case 'start.hideHost': s.prefs.start.hiddenHosts.push(a.host); return done();
      case 'open': case 'navigate': case 'suggestion.open': { const t = this.selected(); const url = a.url || (a.text.includes('.') ? 'https://' + a.text.replace(/^https?:\/\//, '') : 'https://duckduckgo.com/?q=' + encodeURIComponent(a.text)); Object.assign(t, tab(url, new URL(url).hostname), { id: t.id }); s.overlay.commandBar = false; return done(); }
      case 'suggest': {
        const q = a.text.trim(); const items = [];
        if (q.includes('.')) items.push({ id: 'open', kind: 'open', title: 'https://' + q, detail: s.text.lowercase ? 'открыть адрес' : 'Открыть адрес', url: 'https://' + q });
        items.push({ id: 'search', kind: 'search', title: q, detail: (s.text.lowercase ? 'поиск: ' : 'Поиск: ') + 'DuckDuckGo', url: 'https://duckduckgo.com/?q=' + q });
        for (const v of this.state.library.history) if (v.title.toLowerCase().includes(q.toLowerCase())) items.push({ id: v.id, kind: 'history', title: v.title, detail: v.host, url: v.url });
        return this.reply(message.id, items.slice(0, 8));
      }
      case 'find.close': s.overlay.find = false; return done();
      case 'command': {
        if (a.name === 'find') s.overlay.find = !s.overlay.find;
        if (a.name === 'tab') return this.receive({ name: 'tab.new' });
        return done();
      }
      default: console.log('mock host: unhandled', message.name, a);
    }
  }
}
