// Shell menus and popovers drawn by mica (MicaMenu and StickyPopover on macOS).
// One menu at a time; it closes on a click elsewhere, Esc, a choice, a resize or when the window loses focus.
// A menu entry: { title, symbol?, keys?, enabled?, checked?, destructive?, profile?, action, secondary? } or "divider".

import { h, cx } from '../core/dom.js';
import { icon } from '../core/icons.js';
import { ui, update, invalidate } from '../core/app.js';
import { springs, isReduced, hover } from '../core/motion.js';
import { ProfileMark } from './profile.js';

export const divider = 'divider';
export function item(title, action, options) { return { title, action, ...(options || {}) }; }

/// No leading, trailing or doubled dividers, whatever the conditional parts produced.
export function tidy(entries) {
  const out = [];
  for (const entry of entries.flat(Infinity)) {
    if (!entry) continue;
    if (entry === divider) { if (out.length && out[out.length - 1] !== divider) out.push(entry); }
    else out.push({ enabled: true, ...entry });
  }
  while (out[out.length - 1] === divider) out.pop();
  return out;
}

let sequence = 0;

/// Opens at a point (a right click).
export function openMenuAt(entries, x, y) { present(entries, { x, y }); }

/// Opens under a control, or above it when there is no room below.
export function openMenuBelow(entries, element) {
  const rect = element.getBoundingClientRect();
  present(entries, { rect: { left: rect.left, right: rect.right, top: rect.top, bottom: rect.bottom } });
}

function present(entries, where) {
  const list = tidy(entries);
  if (!list.length) return;
  update(u => { u.menu = { id: ++sequence, entries: list, where, highlighted: -1 }; u.submenu = null; });
}

export function closeMenu(animated = true) {
  if (!ui.menu) return;
  update(u => { u.menu = null; u.submenu = null; });
}

/// A context menu for an area: the smallest area under the pointer wins.
export function contextMenu(entries) {
  return event => {
    event.preventDefault(); event.stopPropagation();
    openMenuAt(typeof entries === 'function' ? entries(event) : entries, event.clientX, event.clientY);
  };
}

function place(el, where) {
  const width = el.offsetWidth, height = el.offsetHeight;
  const maxX = window.innerWidth - 4, maxY = window.innerHeight - 4;
  let x, y, originX = 'left', originY = 'top';
  if (where.rect) {
    x = where.rect.left; y = where.rect.bottom + 4;
    if (y + height > maxY && where.rect.top - 4 - height >= 4) { y = where.rect.top - 4 - height; originY = 'bottom'; }
    if (x + width > maxX) { x = where.rect.right - width; originX = 'right'; }
  } else {
    x = where.x; y = where.y;
    if (y + height > maxY && where.y - height >= 4) { y = where.y - height; originY = 'bottom'; }
    if (x + width > maxX) { x = where.x - width; originX = 'right'; }
  }
  x = Math.max(4, Math.min(x, maxX - width)); y = Math.max(4, Math.min(y, maxY - height));
  el.style.left = Math.round(x) + 'px'; el.style.top = Math.round(y) + 'px';
  el.style.transformOrigin = originX + ' ' + originY;
  // Grows from the click point or the button it hangs from, as MenuView does.
  if (isReduced()) el.animate([{ opacity: 0 }, { opacity: 1 }], { duration: 100, easing: 'ease-out' });
  else el.animate([{ opacity: 0, transform: 'scale(0.95)' }, { opacity: 1, transform: 'none' }], { duration: springs.menu.ms, easing: springs.menu.easing });
}

function choose(menu, entry) {
  if (!entry || entry === divider || entry.enabled === false) return;
  closeMenu();
  entry.action && entry.action();
}

function move(menu, step) {
  const candidates = menu.entries.map((entry, index) => entry !== divider && entry.enabled !== false ? index : -1).filter(index => index >= 0);
  if (!candidates.length) return;
  const position = candidates.indexOf(menu.highlighted);
  menu.highlighted = position < 0 ? (step > 0 ? candidates[0] : candidates[candidates.length - 1]) : candidates[(position + step + candidates.length) % candidates.length];
  invalidate();
}

function MenuBody(menu, isChild) {
  const symbols = menu.entries.some(entry => entry !== divider && (entry.symbol || entry.profile));
  return h('div', {
    class: 'menu', role: 'menu', key: 'menu-' + menu.id, onMount: el => place(el, menu.where),
    exit: { name: 'fade', float: false, outMs: 100 },
    onPointerDown: event => event.stopPropagation(),
    onContextMenu: event => {
      event.preventDefault(); event.stopPropagation();
      // A right click on a row with its own choices opens them beside the menu, which stays open under them.
      const entry = menu.entries[menu.highlighted];
      if (!isChild && entry && entry.secondary && entry.secondary.length) update(u => { u.submenu = { id: ++sequence, entries: tidy(entry.secondary), where: { x: event.clientX, y: event.clientY }, highlighted: -1 }; });
    },
  }, menu.entries.map((entry, index) => entry === divider
    ? h('div', { class: 'menu-divider', role: 'separator' })
    : h('button', {
        class: cx('menu-row', { highlighted: menu.highlighted === index && entry.enabled !== false, destructive: entry.destructive }),
        role: entry.checked != null ? 'menuitemcheckbox' : 'menuitem', type: 'button', 'aria-disabled': entry.enabled === false ? 'true' : null,
        'aria-checked': entry.checked ? 'true' : null, tabIndex: -1,
        onPointerEnter: () => { if (menu.highlighted !== index) { menu.highlighted = entry.enabled === false ? -1 : index; invalidate(); } },
        onPointerLeave: () => { if (menu.highlighted === index) { menu.highlighted = -1; invalidate(); } },
        onClick: () => { if (isChild) { const parent = ui.menu; choose(menu, entry); if (parent) closeMenu(); } else choose(menu, entry); },
      },
        symbols ? h('span', { class: 'menu-symbol' }, entry.profile ? ProfileMark(entry.profile, 16) : entry.symbol ? icon(entry.symbol, 12) : null) : null,
        h('span', null, entry.title),
        entry.checked ? icon('checkmark', 10, 'semibold') : null,
        entry.keys ? h('span', { class: 'menu-keys' }, entry.keys) : null)));
}

/// The layer that holds the open menu; drawn by the root above everything else.
export function MenuLayer() {
  const menu = ui.menu;
  if (!menu) return null;
  return h('div', {
    class: 'menu-layer', key: 'menu-layer',
    onPointerDown: event => {
      if (ui.submenu) { update(u => { u.submenu = null; }); return; }
      closeMenu();
      // A right click elsewhere opens the menu of that place, as in system menus; other clicks only close.
      if (event.button === 2) {
        const x = event.clientX, y = event.clientY;
        requestAnimationFrame(() => {
          const target = document.elementFromPoint(x, y);
          if (target) target.dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, cancelable: true, clientX: x, clientY: y, button: 2 }));
        });
      }
    },
    onContextMenu: event => event.preventDefault(),
    onWheel: event => { if (!(event.target.closest && event.target.closest('.menu'))) closeMenu(); },
  }, MenuBody(menu, false), ui.submenu ? MenuBody(ui.submenu, true) : null);
}

/// Keyboard of the open menu. Returns true when the key was taken.
export function menuKey(event) {
  const menu = ui.submenu || ui.menu;
  if (!menu) return false;
  switch (event.key) {
    case 'Escape': if (ui.submenu) update(u => { u.submenu = null; }); else closeMenu(); break;
    case 'ArrowDown': move(menu, 1); break;
    case 'ArrowUp': move(menu, -1); break;
    case 'Enter': case ' ': if (menu.highlighted >= 0) { const parent = ui.submenu ? ui.menu : null; choose(menu, menu.entries[menu.highlighted]); if (parent) closeMenu(); } break;
    default: break;
  }
  event.preventDefault(); event.stopPropagation();
  return true;
}

window.addEventListener('resize', () => { closeMenu(false); closePopover(); });
window.addEventListener('blur', () => closeMenu(false));

// Popovers: a raised card without an arrow that grows out of the control that opened it. A sticky one (a form)
// stays open when the window loses focus; it closes on its own buttons, Esc, a click elsewhere or a resize.

export function openPopover(id, element, render, options) {
  const rect = element.getBoundingClientRect();
  update(u => { u.popover = { id, serial: ++sequence, anchor: { left: rect.left, right: rect.right, top: rect.top, bottom: rect.bottom }, render, ...(options || {}) }; });
}

export function closePopover(id) {
  if (!ui.popover || (id && ui.popover.id !== id)) return;
  const closing = ui.popover;
  update(u => { u.popover = null; });
  if (closing.onClose) closing.onClose();
}

export function popoverOpen(id) { return !!ui.popover && ui.popover.id === id; }

function placePopover(el, popover) {
  const width = el.offsetWidth, height = el.offsetHeight, gap = 6;
  const anchor = popover.anchor, middle = (anchor.left + anchor.right) / 2;
  let x = Math.min(Math.max(middle - width / 2, 8), window.innerWidth - 8 - width);
  let y = anchor.bottom + gap, below = true;
  if (y + height > window.innerHeight - 8 && anchor.top - gap - height >= 8) { y = anchor.top - gap - height; below = false; }
  el.style.left = Math.round(x) + 'px'; el.style.top = Math.round(y) + 'px';
  const origin = Math.min(Math.max((middle - x) / width, 0), 1);
  el.style.transformOrigin = (origin * 100).toFixed(1) + '% ' + (below ? '0%' : '100%');
  if (isReduced()) el.animate([{ opacity: 0 }, { opacity: 1 }], { duration: 100, easing: 'ease-out' });
  else el.animate([{ opacity: 0, transform: `translateY(${below ? -4 : 4}px) scale(0.94)` }, { opacity: 1, transform: 'none' }], { duration: springs.popover.ms, easing: springs.popover.easing });
}

export function PopoverLayer() {
  const popover = ui.popover;
  if (!popover) return null;
  return h('div', {
    class: 'menu-layer popover-layer', key: 'popover-layer',
    // The click only closes the form, as with a popover; a right click still opens its menu.
    onPointerDown: event => { if (event.target === event.currentTarget) closePopover(); },
  }, h('div', {
    class: 'popover', role: 'dialog', 'aria-modal': 'true', key: 'popover-' + popover.serial, style: { width: popover.width ? popover.width + 'px' : null },
    onMount: el => placePopover(el, popover), exit: { name: 'fade', float: false, outMs: 100 },
    onKeyDown: event => { if (event.key === 'Escape') { closePopover(); event.stopPropagation(); } },
  }, popover.render()));
}

export { hover };
