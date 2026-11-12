// The library card beside the page: bookmarks, history, downloads and extensions (Library, Downloads and
// Extensions panels on macOS). The host sends the rows of the open panel only.

import { h, cx } from '../core/dom.js';
import { icon } from '../core/icons.js';
import { T, keys, lang, isLowercase, locale, fileSize } from '../core/text.js';
import { geometry } from '../gen/tokens.g.js';
import { IconButton, TextField, EmptyState, SiteIcon, Switch, Button, LinkRow, Monogram } from '../ui/controls.js';
import { openMenuBelow, item, divider } from '../ui/menu.js';
import { ProfileMark } from '../ui/profile.js';
import { state, ui, update, send, selected } from './model.js';

const ROW_ICON = geometry.chrome.rowIcon;

function panelTitle(panel) {
  switch (panel) {
    case 'bookmarks': return T("закладки", "Закладки");
    case 'history': return T("история", "История");
    case 'downloads': return T("загрузки", "Загрузки");
    default: return T("расширения", "Расширения");
  }
}

function box(panel) { return ui.library[panel] || (ui.library[panel] = { query: '', profile: null }); }

const startOfDay = time => { const d = new Date(time); d.setHours(0, 0, 0, 0); return d.getTime(); };

/// Day title above a group of rows: today, yesterday, then weekday and date in the interface language.
function dayTitle(day) {
  if (day == null) return T("раньше", "Раньше");
  const today = startOfDay(Date.now());
  if (day === today) return T("сегодня", "Сегодня");
  if (day === today - 86400000 || (today - day > 0 && today - day < 90000000 && new Date(today).getDate() !== new Date(day).getDate() && today - day <= 86400000 + 3600000)) return T("вчера", "Вчера");
  const sameYear = new Date(day).getFullYear() === new Date().getFullYear();
  const text = new Date(day).toLocaleDateString(locale(), sameYear ? { weekday: 'long', day: 'numeric', month: 'long' } : { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' });
  // Weekday and month names are authored words, so they follow the case style.
  return isLowercase() ? text.toLocaleLowerCase(locale()) : text[0].toLocaleUpperCase(locale()) + text.slice(1);
}

function grouped(rows, timeOf) {
  const groups = [];
  for (const row of rows) {
    const time = timeOf(row), day = time ? startOfDay(time) : null;
    const last = groups[groups.length - 1];
    if (last && last.day === day) last.rows.push(row); else groups.push({ day, rows: [row] });
  }
  return groups;
}

const time = ms => new Date(ms).toLocaleTimeString(locale(), { hour: '2-digit', minute: '2-digit' });

function VisitRow(visit, panel) {
  const owner = panel === 'history' && state.profiles.length > 1 ? state.profiles.find(profile => profile.id === visit.profile) : null;
  const actions = event => openMenuBelow([
    item(T("открыть в новой вкладке", "Открыть в новой вкладке"), () => send('open', { url: visit.url, newTab: true }), { symbol: 'plus.square' }),
    item(T("копировать адрес", "Копировать адрес"), () => send('copy', { text: visit.url }), { symbol: 'link' }),
    divider,
    panel === 'history' && visit.host ? item(T("удалить всё с сайта ", "Удалить всё с сайта ") + visit.host, () => send('history.removeHost', { host: visit.host }), { symbol: 'trash.slash', destructive: true }) : null,
    item(T("удалить", "Удалить"), () => send(panel === 'history' ? 'history.remove' : 'bookmarks.remove', { id: visit.id }), { symbol: 'trash', destructive: true }),
  ], event.currentTarget);
  return h('div', { class: 'lib-row', key: visit.id, flip: true, enter: 'fade', exit: 'fade' },
    h('button', { class: 'lib-main press', type: 'button', onClick: () => send('open', { url: visit.url }) },
      h('span', { class: 'lib-icon tiled' }, SiteIcon(visit, ROW_ICON * 0.6),
        owner ? h('span', { class: 'lib-owner', title: owner.name }, ProfileMark(owner, 13)) : null),
      h('span', { class: 'lib-text' },
        h('span', { class: 'lib-title clip' }, visit.title || visit.url),
        h('span', { class: 'lib-detail clip' }, visit.host || visit.url, panel === 'history' && visit.time ? h('span', { class: 'lib-time' }, time(visit.time)) : null))),
    h('span', { class: 'lib-actions' }, IconButton('ellipsis', T("действия", "Действия"), { size: 24, onClick: actions })));
}

function ProfileFilter(current, choose) {
  const all = [{ id: null, name: T("все", "Все") }].concat(state.profiles);
  return h('div', { class: 'chips scroll', role: 'radiogroup', 'aria-label': T("профиль", "Профиль") }, all.map(profile => h('button', {
    class: cx('chip press', { selected: current === profile.id }), type: 'button', role: 'radio', 'aria-checked': current === profile.id ? 'true' : 'false', key: profile.id || 'all', flip: true,
    onClick: () => choose(profile.id),
  }, profile.id ? ProfileMark(profile, 14) : null, h('span', null, profile.name))));
}

function Visits(panel) {
  const b = box(panel);
  const list = (panel === 'history' ? state.library.history : state.library.bookmarks) || [];
  const query = b.query.trim().toLocaleLowerCase();
  const filter = state.profiles.some(profile => profile.id === b.profile) ? b.profile : null;
  const rows = list.filter(visit => (!query || (visit.title || '').toLocaleLowerCase().includes(query) || visit.url.toLocaleLowerCase().includes(query))
    && (panel !== 'history' || !filter || visit.profile === filter));
  return [
    TextField(T("поиск", "Поиск"), b.query, value => update(() => { b.query = value; }, 'snappy'), { symbol: 'magnifyingglass', key: 'search' }),
    panel === 'history' && state.window.isPrivate ? h('div', { class: 'lib-note', key: 'private' }, T("история окна инкогнито не записывается", "История окна инкогнито не записывается")) : null,
    panel === 'history' && state.profiles.length > 1 && !state.window.isPrivate ? ProfileFilter(filter, id => update(() => { b.profile = id; }, 'snappy')) : null,
    !rows.length
      ? EmptyState(panel === 'history' ? 'clock' : 'bookmark', query ? T("ничего не найдено", "Ничего не найдено") : panel === 'history' ? T("история пока пуста", "История пока пуста") : T("добавьте закладку через Ctrl+D", "Добавьте закладку через Ctrl+D"))
      : h('div', { class: 'lib-list scroll', key: 'list' }, panel === 'history'
          ? grouped(rows, visit => visit.time).map(group => [h('div', { class: 'day-header', key: 'day-' + group.day, role: 'heading', 'aria-level': 3 }, dayTitle(group.day)), group.rows.map(visit => VisitRow(visit, panel))])
          : rows.map(visit => VisitRow(visit, panel))),
    panel === 'history' && list.length && !state.window.isPrivate ? h('div', { key: 'clear' }, Button(T("очистить историю…", "Очистить историю…"), { kind: 'destructive', compact: true, onClick: () => send('clearData.open') })) : null,
  ];
}

// Downloads

function kindWord(kind) {
  switch (kind) {
    case 'image': return T("картинка", "Картинка");
    case 'video': return T("видео", "Видео");
    case 'archive': return T("архив", "Архив");
    case 'document': return T("документ", "Документ");
    default: return T("файл", "Файл");
  }
}
const kindSymbol = { image: 'photo', video: 'film', archive: 'archivebox', document: 'doc.text', other: 'doc' };

/// Kind of file in words with its extension: "картинка PNG"; English puts the extension first.
function typeLabel(item) {
  const word = kindWord(item.kind), ext = (item.ext || '').toUpperCase();
  if (!ext) return word;
  return lang() === 'en' ? ext + ' ' + word.toLowerCase() : word + ' ' + ext;
}

/// Second line: type, size and time when finished, progress while running, the reason otherwise.
function downloadDetail(item) {
  switch (item.state) {
    case 'running': case 'paused':
      if (item.saving) return T("сохраняется", "Сохраняется");
      return item.total > 0 ? fileSize(item.bytes) + ' ' + T("из", "из") + ' ' + fileSize(item.total) : fileSize(item.bytes);
    case 'complete': return [typeLabel(item), item.size > 0 ? fileSize(item.size) : null, item.time ? time(item.time) : null].filter(Boolean).join(', ');
    case 'cancelled': return T("отменено", "Отменено");
    case 'failed': return item.failure || T("ошибка загрузки", "Ошибка загрузки");
    default: return T("ожидает выбора места", "Ожидает выбора места");
  }
}

/// Leading mark of a download row. While the file arrives: one arrow inside a progress ring. When it lands: the
/// ring closes and a checkmark draws itself. Then: the icon of the file kind.
function DownloadBadge(item) {
  const size = ROW_ICON;
  const phase = item.justFinished ? 'done' : item.active ? 'progress' : 'kind';
  let body;
  if (phase === 'progress') {
    const r = size / 2 - 2, length = 2 * Math.PI * r;
    const known = item.total > 0;
    const arc = known ? Math.max(0.04, item.fraction) : 0.25;
    body = h('span', { class: 'dl-badge-inner', key: 'progress', enter: 'pop', exit: 'pop' },
      h('span', { class: cx('dl-ring', { unknown: !known && item.state === 'running' }), html: `<svg viewBox="0 0 ${size} ${size}" fill="none" stroke-width="2"><circle cx="${size / 2}" cy="${size / 2}" r="${r}" class="dl-track"/>${item.state === 'running' ? `<circle cx="${size / 2}" cy="${size / 2}" r="${r}" class="dl-value" stroke-linecap="round" stroke-dasharray="${(length * arc).toFixed(2)} ${length.toFixed(2)}" transform="rotate(-90 ${size / 2} ${size / 2})"/>` : ''}</svg>` }),
      h('span', { class: 'dl-arrow' }, icon('arrow.down', size * 0.4 / 1.42 * 1.0, 'semibold')));
  } else if (phase === 'done') {
    body = h('span', { class: 'dl-badge-inner dl-done', key: 'done', enter: 'pop', exit: 'pop',
      html: `<svg viewBox="0 0 30 30" fill="none" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="15" cy="15" r="13"/><path class="dl-check" pathLength="1" d="M8.7 15.6l4.5 4.2 8.4-9"/></svg>` });
  } else {
    const failed = item.state === 'failed';
    body = h('span', { class: cx('dl-badge-inner dl-kind', { failed, cancelled: item.state === 'cancelled' }), key: 'kind-' + (failed ? 'failed' : item.kind), enter: 'pop', exit: 'pop' },
      icon(failed ? 'exclamationmark.triangle' : kindSymbol[item.kind] || 'doc', size * 0.5 / 1.42 * 1.0, 'regular'));
  }
  return h('span', { class: 'dl-badge', 'aria-hidden': 'true' }, body);
}

function DownloadRow(item) {
  const name = item.name || T("выбор файла", "Выбор файла");
  const detail = downloadDetail(item);
  const retry = item.resumable ? T("возобновить", "Возобновить") : T("повторить", "Повторить");
  const reveal = T("показать в проводнике", "Показать в проводнике");
  let quick = null;
  if (item.active) quick = IconButton('xmark', T("отменить", "Отменить"), { size: 24, onClick: () => send('download.cancel', { id: item.id }) });
  else if (item.state === 'cancelled' || item.state === 'failed') quick = IconButton('arrow.clockwise', retry, { size: 24, onClick: () => send('download.retry', { id: item.id }) });
  else if (item.state === 'complete') quick = IconButton('folder', reveal, { size: 24, onClick: () => send('download.reveal', { id: item.id }) });
  const menu = event => openMenuBelow([
    item.state === 'complete' ? [item_(T("открыть", "Открыть"), 'download.open', item, 'arrow.up.right'), item_(reveal, 'download.reveal', item, 'folder')] : null,
    item.source ? { title: T("копировать адрес загрузки", "Копировать адрес загрузки"), symbol: 'link', action: () => send('copy', { text: item.source }) } : null,
    divider,
    item.active ? { title: T("отменить", "Отменить"), symbol: 'xmark', destructive: true, action: () => send('download.cancel', { id: item.id }) }
      : { title: T("убрать из списка", "Убрать из списка"), symbol: 'minus.circle', action: () => send('download.remove', { id: item.id }) },
  ], event.currentTarget);
  return h('div', { class: 'lib-row dl-row', key: item.id, flip: true, enter: 'fade', exit: 'fade', 'aria-label': name, 'aria-description': [detail, item.folder].filter(Boolean).join(', ') },
    h('button', { class: 'lib-main press', type: 'button', onClick: () => { if (item.state === 'complete') send('download.open', { id: item.id }); } },
      DownloadBadge(item),
      h('span', { class: 'lib-text' },
        h('span', { class: 'lib-title clip middle' }, name),
        h('span', { class: cx('lib-detail clip tabular', { danger: item.state === 'failed' }) }, detail),
        item.state === 'complete' && item.folder ? h('span', { class: 'lib-folder clip', key: 'folder', enter: 'fade' }, icon('folder', 9), h('span', { class: 'clip' }, item.folder)) : null)),
    h('span', { class: 'lib-actions wide' }, quick, IconButton('ellipsis', T("действия", "Действия"), { size: 24, onClick: menu })));
}
function item_(title, name, entry, symbol) { return { title, symbol, action: () => send(name, { id: entry.id }) }; }

function Downloads() {
  const b = box('downloads');
  const query = b.query.trim().toLocaleLowerCase();
  const rows = (state.library.downloads || []).filter(entry => !query || (entry.name || '').toLocaleLowerCase().includes(query));
  return [
    TextField(T("поиск", "Поиск"), b.query, value => update(() => { b.query = value; }, 'snappy'), { symbol: 'magnifyingglass', key: 'search' }),
    !rows.length
      ? EmptyState('arrow.down.circle', query ? T("ничего не найдено", "Ничего не найдено") : T("загрузки появятся здесь", "Загрузки появятся здесь"))
      : h('div', { class: 'lib-list scroll', key: 'list' }, grouped(rows, entry => entry.time).map(group => [h('div', { class: 'day-header', key: 'day-' + group.day, role: 'heading', 'aria-level': 3 }, dayTitle(group.day)), group.rows.map(DownloadRow)])),
  ];
}

// Extensions

function InstalledExtension(record) {
  const runnable = record.enabled && !state.window.isPrivate;
  const source = record.source && record.source.startsWith('cws:') ? ', Chrome Web Store' : '';
  const menu = event => openMenuBelow([
    item(T("настройки расширения", "Настройки расширения"), () => send('extension.options', { id: record.id }), { enabled: !!record.options && !state.window.isPrivate }),
    divider,
    item(T("удалить", "Удалить"), () => send('extension.remove', { id: record.id }), { destructive: true }),
  ], event.currentTarget);
  return h('div', { class: 'ext-card', key: record.id, flip: true, enter: 'fade', exit: 'fade' },
    h('div', { class: 'row', style: { gap: '10px' } },
      h('button', { class: 'ext-head press', type: 'button', disabled: !runnable, 'aria-label': T("открыть ", "Открыть ") + record.name, onClick: () => send('extension.action', { id: record.id }) },
        h('span', { class: cx('ext-icon', { off: !record.enabled }) }, record.icon ? h('img', { src: record.icon, alt: '', width: ROW_ICON, height: ROW_ICON }) : Monogram(record.name, ROW_ICON)),
        h('span', { class: 'lib-text' },
          h('span', { class: 'lib-title strong clip' }, record.name),
          h('span', { class: 'lib-detail clip' }, record.version + source))),
      IconButton('ellipsis', T("действия", "Действия"), { size: 26, onClick: menu }),
      Switch(record.enabled, () => send('extension.toggle', { id: record.id }), { label: record.name })),
    record.warning ? h('div', { class: 'ext-note' }, record.warning) : null,
    record.error ? h('div', { class: 'ext-note danger selectable' }, record.error) : null,
    h('div', { class: 'hairline' }),
    (record.permissions || []).length ? h('div', { class: 'ext-meta selectable' }, 'API: ' + record.permissions.join(', ')) : null,
    h('div', { class: 'ext-meta selectable' }, T("сайты: ", "Сайты: ") + ((record.hosts || []).length ? record.hosts.join(', ') : T("доступ не выдан", "доступ не выдан"))));
}

/// Chrome Web Store: install the extension open in the current tab, or paste its address or ID.
function ChromeStore() {
  const ext = state.library.extensions || {};
  const b = box('extensions');
  const busy = !!ext.installing || !!ext.busy;
  const current = ext.currentStoreItem;
  const install = () => send('extension.installFromStore', { input: b.store || '' });
  return h('div', { class: 'col', style: { gap: '8px' }, key: 'store' },
    h('div', { class: 'group-title' }, 'Chrome Web Store'),
    current ? h('div', { class: 'ext-card row', style: { gap: '10px' }, key: 'current', enter: 'fade', exit: 'fade' },
      Monogram(current.name, ROW_ICON),
      h('span', { class: 'lib-text grow' },
        h('span', { class: 'lib-title strong clip' }, current.name),
        h('span', { class: 'lib-detail' }, T("открыто в текущей вкладке", "Открыто в текущей вкладке"))),
      ext.installing === current.id ? h('span', { class: 'lib-detail' }, T("загрузка и проверка…", "Загрузка и проверка…"))
        : Button(current.installed ? T("обновить", "Обновить") : T("установить", "Установить"), { kind: current.installed ? 'secondary' : 'primary', compact: true, disabled: busy || state.window.isPrivate, onClick: () => send('extension.installFromStore', { input: current.id }) })) : null,
    TextField(T("ссылка на расширение или его ID", "Ссылка на расширение или его ID"), b.store || '', value => update(() => { b.store = value; }), { symbol: 'link', onSubmit: install, readOnly: busy || state.window.isPrivate }),
    h('div', { class: cx('lib-note', { danger: ext.status && !ext.installing }) }, ext.status || T("Enter устанавливает. mica скачивает тот же пакет, что получает Chrome, проверяет подпись разработчика и показывает права до запуска.", "Enter устанавливает. mica скачивает тот же пакет, что получает Chrome, проверяет подпись разработчика и показывает права до запуска.")),
    LinkRow(T("открыть магазин", "Открыть магазин"), 'arrow.up.right', () => send('open', { url: 'https://chromewebstore.google.com/category/extensions', newTab: true }), 'shop'));
}

function Extensions() {
  const ext = state.library.extensions || { records: [] };
  return h('div', { class: 'lib-list scroll ext-list', key: 'ext' },
    state.window.isPrivate ? h('div', { class: 'lib-note' }, T("расширения работают только в обычных окнах", "Расширения работают только в обычных окнах")) : null,
    h('div', { class: 'row' },
      h('span', { class: 'group-title grow' }, T("установленные", "Установленные")),
      Button(T("с диска…", "С диска…"), { kind: 'ghost', compact: true, disabled: !!ext.busy, onClick: () => send('extension.import') })),
    ext.records.length ? ext.records.map(InstalledExtension) : h('div', { class: 'lib-note', key: 'none' }, T("пока ничего не установлено", "Пока ничего не установлено")),
    ChromeStore());
}

export function LibraryPanel(panel) {
  let body;
  if (panel === 'extensions') body = Extensions();
  else if (panel === 'downloads') body = Downloads();
  else body = Visits(panel);
  return h('aside', { class: 'library', 'aria-label': panelTitle(panel) },
    h('div', { class: 'library-head' },
      h('div', { class: 'library-title' }, panelTitle(panel)),
      IconButton('xmark', T("закрыть панель", "Закрыть панель"), { onClick: () => send('panel.set', { panel: null }) })),
    h('div', { class: 'library-body', key: 'body-' + panel, enter: 'fade' }, body));
}
