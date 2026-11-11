// What the shell derives from the host's snapshot, and the commands it sends back.
//
// The snapshot (Mica.Bridge.ShellState in C#) is the single source of truth; nothing here keeps a copy of it.

import { state, ui, update, animate } from '../core/app.js';
import { send } from '../core/host.js';
import { T } from '../core/text.js';

export const NARROW = 760;

/// Layout of a window this wide: a narrow window keeps a top layout as chosen and moves the sidebar ones to "top".
export function layout() {
  const chosen = state.prefs.layout;
  return window.innerWidth < NARROW && (chosen === 'left' || chosen === 'right') ? 'top' : chosen;
}
export const horizontal = value => value === 'top' || value === 'tabsAbove';
export function selected() { return state.tabs.find(tab => tab.id === state.selectedId) || null; }
export function tabTitle(tab) { return tab.title || tab.host || T("новая вкладка", "Новая вкладка"); }
export function isStart(tab) { return !!tab && tab.start; }

/// A keyboard command from shared/keymap.json, run by the host exactly as its shortcut would.
export function command(name) { send('command', { name }); }

export function newTab() { send('tab.new'); }
export function selectTab(id) { if (id !== state.selectedId) send('tab.select', { id }); }
export function closeTab(id) { send('tab.close', { id }); }
export function togglePanel(panel) { send('panel.set', { panel: state.panel === panel ? null : panel }); }

/// Changes one preference of the window's profile. `path` is a dotted key of Preferences.
export function setPref(path, value) { send('prefs.set', { path, value }); }

export function setLayout(value) { send('prefs.set', { path: 'layout', value }); }
export function toggleSidebar() { send('prefs.set', { path: 'sidebarCollapsed', value: !state.prefs.sidebarCollapsed }); }

/// A window-level card covers the page; the web view takes no input meanwhile.
export function modalOpen() {
  const o = state.overlay;
  return o.settings || o.onboarding || o.clearData || !!o.profilePrompt || !!o.alert;
}

/// Something of the shell is drawn over the page area, so the host must put the shell above the page.
export function coversPage() {
  const o = state.overlay;
  return modalOpen() || o.commandBar || o.customizingToolbar || !!ui.menu || !!ui.popover || !!o.quitHold;
}

export function toolbarItems() {
  const t = state.prefs.toolbar;
  if (!horizontal(layout())) return { leading: t.leading, leadingInner: t.leadingInner, trailingInner: t.trailingInner, trailing: t.trailing, sidebar: t.sidebar };
  // Without a sidebar its items move to the right side of the bar, and the sidebar toggle has nothing to act on.
  const drop = list => list.filter(item => item !== 'sidebar');
  return { leading: drop(t.leading), leadingInner: drop(t.leadingInner), trailingInner: drop(t.trailingInner), trailing: drop(t.trailing.concat(t.sidebar)), sidebar: [] };
}

export function zoneOf(item) {
  const t = state.prefs.toolbar;
  for (const zone of ['leading', 'leadingInner', 'trailingInner', 'trailing', 'sidebar']) if (t[zone].includes(item)) return zone;
  return 'hidden';
}

export const toolbarControls = ['sidebar', 'back', 'forward', 'reload', 'newTab', 'bookmarks', 'history', 'downloads', 'extensions', 'incognito', 'settings', 'profile', 'save'];

export const controlSymbol = {
  sidebar: 'sidebar.left', back: 'chevron.left', forward: 'chevron.right', reload: 'arrow.clockwise', newTab: 'plus', bookmarks: 'bookmark',
  history: 'clock', downloads: 'arrow.down.circle', extensions: 'puzzlepiece.extension', incognito: 'mica.incognito', settings: 'gearshape',
  profile: 'person.crop.circle', save: 'square.and.arrow.down',
};

export function controlTitle(item) {
  switch (item) {
    case 'sidebar': return T("боковая панель", "Боковая панель");
    case 'back': return T("назад", "Назад");
    case 'forward': return T("вперёд", "Вперёд");
    case 'reload': return T("перезагрузить", "Перезагрузить");
    case 'newTab': return T("новая вкладка", "Новая вкладка");
    case 'bookmarks': return T("закладки", "Закладки");
    case 'history': return T("история", "История");
    case 'downloads': return T("загрузки", "Загрузки");
    case 'extensions': return T("расширения", "Расширения");
    case 'incognito': return T("окно инкогнито", "Окно инкогнито");
    case 'settings': return T("настройки", "Настройки");
    case 'profile': return T("профиль", "Профиль");
    case 'save': return T("сохранить страницу", "Сохранить страницу");
    default: return item;
  }
}

export function zoneTitle(zone) {
  switch (zone) {
    case 'leading': return T("у левого края", "У левого края");
    case 'leadingInner': return T("слева от адреса", "Слева от адреса");
    case 'trailingInner': return T("справа от адреса", "Справа от адреса");
    case 'trailing': return T("у правого края", "У правого края");
    case 'sidebar': return T("в боковой панели", "В боковой панели");
    default: return T("не показывается", "Не показывается");
  }
}

export { state, ui, update, animate, send };
