// The start page (StartPage on macOS): greeting or the mica wordmark, the search field, sections of sites and the
// in-place customization. It is mica's own surface inside the content card, so the shell draws it; with glass on,
// the card lets the frosted shell through.

import { h, cx } from '../core/dom.js';
import { icon, incognito } from '../core/icons.js';
import { T, keys } from '../core/text.js';
import { motion as tokens } from '../gen/tokens.g.js';
import { springs, settle, isReduced, hover } from '../core/motion.js';
import { IconButton, KeyHint, SiteIcon, Segmented, Button, TextField, Hairline } from '../ui/controls.js';
import { contextMenu, openPopover, closePopover, item, divider } from '../ui/menu.js';
import { dragSource, onDrop } from '../ui/drag.js';
import { request } from '../core/host.js';
import { state, ui, update, send, selected } from './model.js';
import { SuggestionList, suggest, submit, suggestionKeys, activate } from './command.js';

onDrop('shortcut', (id, before) => { if (before && before !== id) send('start.moveShortcut', { id, before }); });

const introduced = new Set();
const step = index => index * tokens.entrance.stagger;

/// Window and start page entrance: a part fades in and settles into place with the panel spring `delay` seconds
/// after the entrance begins. It only moves pixels: the field takes typing and clicks from the first frame.
function entrance(play, delay, { rise = tokens.entrance.rise, dx = 0, scale = 1 } = {}) {
  if (!play) return null;
  return el => {
    if (isReduced()) { el.animate([{ opacity: 0 }, { opacity: 1 }], { duration: tokens.entrance.reducedFade * 1000, easing: 'ease-out', fill: 'backwards' }); return; }
    const options = { duration: springs.panel.ms, easing: springs.panel.easing, delay: delay * 1000, fill: 'backwards' };
    el.animate([{ opacity: 0 }, { opacity: 1 }], options);
    if (rise || dx || scale !== 1) el.animate([{ translate: `${dx}px ${rise}px`, scale }, { translate: '0 0', scale: 1 }], options);
  };
}

const letterStep = count => count > 1 ? Math.min(tokens.wordmark.letterStagger, tokens.wordmark.staggerCap / (count - 1)) : 0;
const letterTotal = count => Math.max(count - 1, 0) * letterStep(count) + settle(tokens.wordmark.letterDuration, 0.78);

/// Text that assembles glyph by glyph: each glyph rises, comes into focus and closes in from a wider spacing,
/// one after another from the first (AssembleRenderer on macOS). Words stay whole, so a greeting still wraps.
function Assembling(text, cls, play, delay) {
  const glyphs = Array.from(text);
  const count = glyphs.filter(glyph => glyph.trim()).length;
  const middle = (count - 1) / 2, stagger = letterStep(count), fade = tokens.wordmark.letterDuration * 0.6 * 1000;
  let index = 0;
  const words = text.split(/(\s+)/).map((word, w) => {
    if (!word.trim()) return word ? ' ' : null;
    return h('span', { class: 'word', key: w }, Array.from(word).map(glyph => {
      const i = index++;
      return h('span', {
        class: 'letter',
        onMount: play && !isReduced() ? el => {
          const wait = (delay + i * stagger) * 1000;
          el.animate([{ translate: `${(i - middle) * tokens.wordmark.spread}px ${tokens.wordmark.rise}px` }, { translate: '0 0' }], { duration: springs.letter.ms, easing: springs.letter.easing, delay: wait, fill: 'backwards' });
          el.animate([{ opacity: 0, filter: `blur(${tokens.wordmark.blur}px)` }, { opacity: 1, filter: 'blur(0px)' }], { duration: fade, easing: 'linear', delay: wait, fill: 'backwards' });
        } : null,
      }, glyph);
    }));
  });
  return h('div', { class: cx('assembling', cls), 'aria-label': text, role: 'heading', 'aria-level': 1, onMount: play && isReduced() ? entrance(true, delay) : null }, words);
}

function label(site) { return site.title || (site.host || '').replace(/^www\./i, ''); }

function siteMenu(site, section, shortcuts) {
  return () => {
    const first = shortcuts.length && shortcuts[0].id === site.shortcut, last = shortcuts.length && shortcuts[shortcuts.length - 1].id === site.shortcut;
    return [
      item(T("открыть в новой вкладке", "Открыть в новой вкладке"), () => send('open', { url: site.url, newTab: true }), { symbol: 'plus.square' }),
      item(T("открыть в новом окне", "Открыть в новом окне"), () => send('open', { url: site.url, newWindow: true }), { symbol: 'macwindow' }),
      divider,
      site.shortcut ? [
        item(T("изменить…", "Изменить…"), () => { const el = document.querySelector(`[data-site="${site.id}"]`); if (el) openPopover('shortcut', el, () => ShortcutEditor({ editing: site, done: () => closePopover('shortcut') }), { sticky: true }); }, { symbol: 'pencil' }),
        item(T("переместить левее", "Переместить левее"), () => send('start.shiftShortcut', { id: site.shortcut, by: -1 }), { symbol: 'arrow.left', enabled: !first }),
        item(T("переместить правее", "Переместить правее"), () => send('start.shiftShortcut', { id: site.shortcut, by: 1 }), { symbol: 'arrow.right', enabled: !last }),
        divider,
        item(T("удалить с начальной страницы", "Удалить с начальной страницы"), () => send('start.removeShortcut', { id: site.shortcut }), { symbol: 'trash', destructive: true }),
      ] : [
        item(T("закрепить в своих сайтах", "Закрепить в своих сайтах"), () => send('start.pin', { url: site.url, title: site.title }), { symbol: 'pin' }),
        section === 'frequent' && site.host ? item(T("скрыть из частых", "Скрыть из частых"), () => send('start.hideHost', { host: site.host }), { symbol: 'eye.slash' }) : null,
      ],
      divider,
      item(T("настроить начальную страницу…", "Настроить начальную страницу…"), () => send('customize.start', { on: true }), { symbol: 'slider.horizontal.3' }),
    ];
  };
}

function SiteTile(site, section, shortcuts) {
  const draggable = !!site.shortcut;
  return h('button', {
    class: 'site-tile', type: 'button', key: site.id, flip: true, enter: 'pop', exit: 'pop', title: site.host, 'aria-label': label(site), 'data-site': site.id,
    'data-drop': draggable ? 'shortcut' : null, 'data-drop-id': draggable ? site.shortcut : null,
    onPointerDown: draggable ? dragSource('shortcut', site.shortcut) : null,
    // Ctrl+click opens the site in a new window of this profile, as ⌘-click does on macOS.
    onClick: event => send('open', { url: site.url, newWindow: event.ctrlKey || event.metaKey }), onContextMenu: contextMenu(siteMenu(site, section, shortcuts)),
  }, h('span', { class: 'tile-box' },
    // The site's own colour lighting the tile from inside on hover (motion.aura), clipped by the plate.
    h('span', { class: 'tile-aura', 'aria-hidden': 'true' }, SiteIcon(site, tokens.aura.icon, true)),
    h('span', { class: 'tile-icon' }, SiteIcon(site, tokens.aura.icon, true))),
  h('span', { class: 'tile-label clip' }, label(site)));
}

function AddTile() {
  return h('button', {
    class: 'site-tile add', type: 'button', key: 'add', flip: true, enter: 'pop', exit: 'pop', 'aria-label': T("добавить сайт на начальную страницу", "Добавить сайт на начальную страницу"),
    onClick: event => openPopover('shortcut', event.currentTarget.querySelector('.tile-box'), () => ShortcutEditor({ done: () => closePopover('shortcut') }), { sticky: true }),
  }, h('span', { class: 'tile-box dashed' }, icon('plus', 16, 'regular')), h('span', { class: 'tile-label clip' }, T("добавить", "Добавить")));
}

/// Adds or edits a custom start page site. Plain words are refused instead of becoming a search shortcut.
/// Opened from the address bar it comes with the page's address filled in, and the name field takes the focus.
export function ShortcutEditor({ editing, page, done }) {
  const form = ui.shortcutForm && ui.shortcutForm.owner === (editing ? editing.id : page || 'new')
    ? ui.shortcutForm
    : (ui.shortcutForm = { owner: editing ? editing.id : page || 'new', address: editing ? editing.url : page || '', title: editing ? editing.title : '', invalid: false });
  const save = () => {
    request('start.saveShortcut', { id: editing ? editing.shortcut : null, address: form.address, title: form.title, page: page || null }).then(ok => {
      if (ok) { ui.shortcutForm = null; done(); } else update(() => { form.invalid = true; });
    });
  };
  const cancel = () => { ui.shortcutForm = null; done(); };
  return h('div', { class: 'shortcut-editor' },
    h('div', { class: 'popover-title' }, editing ? T("изменить сайт", "Изменить сайт") : T("новый сайт", "Новый сайт")),
    h('div', { class: 'col', style: { gap: '8px' } },
      TextField(T("адрес, например github.com", "Адрес, например github.com"), form.address, value => update(() => { form.address = value; form.invalid = false; }), { symbol: 'globe', autofocus: !page, onSubmit: save, onEscape: cancel }),
      form.invalid ? h('div', { class: 'form-error', key: 'error', enter: 'fade' }, T("нужен адрес сайта, а не поисковый запрос", "Нужен адрес сайта, а не поисковый запрос")) : null,
      TextField(T("название, необязательно", "Название, необязательно"), form.title, value => update(() => { form.title = value; }), { symbol: 'textformat', autofocus: !!page, onSubmit: save, onEscape: cancel, key: 'title' })),
    h('div', { class: 'row', style: { gap: '8px', 'justify-content': 'flex-end' } },
      Button(T("отмена", "Отмена"), { kind: 'ghost', compact: true, onClick: cancel }),
      Button(editing ? T("сохранить", "Сохранить") : T("добавить", "Добавить"), { kind: 'primary', compact: true, disabled: !form.address.trim(), onClick: save })));
}

const sectionTitle = section => section === 'custom' ? T("свои сайты", "Свои сайты") : section === 'frequent' ? T("часто открываете", "Часто открываете") : T("закладки", "Закладки");

/// Title row of a start page block. While customizing, the title with an eye after it shows or hides the block,
/// and optional order buttons stand on the right. The row itself never dims, only the block content.
function BlockHeader(title, editing, shown, onToggle, order, id) {
  return h('div', { class: 'block-header' },
    BlockTitle(title, editing, shown, onToggle, id),
    h('span', { class: 'spacer' }),
    editing && order ? h('span', { class: 'row', key: 'order', enter: 'fade', exit: 'fade' }, order) : null);
}

/// While customizing the title becomes the block's visibility toggle: the eye after it fades in, so the title never
/// moves, and the whole capsule is the target. The outline radius follows from this capsule (.start-block).
function BlockTitle(title, editing, shown, onToggle, id) {
  const label = (shown ? T("скрыть", "Скрыть") : T("показать", "Показать")) + ': ' + title;
  return h('button', {
    class: cx('block-toggle press', { editing }), type: 'button', role: editing ? 'switch' : null, 'aria-checked': editing ? String(shown) : null,
    'aria-label': editing ? T("показывать", "Показывать") + ': ' + title : null, title: editing ? label : null, tabIndex: editing ? 0 : -1,
    onClick: () => { if (editing) onToggle(!shown); },
  },
    h('span', { class: 'block-title' }, title),
    editing ? h('span', { class: cx('block-eye', { off: !shown }), key: 'eye', enter: 'fade', exit: 'fade', html: eyeSVG('eye-' + id) }) : null);
}

/// An eye that a slash crosses out when its block is hidden: the slash grows from its top end and cuts a gap through
/// the outline (a mask, so the gap does not depend on the frosted background), the lid narrows and the pupil fades.
const eyeSVG = id => `<svg viewBox="0 0 24 24" width="17" height="17" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false"><defs><mask id="${id}" maskUnits="userSpaceOnUse" x="0" y="0" width="24" height="24"><rect width="24" height="24" fill="#fff" stroke="none"/><path class="eye-slash" d="M4.5 3.5l16 16" stroke="#000" stroke-width="5"/></mask></defs><g mask="url(#${id})"><path class="eye-lid" d="M2.5 12c2.2-4.2 5.4-6.3 9.5-6.3s7.3 2.1 9.5 6.3c-2.2 4.2-5.4 6.3-9.5 6.3S4.7 16.2 2.5 12Z"/><circle class="eye-pupil" cx="12" cy="12" r="2.8"/></g><path class="eye-slash" d="M4.5 3.5l16 16"/></svg>`;

function Section(entry, editing, play, delay) {
  const start = state.prefs.start, section = entry.section;
  const visible = start.sections.includes(section);
  const first = start.sections[0] === section, last = start.sections[start.sections.length - 1] === section;
  const placeholder = section === 'frequent'
    ? (state.window.isPrivate ? T("в окне инкогнито частые сайты не показываются", "В окне инкогнито частые сайты не показываются") : T("появятся, когда вы начнёте открывать сайты", "Появятся, когда вы начнёте открывать сайты"))
    : T("здесь будут закладки, Ctrl+D добавляет страницу", "Здесь будут закладки, Ctrl+D добавляет страницу");
  // A row never holds more columns than the section has tiles, so the block keeps to its own content.
  const tiles = entry.sites.length + (section === 'custom' ? 1 : 0);
  const columns = Math.max(1, Math.min(start.frequentCount, tiles));
  return h('section', { class: cx('start-block', { editing }), key: section, flip: true, enter: 'fade', exit: 'fade', onMount: entrance(play, delay), style: { '--row': columns } },
    BlockHeader(sectionTitle(section), editing, visible, value => send('start.setVisible', { section, on: value }), h('span', { class: 'row' },
      IconButton('chevron.up', T("выше", "Выше") + ': ' + sectionTitle(section), { size: 24, disabled: !visible || first, onClick: () => send('start.shiftSection', { section, by: -1 }) }),
      IconButton('chevron.down', T("ниже", "Ниже") + ': ' + sectionTitle(section), { size: 24, disabled: !visible || last, onClick: () => send('start.shiftSection', { section, by: 1 }) })), section),
    h('div', { class: cx('block-content', { dimmed: editing && !visible }) },
      editing && !entry.sites.length && section !== 'custom'
        ? h('div', { class: 'block-placeholder', key: 'placeholder' }, placeholder)
        : h('div', { class: 'tile-grid', key: 'grid' }, entry.sites.map(site => SiteTile(site, section, start.shortcuts)), section === 'custom' ? AddTile() : null)));
}

/// Sections in the user's order. Empty sections are skipped, except custom sites, which always offer the add tile.
/// While customizing, every section is listed, hidden ones after the visible ones, empty ones too.
function visibleSections(editing) {
  const options = state.prefs.start, all = ['custom', 'frequent', 'bookmarks'];
  const order = editing ? options.sections.concat(all.filter(section => !options.sections.includes(section))) : options.sections;
  const out = [];
  for (const section of order) {
    const entry = state.start.sections.find(candidate => candidate.section === section) || { section, sites: [] };
    if (section !== 'custom' && !entry.sites.length && !editing) continue;
    out.push(entry);
  }
  return out;
}

function SearchField(box, editing, play) {
  const focused = box.focused;
  const choose = entry => { activate(entry); box.text = ''; box.items = []; };
  return h('div', { class: cx('start-search', { focused, dimmed: editing }), key: 'search', flip: true, onMount: entrance(play, step(3)) },
    h('div', { class: 'start-search-row' },
      h('span', { class: 'command-glass' }, icon('magnifyingglass', 15)),
      h('input', {
        class: 'command-input', type: 'text', value: box.text, disabled: editing, spellcheck: false, autocomplete: 'off',
        placeholder: T("поиск в ", "Поиск в ") + state.start.searchTitle + T(" или адрес", " или адрес"), 'aria-label': T("адресная строка", "Адресная строка"),
        onInput: event => suggest(box, event.target.value),
        onFocus: () => update(() => { box.focused = true; }, 'snappy'),
        onBlur: () => update(() => { box.focused = false; }, 'snappy'),
        onKeyDown: event => {
          if (event.key === 'Enter') { if (submit(box)) { box.text = ''; box.items = []; } event.preventDefault(); }
          else if (event.key === 'Escape') { event.target.blur(); }
          else if (suggestionKeys(box, event)) event.preventDefault();
        },
        ref: el => { startField = el; },
        onMount: el => { if (!state.overlay.onboarding) requestAnimationFrame(() => el.focus()); },
      }),
      !focused ? h('span', { key: 'hint', enter: 'fade', exit: 'fade' }, KeyHint(keys('address'))) : null),
    box.items.length && focused ? [Hairline(), h('div', { class: 'command-list', key: 'list' }, SuggestionList(box, choose))] : null);
}

let startField = null;
/// Ctrl+L on the start page focuses its own field instead of opening the command bar.
export function focusStartField() { if (startField && startField.isConnected) { startField.focus(); startField.select(); return true; } return false; }

function hints() {
  const hint = (shortcut, title) => h('span', { class: 'start-hint' }, KeyHint(shortcut), h('span', null, title));
  return h('div', { class: 'start-hints', key: 'hints', enter: 'fade', exit: 'fade' },
    hint(keys('tab'), T("вкладка", "Вкладка")), hint(keys('private'), T("инкогнито", "Инкогнито")), hint(keys('sidebar'), T("боковая панель", "Боковая панель")));
}

/// Options that apply to the whole start page, under the live page while customizing.
function CustomizeBar() {
  const start = state.prefs.start;
  return h('div', { class: 'start-bar raised', key: 'bar', enter: 'slide-bottom', exit: { name: 'slide-bottom', float: false } },
    h('span', { class: 'start-bar-label' }, T("сайтов в ряду", "Сайтов в ряду")),
    Segmented(start.frequentCount, [4, 8, 12, 16].map(value => ({ value, title: String(value) })), value => send('start.frequentCount', { value }), { compact: true, label: T("сайтов в ряду", "Сайтов в ряду") }),
    h('span', { class: 'spacer' }),
    IconButton('arrow.counterclockwise', T("вернуть как было", "Вернуть как было"), { disabled: state.start.isDefault, onClick: () => send('start.reset') }),
    IconButton('gearshape', T("все настройки", "Все настройки"), { onClick: () => { send('customize.start', { on: false }); send('settings.open', { section: 'start' }); } }),
    Button(T("готово", "Готово"), { kind: 'primary', compact: true, onClick: () => send('customize.start', { on: false }) }));
}

export function StartScreen(tab) {
  const editing = state.overlay.customizingStart;
  const box = ui.start;
  if (box.tab !== tab.id) { box.tab = tab.id; box.text = ''; box.items = []; box.highlighted = 0; box.focused = false; }
  // Plays the entrance once per tab; a tab that already showed it comes back at rest.
  const play = !introduced.has(tab.id);
  introduced.add(tab.id);
  const options = state.prefs.start;
  const greeting = state.start.greeting;
  const sections = visibleSections(editing);
  const isPrivate = state.window.isPrivate;
  const showMark = options.wordmark || editing;
  const markTotal = letterTotal(Array.from(greeting || 'mica').filter(glyph => glyph.trim()).length);
  return h('div', { class: cx('start', { editing }), key: 'start-' + tab.id, enter: 'fade', exit: 'fade', onKeyDown: event => { if (event.key === 'Escape' && editing) send('customize.start', { on: false }); } },
    h('div', { class: 'start-scroll scroll' },
      h('div', { class: 'start-column', style: { '--columns': options.frequentCount } },
        showMark || isPrivate ? h('div', { class: 'start-head', key: 'head', flip: true },
          showMark ? h('div', { class: cx('start-block mark-block', { editing }), key: 'mark' },
            editing ? BlockHeader(greeting ? T("приветствие", "Приветствие") : T("знак mica", "Знак mica"), true, options.wordmark, value => send('start.wordmark', { on: value }), null, 'mark') : null,
            h('div', { class: cx('mark-holder', { dimmed: editing && !options.wordmark }) },
              greeting ? Assembling(greeting, 'greeting', play, step(2)) : Assembling('mica', 'wordmark', play, step(2)))) : null,
          isPrivate && !editing ? h('span', { class: 'private-capsule', key: 'private', onMount: entrance(play, options.wordmark ? step(2) + markTotal * 0.55 : step(2), { rise: 0, dx: -14 }) }, icon(incognito, 11.5), T("инкогнито", "Инкогнито")) : null) : null,
        SearchField(box, editing, play),
        !box.text || editing ? [
          sections.length ? null : hints(),
          sections.map((entry, index) => Section(entry, editing, play, step(4 + index))),
        ] : null,
        isPrivate && !editing ? h('div', { class: 'private-note', key: 'private-note', flip: true, onMount: entrance(play, step(4 + sections.length)) },
          T("история и сессия этого окна не сохраняются. загруженные файлы остаются на диске.", "История и сессия этого окна не сохраняются. Загруженные файлы остаются на диске.")) : null)),
    editing ? CustomizeBar() : h('button', {
      class: 'start-customize press', type: 'button', key: 'customize', title: T("настроить начальную страницу", "Настроить начальную страницу"), enter: 'fade', exit: 'fade',
      onMount: entrance(play, step(5 + sections.length), { rise: 0 }), onClick: () => send('customize.start', { on: true }),
    }, icon('slider.horizontal.3', 11.5), h('span', null, T("настроить", "Настроить"))));
}

export { hover, selected };
