// Entry of the mica shell. Connects to the host, applies the window's look, renders the window and reports to the
// host where the page goes and which parts of the top bar move the window.

import { installMotion, isReduced } from './core/motion.js';
import { connect, onState, onEvent, send, hosted } from './core/host.js';
import { mount, setState, watchState, watchLayout, update, ui, state, animate } from './core/app.js';
import { Root } from './shell/root.js';
import { menuKey, closeMenu, closePopover, openMenuBelow } from './ui/menu.js';
import { openAppMenu, openSaveMenu } from './shell/topbar.js';
import { focusStartField } from './shell/start.js';
import { prepareCommandBar } from './shell/command.js';
import { focusFind } from './shell/page.js';
import { coversPage, keepsPageKeyboard, layout as currentLayout } from './shell/model.js';
import { keymap } from './gen/tokens.g.js';

// Window shortcuts from shared/keymap.json. The shell sees them while it has the keyboard and hands them to the host,
// which runs them exactly as its accelerators do (and ignores a second report of the same press).
const codes = { '=': 'Equal', '-': 'Minus', ',': 'Comma', '[': 'BracketLeft', ']': 'BracketRight', Left: 'ArrowLeft', Right: 'ArrowRight', Add: 'NumpadAdd', Subtract: 'NumpadSubtract', NumberPad0: 'Numpad0' };
const shortcuts = [];
for (const command in keymap) for (const text of keymap[command]) {
  const parts = text.split('+'), key = parts.pop();
  if (key.startsWith('XButton')) continue;
  const code = codes[key] || (/^[A-Z]$/.test(key) ? 'Key' + key : /^[0-9]$/.test(key) ? 'Digit' + key : key);
  shortcuts.push({ command, code, ctrl: parts.includes('Ctrl'), shift: parts.includes('Shift'), alt: parts.includes('Alt') });
}
function shortcutFor(event) {
  for (const s of shortcuts) {
    if (s.ctrl !== event.ctrlKey || s.shift !== event.shiftKey || s.alt !== event.altKey || event.metaKey) continue;
    if (event.code === s.code || event.key === s.code) return s.command;
  }
  return null;
}

installMotion();

function applyLook(next) {
  const root = document.documentElement, a = next.appearance;
  root.dataset.theme = a.dark ? 'dark' : 'light';
  if (a.contrast) root.dataset.contrast = 'more'; else delete root.dataset.contrast;
  if (a.accent) {
    root.dataset.accent = '';
    root.style.setProperty('--accent-raw', a.accent);
    root.style.setProperty('--on-accent-raw', a.onAccent || '#fff');
    root.style.setProperty('--accent-tint', Math.round(a.accentTint * 100) + '%');
  } else delete root.dataset.accent;
  root.style.setProperty('--shell-alpha', a.glass ? a.shellAlpha : 1);
  root.style.setProperty('--start-alpha', a.glass ? a.startAlpha : 1);
  root.style.setProperty('--caption-bar', (next.system.captionHeight || 48) + 'px');
}

// Which changes animate, and with which spring (the .animation(..., value:) modifiers of BrowserRoot).
watchState((previous, next) => {
  const p = previous, n = next;
  if (p.prefs.layout !== n.prefs.layout || p.prefs.sidebarCollapsed !== n.prefs.sidebarCollapsed || p.panel !== n.panel) return 'panel';
  if (p.overlay.customizingToolbar !== n.overlay.customizingToolbar || p.overlay.customizingStart !== n.overlay.customizingStart) return 'panel';
  if (JSON.stringify(p.prefs.toolbar) !== JSON.stringify(n.prefs.toolbar)) return 'snappy';
  if (JSON.stringify(p.prefs.start) !== JSON.stringify(n.prefs.start)) return 'snappy';
  if (p.tabs.length !== n.tabs.length || p.tabs.some((tab, i) => tab.id !== n.tabs[i].id || tab.pinned !== n.tabs[i].pinned)) return 'snappy';
  if (p.start && n.start && JSON.stringify(p.start.sections) !== JSON.stringify(n.start.sections)) return 'snappy';
  if (p.library !== n.library && n.panel) return 'snappy';
  if ((p.settings && p.settings.section) !== (n.settings && n.settings.section)) return 'snappy';
  return null;
});

let first = true;
onState(next => {
  applyLook(next);
  if (!state || !state.overlay.commandBar) { if (next.overlay.commandBar) prepareCommandBar(); }
  setState(next);
  if (first) { first = false; requestAnimationFrame(() => send('shell.ready')); }
});

onEvent((name, args) => {
  switch (name) {
    case 'focusAddress': if (!focusStartField()) send('commandBar', { on: true }); break;
    case 'menu': openAppMenu(); break;
    case 'saveMenu': openSaveMenu(); break;
    case 'focusFind': focusFind(); break;
    case 'closeMenus': closeMenu(false); closePopover(); break;
    case 'entered': update(u => { u.entered = false; }); break;
    default: break;
  }
});

// Geometry for the host: the page rectangle and the caption regions of the window, in DIPs.
let lastReport = '';
let tracking = 0;
function report() {
  if (!state) return;
  const hole = document.querySelector('.page-hole');
  const rect = hole ? hole.getBoundingClientRect() : null;
  const caption = [], passthrough = [];
  const bands = document.querySelectorAll('.bar-top, .band, .bar-under, .strip-host');
  for (const band of bands) {
    const r = band.getBoundingClientRect();
    if (r.height > 0) caption.push([r.left, r.top, r.width, r.height]);
    for (const el of band.querySelectorAll('button, input, .tab, .tile, .pill, .dropzone, .edit-tile, [role="slider"]')) {
      const b = el.getBoundingClientRect();
      if (b.width > 0 && b.height > 0) passthrough.push([b.left, b.top, b.width, b.height]);
    }
  }
  const payload = {
    page: rect ? [rect.left, rect.top, rect.width, rect.height] : null,
    covered: coversPage(),
    keepPage: keepsPageKeyboard(),
    caption: state.overlay.customizingToolbar || document.documentElement.hasAttribute('data-dragging') ? [] : caption,
    passthrough,
    radius: 10,
  };
  const text = JSON.stringify(payload, (key, value) => typeof value === 'number' ? Math.round(value * 100) / 100 : value);
  if (text === lastReport) return;
  lastReport = text;
  send('layout', payload);
}

/// While an animation moves the card (layout change, panel opening), the page follows it frame by frame.
function follow(ms) {
  const until = performance.now() + ms;
  if (tracking > until) return;
  const running = tracking > performance.now();
  tracking = until;
  if (running) return;
  const tick = () => { report(); if (performance.now() < tracking) requestAnimationFrame(tick); };
  requestAnimationFrame(tick);
}

watchLayout(() => { report(); if (document.documentElement.hasAttribute('data-anim')) follow(700); });
window.addEventListener('resize', () => { update(); });
new ResizeObserver(() => report()).observe(document.documentElement);

// Keys the shell takes itself; window shortcuts reach the host as accelerators.
window.addEventListener('keydown', event => {
  if (menuKey(event)) return;
  const command = shortcutFor(event);
  if (command && !(event.repeat && command === 'quit')) { event.preventDefault(); event.stopPropagation(); send('key', { command }); return; }
  if (event.key === 'Escape') {
    if (ui.popover) { closePopover(); event.preventDefault(); return; }
    if (state && state.overlay.commandBar) { send('commandBar', { on: false }); event.preventDefault(); return; }
    if (state && state.overlay.customizingToolbar) { send('customize.toolbar', { on: false }); event.preventDefault(); return; }
    if (state && state.overlay.find) { send('find.close'); event.preventDefault(); return; }
    if (state && state.overlay.passwordOffer) { send('passwords.offer', { index: -1 }); event.preventDefault(); return; }
  }
  if (event.key === 'Enter' && state && (state.overlay.profilePrompt || state.overlay.alert)) {
    const button = document.querySelector('.modal [data-default]');
    if (button && document.activeElement && document.activeElement.tagName !== 'BUTTON') { button.click(); event.preventDefault(); }
  }
}, true);

// The page area of the shell must never take the context menu of the shell's web view.
window.addEventListener('contextmenu', event => {
  if (!event.defaultPrevented && !(event.target.closest && event.target.closest('input, textarea, .selectable'))) event.preventDefault();
});

// Text selection and dragging of shell images look like a web page; the shell is an application.
window.addEventListener('dragstart', event => { if (!(event.target.closest && event.target.closest('input'))) event.preventDefault(); });

async function start() {
  if (!hosted) {
    const { MockHost } = await import('../dev/mock-host.js');
    connect(new MockHost());
  } else connect();
  mount(document.getElementById('root'), Root);
  send('shell.hello', { reducedMotion: isReduced() });
}
start();

export { animate, currentLayout, openMenuBelow };
