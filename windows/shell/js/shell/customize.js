// Toolbar customization on the real window (Shell/Customize on macOS): the top bar and the bottom of the sidebar
// turn into drop zones, and a palette of every control slides over the page. Drag a control into a zone, onto
// another control to put it before that one, or back onto the palette to remove it. The context menu of each
// control offers the same moves.

import { h, cx } from '../core/dom.js';
import { icon } from '../core/icons.js';
import { T } from '../core/text.js';
import { Button, Slider } from '../ui/controls.js';
import { contextMenu, item, divider } from '../ui/menu.js';
import { dragSource, onDrop } from '../ui/drag.js';
import { state, send, layout as currentLayout, horizontal, zoneOf, zoneTitle, controlSymbol, controlTitle, toolbarControls } from './model.js';

function move(control, zone, before) { send('toolbar.move', { item: control, zone, before: before || null }); }

onDrop('tool', (control, targetId, target) => {
  const kind = target.dataset.dropKind;
  if (kind === 'palette') move(control, 'hidden');
  else if (kind === 'tile') { if (targetId !== control) move(control, zoneOf(targetId), targetId); }
  else if (kind === 'zone') {
    // Appending in a top layout: sidebar items are shown after the right-hand ones, so an item dropped at the end
    // of the right zone joins them to appear last.
    const zone = target.dataset.zone;
    if (zone === 'trailing' && horizontal(currentLayout()) && state.prefs.toolbar.sidebar.some(other => other !== control)) move(control, 'sidebar');
    else move(control, zone);
  }
});

function movesMenu(control) {
  return () => {
    const current = zoneOf(control), top = horizontal(currentLayout());
    return [
      ['leading', 'leadingInner', 'trailingInner', 'trailing', 'sidebar'].map(zone => item(zoneTitle(zone), () => move(control, zone), { checked: current === zone, enabled: current !== zone && !(zone === 'sidebar' && top) })),
      divider,
      item(T("убрать", "Убрать"), () => move(control, 'hidden'), { destructive: true, enabled: current !== 'hidden' }),
    ];
  };
}

/// Drag preview: the glyph on a raised tile.
function preview(control) {
  return () => {
    const el = document.createElement('div');
    el.className = 'edit-glyph';
    el.innerHTML = icon(controlSymbol[control], 14).props.html;
    return el;
  };
}

/// A control as it looks while customizing: same size as the live button, draggable, with an insertion caret on
/// its leading edge while another control hovers over it.
function EditTile(control) {
  const symbol = control === 'sidebar' && currentLayout() === 'right' ? 'sidebar.right' : controlSymbol[control];
  return h('div', {
    class: 'edit-tile', key: control, flip: true, enter: 'pop', exit: 'pop', title: controlTitle(control), role: 'button', tabIndex: 0, 'aria-label': controlTitle(control),
    'aria-description': T("перетащите или откройте меню действий", "Перетащите или откройте меню действий"),
    'data-drop': 'tool', 'data-drop-kind': 'tile', 'data-drop-id': control,
    onPointerDown: dragSource('tool', control, { preview: preview(control) }), onContextMenu: contextMenu(movesMenu(control)),
  }, icon(symbol, 13.5), h('span', { class: 'edit-caret' }));
}

/// One area that accepts controls: a side of the top bar or the bottom of the sidebar.
export function DropZone(zone, items, { vertical = false, width, align = 'start' } = {}) {
  return h('div', {
    class: cx('dropzone', { vertical }, 'align-' + align), key: 'zone-' + zone, title: zoneTitle(zone), role: 'group', 'aria-label': zoneTitle(zone),
    style: width != null ? { width: width + 'px' } : null, enter: 'fade', exit: 'fade',
    'data-drop': 'tool', 'data-drop-kind': 'zone', 'data-zone': zone, 'data-drop-self': '1',
  }, items.map(EditTile));
}

/// A control in the palette with where it currently lives. Placed controls stay draggable, so the palette is also
/// the way to move a control from one area to another.
function PaletteTile(control) {
  const zone = zoneOf(control), placed = zone !== 'hidden';
  return h('div', {
    class: cx('palette-tile', { placed }), key: control, role: 'button', tabIndex: 0, 'aria-label': controlTitle(control) + ', ' + zoneTitle(zone),
    onPointerDown: dragSource('tool', control, { preview: preview(control) }), onContextMenu: contextMenu(movesMenu(control)),
  },
    h('span', { class: 'palette-glyph' }, icon(controlSymbol[control], 14)),
    h('span', { class: 'palette-labels' },
      h('span', { class: 'palette-name clip' }, controlTitle(control)),
      h('span', { class: 'palette-where clip' }, placed ? zoneTitle(zone) : T("можно добавить", "Можно добавить"))));
}

/// The palette over the page: every control, the address field length and the finish action.
export function CustomizePanel() {
  const toolbar = state.prefs.toolbar;
  const top = horizontal(currentLayout());
  const done = () => send('customize.toolbar', { on: false });
  return h('div', {
    class: 'customize raised', key: 'customize', role: 'dialog', 'aria-label': T("настроить панель инструментов…", "Настроить панель инструментов…"), enter: 'palette', exit: { name: 'fade', float: false },
    'data-drop': 'tool', 'data-drop-kind': 'palette', 'data-drop-self': '1',
    onKeyDown: event => { if (event.key === 'Escape') { done(); event.stopPropagation(); } },
  }, h('div', { class: 'customize-body scroll' },
    h('div', { class: 'col', style: { gap: '4px' } },
      h('div', { class: 'customize-title' }, T("перетащите кнопки на панель", "Перетащите кнопки на панель")),
      h('div', { class: 'customize-note' }, top
        ? T("в шапке четыре места: у краёв окна и рядом с адресом. чтобы убрать кнопку, верните её сюда.", "В шапке четыре места: у краёв окна и рядом с адресом. Чтобы убрать кнопку, верните её сюда.")
        : T("в шапке четыре места: у краёв окна и рядом с адресом, ещё одно внизу боковой панели. чтобы убрать кнопку, верните её сюда.", "В шапке четыре места: у краёв окна и рядом с адресом, ещё одно внизу боковой панели. Чтобы убрать кнопку, верните её сюда."))),
    h('div', { class: 'palette' }, toolbarControls.map(PaletteTile)),
    h('div', { class: 'col', style: { gap: '12px' } },
      h('div', { class: 'row', style: { gap: '12px' } },
        h('span', { class: 'customize-label' }, T("длина адресной строки", "Длина адресной строки")),
        h('div', { style: { width: '180px', display: 'flex' } }, Slider(toolbar.addressWidth, [320, 820], value => send('toolbar.addressWidth', { value: Math.round(value) }), { label: T("длина адресной строки", "Длина адресной строки") })),
        h('span', { class: 'customize-value tabular' }, Math.round(toolbar.addressWidth) + ' px')),
      h('div', { class: 'row', style: { gap: '8px' } },
        Button(T("вернуть как было", "Вернуть как было"), { kind: 'ghost', disabled: state.toolbarIsDefault, onClick: () => send('toolbar.reset') }),
        h('span', { class: 'spacer' }),
        Button(T("готово", "Готово"), { kind: 'primary', onClick: done, autofocus: true })))));
}
