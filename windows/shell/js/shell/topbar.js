// Top bar across the whole window (Shell/TopBar on macOS). The address field is centred on the window wherever
// the tabs are and narrows before it moves; the controls come from the user's toolbar layout: at each window edge
// and right next to the field. On Windows the caption buttons take the right edge of the first row, so that side
// reserves their width, and the "…" menu stands in for the macOS menu bar.

import { h, cx } from '../core/dom.js';
import { icon, incognito } from '../core/icons.js';
import { T, keys, withKeys, quoted } from '../core/text.js';
import { geometry } from '../gen/tokens.g.js';
import { IconButton, ProgressRing, Monogram, Segmented, Switch, Button, Hairline } from '../ui/controls.js';
import { contextMenu, openMenuBelow, openPopover, closePopover, popoverOpen, item, divider } from '../ui/menu.js';
import { ProfileMark } from '../ui/profile.js';
import { state, ui, send, command, selected, layout as currentLayout, horizontal, toolbarItems, controlSymbol, controlTitle, togglePanel, toggleSidebar, newTab } from './model.js';
import { layoutEntries } from './tabs.js';
import { DropZone } from './customize.js';
import { ShortcutEditor } from './start.js';

const ITEM = geometry.chrome.item, GAP = geometry.space.small;

// Profiles from the shell: switch this window, create a profile, open profile settings.
function openProfile(profile) {
  if (profile.id === state.profile.id) return;
  send('profile.open', { id: profile.id });
}

export function profileEntries() {
  const entries = state.profiles.map(profile => ({
    title: profile.name, profile, checked: profile.id === state.profile.id, action: () => openProfile(profile),
    // Right click choices of a profile row: where to open it, regardless of the remembered answer.
    secondary: [
      item(T("открыть в новом окне", "Открыть в новом окне"), () => send('profile.open', { id: profile.id, where: 'newWindow' }), { symbol: 'macwindow.badge.plus' }),
      item(T("открыть в этом окне", "Открыть в этом окне"), () => send('profile.open', { id: profile.id, where: 'here' }), { symbol: 'macwindow', enabled: profile.id !== state.profile.id }),
      divider,
      item(T("настроить…", "Настроить…"), () => send('settings.open', { section: 'profiles', profile: profile.id }), { symbol: 'gearshape' }),
    ],
  }));
  entries.push(divider);
  if (state.profiles.length < state.profileLimit) entries.push(item(T("новый профиль…", "Новый профиль…"), () => send('profile.add'), { symbol: 'plus' }));
  entries.push(item(T("настроить профили…", "Настроить профили…"), () => send('settings.open', { section: 'profiles', profile: state.profile.id }), { symbol: 'gearshape' }));
  return entries;
}

function ProfileButton() {
  const profile = state.profile;
  const label = T("профиль: ", "Профиль: ") + profile.name;
  return h('button', { class: 'ib profile-button', type: 'button', title: label, 'aria-label': label, 'aria-haspopup': 'menu', onClick: event => openMenuBelow(profileEntries(), event.currentTarget) },
    ProfileMark(profile, 28 * 0.64, { key: profile.id }));
}

export function saveEntries() {
  const save = format => () => send('page.save', { format });
  return [
    item('PDF', save('pdf'), { symbol: 'doc.text' }),
    item(T("картинка PNG", "Картинка PNG"), save('png'), { symbol: 'photo' }),
    item(T("картинка JPEG", "Картинка JPEG"), save('jpeg'), { symbol: 'camera' }),
    item('HTML', save('html'), { symbol: 'chevron.left.forwardslash.chevron.right' }),
  ];
}

let saveButton = null;
/// Ctrl+S: the save button opens its format menu; with the button hidden the menu opens under the address.
export function openSaveMenu() {
  const tab = selected();
  if (!tab || !tab.canSave) return;
  const anchor = saveButton && saveButton.isConnected ? saveButton : document.querySelector('.pill');
  if (anchor) openMenuBelow(saveEntries(), anchor);
}

let menuButton = null;
/// F10 or Alt+F.
export function openAppMenu() { if (menuButton && menuButton.isConnected) openMenuBelow(appMenu(), menuButton); }

/// The menu that stands in for the macOS menu bar: every command that lives only in the macOS menus is here,
/// with its Windows shortcut.
export function appMenu() {
  const tab = selected();
  const live = !!tab && !!tab.url && !tab.start;
  const run = name => () => command(name);
  const zoomed = tab && tab.zoom && Math.abs(tab.zoom - 1) > 0.001;
  return [
    item(T("новая вкладка", "Новая вкладка"), run('tab'), { symbol: 'plus', keys: keys('tab') }),
    item(T("новое окно", "Новое окно"), run('newWindow'), { symbol: 'macwindow', keys: keys('newWindow') }),
    item(T("новое окно инкогнито", "Новое окно инкогнито"), run('private'), { symbol: incognito, keys: keys('private') }),
    item(T("восстановить вкладку", "Восстановить вкладку"), run('reopen'), { symbol: 'arrow.counterclockwise', enabled: state.closedCount > 0, keys: keys('reopen') }),
    divider,
    item(T("история", "История"), run('history'), { symbol: 'clock', keys: keys('history') }),
    item(T("закладки", "Закладки"), () => togglePanel('bookmarks'), { symbol: 'bookmark' }),
    item(T("загрузки", "Загрузки"), run('downloads'), { symbol: 'arrow.down.circle', keys: keys('downloads') }),
    item(T("расширения", "Расширения"), run('extensions'), { symbol: 'puzzlepiece.extension', keys: keys('extensions') }),
    item(T("очистить историю…", "Очистить историю…"), run('clearData'), { symbol: 'trash', keys: keys('clearData') }),
    divider,
    item(T("найти на странице", "Найти на странице"), run('find'), { symbol: 'text.magnifyingglass', enabled: live, keys: keys('find') }),
    item(T("сохранить страницу как…", "Сохранить страницу как…"), run('save'), { symbol: 'square.and.arrow.down', enabled: !!tab && tab.canSave, keys: keys('save') }),
    item(T("печать…", "Печать…"), run('print'), { symbol: 'printer', enabled: live, keys: keys('print') }),
    item(T("увеличить", "Увеличить"), run('zoomIn'), { symbol: 'plus', enabled: live, keys: keys('zoomIn') }),
    item(T("уменьшить", "Уменьшить"), run('zoomOut'), { symbol: 'minus', enabled: live, keys: keys('zoomOut') }),
    item(T("исходный масштаб", "Исходный масштаб") + (zoomed ? ` (${Math.round(tab.zoom * 100)}%)` : ''), run('zoomReset'), { enabled: !!zoomed, keys: keys('zoomReset') }),
    item(T("полноэкранный режим", "Полноэкранный режим"), run('fullscreen'), { symbol: 'arrow.up.left.and.arrow.down.right', keys: keys('fullscreen') }),
    item(T("инструменты разработчика", "Инструменты разработчика"), run('devTools'), { enabled: live, keys: keys('devTools') }),
    divider,
    state.profiles.length > 1 ? state.profiles.map(profile => ({ title: profile.name, profile, checked: profile.id === state.profile.id, action: () => openProfile(profile) })) : null,
    item(T("настроить профили…", "Настроить профили…"), () => send('settings.open', { section: 'profiles', profile: state.profile.id }), { symbol: 'person.crop.circle' }),
    divider,
    item(T("настроить панель инструментов…", "Настроить панель инструментов…"), () => send('customize.toolbar', { on: true }), { symbol: 'slider.horizontal.3' }),
    layoutEntries(),
    divider,
    item(T("настройки…", "Настройки…"), run('settings'), { symbol: 'gearshape', keys: keys('settings') }),
    item(T("о mica", "О mica"), () => send('settings.open', { section: 'about' }), { symbol: 'info.circle' }),
    item(T("завершить mica", "Завершить mica"), () => send('app.quit'), { keys: keys('quit') }),
  ];
}

/// One configurable control. The same item works in the top bar, at the bottom of the sidebar and in the rail.
export function ToolbarButton(control, edge, inSidebar) {
  const tab = selected();
  const wrap = body => h('span', { class: 'tool', key: control, flip: true, enter: 'pop', exit: 'pop' }, body);
  switch (control) {
    case 'sidebar': {
      const collapsed = state.prefs.sidebarCollapsed;
      return wrap(IconButton(edge === 'right' ? 'sidebar.right' : 'sidebar.left', withKeys(collapsed ? T("развернуть боковую панель", "Развернуть боковую панель") : T("свернуть боковую панель", "Свернуть боковую панель"), 'sidebar'), { onClick: toggleSidebar }));
    }
    case 'back': return wrap(IconButton('chevron.left', T("назад", "Назад"), { disabled: !tab || !tab.canBack, onClick: () => command('back') }));
    case 'forward': return wrap(IconButton('chevron.right', T("вперёд", "Вперёд"), { disabled: !tab || !tab.canForward, onClick: () => command('forward') }));
    case 'reload': {
      const loading = !!tab && tab.loading;
      return wrap(h('button', {
        class: 'ib', type: 'button', disabled: !tab || !tab.url, title: loading ? T("остановить", "Остановить") : withKeys(T("перезагрузить", "Перезагрузить"), 'reload'),
        'aria-label': loading ? T("остановить", "Остановить") : T("перезагрузить", "Перезагрузить"), onClick: () => send(loading ? 'tab.stop' : 'tab.reload', { id: tab.id }),
      }, h('span', { class: 'swap', key: loading ? 'stop' : 'reload', enter: 'pop', exit: 'pop' }, icon(loading ? 'xmark' : 'arrow.clockwise', 28 * 0.48))));
    }
    case 'newTab': return wrap(IconButton('plus', withKeys(controlTitle(control), 'tab'), { onClick: newTab }));
    case 'incognito': return wrap(IconButton(incognito, withKeys(T("новое окно инкогнито", "Новое окно инкогнито"), 'private'), { onClick: () => command('private') }));
    case 'bookmarks': case 'history': case 'downloads': case 'extensions':
      return wrap(IconButton(controlSymbol[control], controlTitle(control), { selected: state.panel === control, onClick: () => togglePanel(control) }));
    case 'settings': return wrap(IconButton('gearshape', withKeys(controlTitle(control), 'settings'), { onClick: () => send('settings.open', {}) }));
    case 'profile': return wrap(ProfileButton());
    case 'save': {
      // While a page of this tab is being written the button shows its progress in place of the glyph.
      const saving = state.saving;
      const disabled = !tab || !tab.canSave || (tab.loading && tab.progress < 0.1);
      return wrap(h('span', { class: 'save-button' },
        saving
          ? h('span', { class: 'saving', key: 'saving', title: T("сохраняется", "Сохраняется"), role: 'img', 'aria-label': T("сохраняется", "Сохраняется"), enter: 'fade', exit: 'fade' }, ProgressRing(saving.fraction, 16))
          : h('span', { key: 'button', enter: 'fade', exit: 'fade' }, IconButton('square.and.arrow.down', withKeys(controlTitle(control), 'save'), { disabled, ref: el => { saveButton = el; }, onClick: event => openMenuBelow(saveEntries(), event.currentTarget) }))));
    }
    default: return null;
  }
}

const capabilityName = capability => {
  switch (capability) {
    case 'camera': return T("камера", "Камера");
    case 'microphone': return T("микрофон", "Микрофон");
    case 'notifications': return T("уведомления", "Уведомления");
    default: return T("геолокация", "Геолокация");
  }
};
export { capabilityName };

function SiteInfo() {
  const tab = selected(), site = state.site;
  if (!tab || !site) return null;
  const decisions = [{ value: 'ask', title: T("спрашивать", "Спрашивать") }, { value: 'allow', title: T("разрешить", "Разрешить") }, { value: 'deny', title: T("запретить", "Запретить") }];
  return h('div', { class: 'siteinfo' },
    h('div', { class: 'siteinfo-head' },
      Monogram(tab.host, 32),
      h('div', { class: 'col grow', style: { gap: '2px' } },
        h('div', { class: 'siteinfo-name clip selectable' }, site.fileName || tab.host || 'mica'),
        h('div', { class: 'siteinfo-line' },
          icon(site.fileName ? 'doc' : tab.secure ? 'lock.fill' : 'exclamationmark.shield', 11.5),
          h('span', null, site.fileName ? T("локальный файл на этом компьютере", "Локальный файл на этом компьютере") : tab.secure ? T("соединение HTTPS", "Соединение HTTPS") : T("защищённое соединение не подтверждено", "Защищённое соединение не подтверждено"))))),
    site.filePath ? h('div', { class: 'siteinfo-note selectable' }, site.filePath) : null,
    site.host ? [
      h('label', { class: 'toggle-row siteinfo-toggle', key: 'blocking' },
        h('span', { class: 'grow' }, T("блокировка рекламы на сайте", "Блокировка рекламы на сайте")),
        Switch(site.blocking, value => send('site.blocking', { host: site.host, on: value }), { label: T("блокировка рекламы на сайте", "Блокировка рекламы на сайте") })),
      h('div', { class: 'siteinfo-note', key: 'blocking-note' }, T("правила применяются к новым запросам; перезагрузите страницу для полной проверки", "Правила применяются к новым запросам; перезагрузите страницу для полной проверки")),
    ] : null,
    site.origin ? [
      Hairline(),
      site.permissions.map(permission => h('div', { class: 'siteinfo-capability', key: permission.capability },
        h('div', { class: 'siteinfo-label' }, capabilityName(permission.capability)),
        Segmented(permission.decision, decisions, value => send('site.permission', { origin: site.origin, capability: permission.capability, decision: value }), { compact: true, fill: true, label: capabilityName(permission.capability) }))),
    ] : null,
    tab.capturing ? h('div', { class: 'row', style: { gap: '8px' } },
      h('span', { class: 'siteinfo-live grow' }, icon('mic.fill', 12), T("идёт запись с камеры или микрофона", "Идёт запись с камеры или микрофона")),
      Button(T("остановить", "Остановить"), { compact: true, onClick: () => send('site.stopCapture', { id: tab.id }) })) : null);
}

/// A page address drawn the way the address field shows it: the site's own domain in ink, the parts the user chose
/// to quiet in text2. The host splits it with the shared AddressDisplay rule.
export function AddressText(parts) {
  return parts.map((part, index) => h('span', { class: part.dim ? 'addr-dim' : 'addr-ink', key: index }, part.text));
}

function AddressPill(tab, style) {
  const control = geometry.chrome.field - 6;
  const pinning = popoverOpen('pin');
  const symbol = state.window.isPrivate ? incognito : tab.secure ? 'lock.fill' : !tab.url ? 'magnifyingglass' : tab.local ? 'doc' : 'exclamationmark.shield';
  return h('div', { class: cx('pill', { pinning, loading: tab.loading }), key: 'pill', style },
    IconButton(symbol, T("сведения о сайте", "Сведения о сайте"), { size: control, disabled: !tab.url, onClick: event => popoverOpen('siteinfo') ? closePopover() : openPopover('siteinfo', event.currentTarget, SiteInfo, { width: 320 }) }),
    h('button', {
      class: 'pill-address', type: 'button', 'aria-label': T("адресная строка: ", "Адресная строка: ") + (tab.url || ''), title: withKeys(T("адрес или поиск", "Адрес или поиск"), 'address'),
      onClick: () => send('commandBar', { on: true }),
    }, tab.url ? h('span', { class: 'clip' }, AddressText(tab.address || [{ text: tab.url, dim: false }])) : h('span', { class: 'pill-placeholder clip' }, T("адрес или поиск", "Адрес или поиск"))),
    tab.storeExtension ? h('span', { key: 'install', enter: 'fade', exit: 'fade' }, IconButton('puzzlepiece.extension', T("установить расширение в mica", "Установить расширение в mica"), { size: control, onClick: () => send('extensions.installFromPage', { id: tab.id }) })) : null,
    IconButton(tab.pinnedToStart ? 'pin.fill' : 'pin', tab.pinnedToStart ? T("удалить с начальной страницы", "Удалить с начальной страницы") : T("закрепить в своих сайтах", "Закрепить в своих сайтах"), {
      size: control, disabled: !tab.pinnable, cls: cx('pill-hover', { shown: pinning }), key: 'pin',
      // A pinned page comes off at once; a new one opens the form to give it a name first.
      onClick: event => { if (tab.pinnedToStart) send('start.unpinPage', { url: tab.url }); else openPopover('pin', event.currentTarget, () => ShortcutEditor({ page: tab.url, done: () => closePopover('pin') }), { sticky: true }); },
    }),
    IconButton(tab.bookmarked ? 'bookmark.fill' : 'bookmark', withKeys(T("добавить или удалить закладку", "Добавить или удалить закладку"), 'bookmark'), {
      size: control, disabled: !tab.url || tab.local, cls: cx('pill-hover', { shown: tab.bookmarked && !tab.local }), key: 'bookmark', onClick: () => command('bookmark'),
    }),
    // Load progress: flush with the bottom edge from the very left, clipped by the field's own shape.
    h('span', { class: 'pill-progress', 'aria-hidden': 'true' }, h('span', { style: { width: Math.min(1, tab.progress || 0) * 100 + '%' } })));
}

function PrivateBadge() {
  const label = T("окно инкогнито", "Окно инкогнито");
  return h('span', { class: 'private-badge', key: 'private', title: label, role: 'img', 'aria-label': label }, icon(incognito, 13));
}

export function TopBar(layout, windowWidth, topRow) {
  const items = toolbarItems();
  const edge = horizontal(layout) ? null : layout;
  const editing = state.overlay.customizingToolbar;
  const tab = selected();
  const span = list => list.length * ITEM;
  const badge = state.window.isPrivate && !editing ? ITEM : 0;
  const leadingInset = GAP;
  // The caption buttons sit in the first row of the window; in full screen they are gone.
  const caption = topRow && !state.window.fullScreen ? state.system.captionInset : 0;
  const menu = ITEM;
  // Controls next to the field get the same width on both sides, so the field stays on the centre line.
  const inner = editing ? Math.max(44, Math.max(span(items.leadingInner), span(items.trailingInner)) + 4) : Math.max(span(items.leadingInner), span(items.trailingInner));
  const innerRoom = inner > 0 || editing ? inner + GAP : 0;
  const edgeLeading = editing ? Math.max(48, span(items.leading) + 4 + ITEM) : span(items.leading);
  const edgeTrailing = editing ? Math.max(48, span(items.trailing) + 4 + ITEM) : span(items.trailing) + badge;
  const leading = leadingInset + edgeLeading + GAP + innerRoom;
  const trailing = caption + GAP + menu + edgeTrailing + GAP + innerRoom;
  // Equal room on both sides keeps the field on the window's centre line; it narrows before it moves.
  const room = windowWidth - 2 * Math.max(leading, trailing);
  const width = Math.max(0, Math.min(state.prefs.toolbar.addressWidth, room));
  const centred = width >= 200 || editing;
  const buttons = list => list.map(control => ToolbarButton(control, edge, false));
  const menuControl = h('span', { class: 'tool', key: 'app-menu', flip: true }, IconButton('ellipsis', withKeys(T("меню mica", "Меню mica"), 'menu'), { ref: el => { menuButton = el; }, onClick: event => openMenuBelow(appMenu(), event.currentTarget) }));

  let pillStyle;
  if (centred) pillStyle = { left: (windowWidth - width) / 2 + 'px', width: width + 'px' };
  else {
    // Too narrow to centre: the field takes the space between the side groups.
    const flowLeading = leadingInset + span(items.leading) + span(items.leadingInner);
    const flowTrailing = caption + GAP + menu + span(items.trailing) + span(items.trailingInner) + badge;
    pillStyle = { left: flowLeading + GAP + 'px', width: Math.max(0, windowWidth - flowLeading - flowTrailing - 2 * GAP) + 'px' };
  }

  let body;
  if (editing) {
    const half = windowWidth / 2 - width / 2 - GAP - inner - GAP;
    body = h('div', { class: 'tb-zones', key: 'zones', enter: 'fade', exit: 'fade' },
      h('div', { style: { width: leadingInset + 'px' } }),
      DropZone('leading', items.leading, { width: Math.max(0, half - leadingInset), align: 'start' }),
      h('div', { style: { width: GAP + 'px' } }),
      DropZone('leadingInner', items.leadingInner, { width: inner, align: 'end' }),
      h('div', { style: { width: width + 2 * GAP + 'px' } }),
      DropZone('trailingInner', items.trailingInner, { width: inner, align: 'start' }),
      h('div', { style: { width: GAP + 'px' } }),
      DropZone('trailing', items.trailing, { width: Math.max(0, half - GAP - caption), align: 'end' }));
  } else {
    body = [
      h('div', { class: 'tb-row', key: 'row', style: { 'padding-left': leadingInset + 'px', 'padding-right': caption + GAP + 'px' }, enter: 'fade', exit: 'fade' },
        buttons(items.leading), centred ? null : buttons(items.leadingInner),
        h('span', { class: 'spacer', key: 'spacer' }),
        centred ? null : buttons(items.trailingInner), buttons(items.trailing),
        state.window.isPrivate ? PrivateBadge() : null, menuControl),
      centred && inner > 0 ? h('div', { class: 'tb-inner', key: 'inner', style: { left: (windowWidth - width) / 2 - GAP - inner + 'px', width: width + 2 * GAP + 2 * inner + 'px' } },
        h('div', { class: 'tb-inner-side end', style: { width: inner + 'px' } }, buttons(items.leadingInner)),
        h('div', { class: 'spacer' }),
        h('div', { class: 'tb-inner-side', style: { width: inner + 'px' } }, buttons(items.trailingInner))) : null,
    ];
  }

  return h('div', {
    class: cx('topbar', { editing }), key: 'topbar', role: 'toolbar', 'aria-label': T("панель инструментов", "Панель инструментов"),
    onContextMenu: editing ? null : contextMenu(() => [item(T("настроить панель инструментов…", "Настроить панель инструментов…"), () => send('customize.toolbar', { on: true }), { symbol: 'slider.horizontal.3' }), divider, layoutEntries()]),
  }, body, tab ? AddressPill(tab, pillStyle) : null);
}

export { quoted };
