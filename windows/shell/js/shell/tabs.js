// Tabs: rows in the sidebar, pinned tiles, the rail of site icons and the horizontal strip
// (Shell/Tabs on macOS). Sizes, fills and transitions follow TabRow.swift, Rail.swift, Sidebar.swift and TabStrip.swift.

import { h, cx } from '../core/dom.js';
import { icon } from '../core/icons.js';
import { T, keys, withKeys } from '../core/text.js';
import { IconButton, KeyHint, SiteIcon, ProgressRing, Hairline } from '../ui/controls.js';
import { contextMenu, item, divider } from '../ui/menu.js';
import { dragSource, onDrop } from '../ui/drag.js';
import { state, send, tabTitle, selectTab, closeTab, newTab, toolbarItems, setLayout, toggleSidebar, layout as currentLayout } from './model.js';
import { ToolbarButton } from './topbar.js';
import { DropZone } from './customize.js';

onDrop('tab', (id, before) => { if (before && before !== id) send('tab.move', { id, before }); });

/// Tab status: microphone or camera in use, a crashed page, load progress, otherwise the site icon
/// (dimmed until a restored tab loads).
export function TabIcon(tab, size = 16, plain = false) {
  let body, key;
  if (tab.capturing) { body = h('span', { class: 'tab-status live' }, icon('mic.fill', size * 0.7)); key = 'mic'; }
  else if (tab.phase === 'terminated') { body = h('span', { class: 'tab-status' }, icon('exclamationmark.triangle', size * 0.7)); key = 'failed'; }
  else if (tab.loading) { body = ProgressRing(tab.progress, size); key = 'ring'; }
  else { body = SiteIcon(tab, size, plain); key = 'site'; }
  return h('span', { class: cx('tab-icon', { dim: tab.phase === 'restored' && !tab.loading }), style: { width: size + 'px', height: size + 'px' } },
    h('span', { class: 'tab-icon-body', key, enter: 'fade' }, body));
}

export function tabMenu(tab) {
  return () => [
    item(T("дублировать", "Дублировать"), () => send('tab.duplicate', { id: tab.id }), { symbol: 'plus.square.on.square' }),
    item(tab.pinned ? T("открепить", "Открепить") : T("закрепить", "Закрепить"), () => send('tab.pin', { id: tab.id }), { symbol: tab.pinned ? 'pin.slash' : 'pin' }),
    item(T("перезагрузить", "Перезагрузить"), () => send('tab.reload', { id: tab.id }), { symbol: 'arrow.clockwise', enabled: !!tab.url }),
    item(T("копировать адрес", "Копировать адрес"), () => send('tab.copyAddress', { id: tab.id }), { symbol: 'link', enabled: !!tab.url }),
    item(T("открыть в новом окне", "Открыть в новом окне"), () => send('tab.toNewWindow', { id: tab.id }), { symbol: 'macwindow' }),
    divider,
    item(T("закрыть остальные", "Закрыть остальные"), () => send('tab.closeOthers', { id: tab.id }), { symbol: 'square.on.square.dashed' }),
    item(T("закрыть все", "Закрыть все"), () => send('tab.closeAll'), { symbol: 'rectangle.on.rectangle.slash' }),
    item(T("закрыть вкладку", "Закрыть вкладку"), () => closeTab(tab.id), { symbol: 'xmark', keys: keys('close') }),
  ];
}

/// Drag to reorder, the tab menu and closing with the middle button, shared by rows, pinned tiles and rail tiles.
function interactions(tab) {
  return {
    'data-drop': 'tab', 'data-drop-id': tab.id,
    onPointerDown: dragSource('tab', tab.id),
    onContextMenu: contextMenu(tabMenu(tab)),
    onAuxClick: event => { if (event.button === 1) { closeTab(tab.id); event.preventDefault(); } },
  };
}

function accessibleName(tab) { return (tab.pinned ? T("закреплена: ", "Закреплена: ") : '') + tabTitle(tab); }

export function TabRow(tab, isHorizontal, style) {
  const isSelected = state.selectedId === tab.id;
  const title = tabTitle(tab);
  return h('div', {
    class: cx('tab', { selected: isSelected, h: isHorizontal, restored: tab.phase === 'restored', pinned: tab.pinned }),
    key: tab.id, flip: !isHorizontal, enter: 'pop', exit: 'pop', style, ...interactions(tab),
  },
    h('button', {
      class: 'tab-main press', type: 'button', role: 'tab', 'aria-selected': isSelected ? 'true' : 'false', 'aria-label': accessibleName(tab),
      'aria-description': isSelected ? T("выбрана", "Выбрана") : tab.phase === 'restored' ? T("ещё не загружена", "Ещё не загружена") : null,
      onClick: () => selectTab(tab.id),
    }, TabIcon(tab), h('span', { class: 'tab-title clip' }, title)),
    isHorizontal && tab.pinned ? h('span', { class: 'tab-pin', 'aria-hidden': 'true' }, icon('pin', 10, 'regular')) : null,
    IconButton('xmark', T("закрыть: ", "Закрыть: ") + title, { size: 22, cls: 'tab-close', onClick: event => { event.stopPropagation(); closeTab(tab.id); } }));
}

/// Close badge of an icon-only tab tile: a small raised round button on the tile's top right corner, half over the
/// tile and half outside. It appears after the pointer rests on the tile (motion.hoverIntent), in CSS.
function CloseBadge(tab) {
  const label = T("закрыть: ", "Закрыть: ") + tabTitle(tab);
  return h('button', {
    class: 'tile-badge', type: 'button', title: label, 'aria-label': label, tabIndex: -1,
    onClick: event => { event.stopPropagation(); closeTab(tab.id); },
    onPointerDown: event => event.stopPropagation(),
  }, h('span', { class: 'tile-badge-face' }, icon('xmark', 7.5, 'semibold')));
}

export function PinnedTile(tab) {
  const isSelected = state.selectedId === tab.id;
  return h('div', { class: cx('tile pinned-tile', { selected: isSelected }), key: tab.id, flip: true, enter: 'pop', exit: 'pop', ...interactions(tab) },
    h('button', { class: 'tile-main press', type: 'button', title: tab.title || tab.host || '', 'aria-label': T("закреплена: ", "Закреплена: ") + tabTitle(tab), 'aria-pressed': isSelected ? 'true' : 'false', onClick: () => selectTab(tab.id) },
      TabIcon(tab, 20)),
    CloseBadge(tab));
}

/// Site icon of a tab in the collapsed sidebar; same interactions as a tab row.
export function RailTile(tab) {
  const isSelected = state.selectedId === tab.id;
  return h('div', { class: cx('tile rail-tile', { selected: isSelected }), key: tab.id, flip: true, enter: 'pop', exit: 'pop', ...interactions(tab) },
    h('button', { class: 'tile-main press', type: 'button', title: tabTitle(tab), 'aria-label': accessibleName(tab), 'aria-pressed': isSelected ? 'true' : 'false', onClick: () => selectTab(tab.id) },
      TabIcon(tab, 20, true)),
    tab.pinned ? h('span', { class: 'rail-pin', 'aria-hidden': 'true' }, icon('pin', 8, 'bold')) : null,
    CloseBadge(tab));
}

function RailPlus() {
  return h('button', { class: 'tile-main rail-plus press', type: 'button', key: 'plus', flip: true, title: withKeys(T("новая вкладка", "Новая вкладка"), 'tab'), 'aria-label': T("новая вкладка", "Новая вкладка"), onClick: newTab },
    icon('plus', 13));
}

function NewTabRow() {
  return h('button', { class: 'newtab-row press', type: 'button', key: 'newtab', flip: true, onClick: newTab },
    h('span', { class: 'newtab-plus' }, icon('plus', 12)),
    h('span', { class: 'grow clip' }, T("новая вкладка", "Новая вкладка")),
    KeyHint(keys('tab'), { class: 'newtab-keys' }));
}

function layoutEntries() {
  const current = state.prefs.layout;
  return [
    item(T("боковая панель слева", "Боковая панель слева"), () => setLayout('left'), { symbol: 'sidebar.left', checked: current === 'left' }),
    item(T("вкладки под адресом", "Вкладки под адресом"), () => setLayout('top'), { symbol: 'rectangle.topthird.inset.filled', checked: current === 'top' }),
    item(T("вкладки над адресом", "Вкладки над адресом"), () => setLayout('tabsAbove'), { symbol: 'macwindow', checked: current === 'tabsAbove' }),
    item(T("боковая панель справа", "Боковая панель справа"), () => setLayout('right'), { symbol: 'sidebar.right', checked: current === 'right' }),
  ];
}
export { layoutEntries };

const customizeEntry = () => item(T("настроить панель инструментов…", "Настроить панель инструментов…"), () => send('customize.toolbar', { on: true }), { symbol: 'slider.horizontal.3' });

function sidebarMenu(edge) {
  return () => [
    item(T("новая вкладка", "Новая вкладка"), newTab, { symbol: 'plus' }),
    item(state.prefs.sidebarCollapsed ? T("развернуть боковую панель", "Развернуть боковую панель") : T("свернуть боковую панель", "Свернуть боковую панель"), toggleSidebar, { symbol: edge === 'right' ? 'sidebar.right' : 'sidebar.left' }),
    divider, layoutEntries(), divider, customizeEntry(),
  ];
}

/// Menu of the strip's free space, in both horizontal layouts: a new tab, the tab layout and the toolbar editor.
export function stripMenu() {
  return [item(T("новая вкладка", "Новая вкладка"), newTab, { symbol: 'plus' }), divider, layoutEntries(), divider, customizeEntry()];
}

export function Sidebar(edge, compact) {
  const pinned = state.tabs.filter(tab => tab.pinned);
  const regular = state.tabs.filter(tab => !tab.pinned);
  const footer = toolbarItems().sidebar;
  const editing = state.overlay.customizingToolbar;
  return h('div', { class: cx('sidebar', edge), key: 'sidebar-' + edge, onContextMenu: contextMenu(sidebarMenu(edge)), exit: { name: 'fade', float: false } },
    compact
      ? h('div', { class: 'rail', key: 'rail', enter: 'fade', exit: 'fade', role: 'tablist', 'aria-orientation': 'vertical' },
          pinned.map(RailTile),
          pinned.length ? h('div', { class: 'hairline rail-rule', key: 'rule', flip: true }) : null,
          h('div', { class: 'rail-scroll scroll', key: 'scroll' }, regular.map(RailTile), RailPlus()),
          h('div', { class: 'spacer', key: 'spacer' }),
          editing ? DropZone('sidebar', footer, { vertical: true }) : footer.map(control => ToolbarButton(control, edge, true)))
      : h('div', { class: 'sidebar-full', key: 'full', enter: 'fade', exit: 'fade' },
          pinned.length ? h('div', { class: 'pinned-grid', key: 'pinned', role: 'tablist' }, pinned.map(PinnedTile)) : null,
          NewTabRow(),
          h('div', { class: 'hairline sidebar-rule', key: 'rule', flip: true }),
          h('div', { class: 'tab-list scroll', key: 'list', role: 'tablist', 'aria-orientation': 'vertical' }, regular.map(tab => TabRow(tab, false))),
          h('div', { class: 'spacer', key: 'spacer' }),
          editing ? DropZone('sidebar', footer, {}) : footer.length ? h('div', { class: 'sidebar-footer', key: 'footer' }, footer.map(control => ToolbarButton(control, edge, true))) : null));
}

/// Horizontal tabs share the width evenly; the new-tab button sits right after the last tab, in the tab colour.
/// In the title bar band (`titleBand`) the strip keeps free space at its end, where the window can still be dragged.
/// Tabs are placed by x and width, as SwiftUI places them, so a new tab appears in its slot while the others move.
export function TabStrip(titleBand, width) {
  const tabs = state.tabs;
  const plus = 32, gap = 4, dragRoom = 64;
  const available = Math.max(0, width - (titleBand ? dragRoom : 0));
  const fixed = plus + tabs.length * gap;
  const each = tabs.length === 0 ? 0 : Math.min(240, Math.max(130, (available - fixed) / tabs.length));
  const content = fixed + tabs.length * each;
  return h('div', { class: cx('strip', { band: titleBand }), key: 'strip', role: 'tablist', onContextMenu: contextMenu(stripMenu) },
    h('div', {
      class: 'strip-scroll scroll', style: { width: titleBand ? Math.max(0, Math.min(content, available)) + 'px' : null },
      // A mouse wheel turns vertically; the strip scrolls sideways, as a trackpad swipe does on macOS.
      onWheel: event => { const el = event.currentTarget; if (Math.abs(event.deltaY) > Math.abs(event.deltaX) && el.scrollWidth > el.clientWidth) { el.scrollLeft += event.deltaY; event.preventDefault(); } },
    },
      h('div', { class: 'strip-track', style: { width: content + 'px' } },
        tabs.map((tab, index) => TabRow(tab, true, { width: each + 'px', transform: `translateX(${index * (each + gap)}px)` })),
        h('button', {
          class: 'strip-plus press', type: 'button', key: 'plus', title: withKeys(T("новая вкладка", "Новая вкладка"), 'tab'), 'aria-label': T("новая вкладка", "Новая вкладка"),
          style: { transform: `translateX(${tabs.length * (each + gap)}px)` }, onClick: newTab,
        }, icon('plus', 12)))));
}

export { Hairline, currentLayout };
