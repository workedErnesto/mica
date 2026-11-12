// Reusable controls of the shell (DesignSystem/Components on macOS). Each returns a vnode and owns only its own
// shape; callers place them. States (hover, pressed, focus) are CSS, so they never wait for a render.

import { h, cx } from '../core/dom.js';
import { icon } from '../core/icons.js';
import { T } from '../core/text.js';
import { invalidate } from '../core/app.js';

/// MButtonStyle: kind is "primary", "secondary" (default), "ghost" or "destructive".
export function Button(title, { kind = 'secondary', compact = false, fill = false, disabled = false, onClick, key, symbol, autofocus } = {}) {
  return h('button', { class: cx('btn', kind !== 'secondary' && kind, { compact, fill }), disabled, onClick, key, type: 'button', 'data-default': autofocus || null },
    symbol ? icon(symbol, compact ? 11 : 12) : null, title);
}

export function IconButton(symbol, label, { size = 28, selected = false, disabled = false, onClick, key, weight, glyphSize, ref, cls, onContextMenu } = {}) {
  return h('button', {
    class: cx('ib', { selected }, cls), style: size === 28 ? null : { '--s': size + 'px' }, title: label, 'aria-label': label,
    'aria-pressed': selected ? 'true' : null, disabled, onClick, key, type: 'button', ref, onContextMenu,
  }, icon(symbol, glyphSize || size * 0.48, weight));
}

/// options: [{ value, title, symbol? }]
export function Segmented(selection, options, onChange, { compact = false, fill = false, minWidth = 0, label = '', disabled = false, key } = {}) {
  const index = Math.max(0, options.findIndex(option => option.value === selection));
  return h('div', {
    class: cx('seg', { compact, fill }), role: 'radiogroup', 'aria-label': label, 'aria-disabled': disabled ? 'true' : null, key,
    style: { '--n': options.length, '--i': index, 'min-width': minWidth ? minWidth + 'px' : null },
  },
    h('span', { class: 'seg-thumb' }),
    options.map(option => h('button', {
      class: 'seg-item', role: 'radio', type: 'button', 'aria-checked': option.value === selection ? 'true' : 'false',
      onClick: () => { if (option.value !== selection) onChange(option.value); },
    }, option.symbol ? icon(option.symbol, compact ? 10 : 11) : null, h('span', null, option.title))));
}

export function Switch(isOn, onChange, { label = '', disabled = false, key } = {}) {
  return h('button', {
    class: 'switch', role: 'switch', type: 'button', 'aria-checked': isOn ? 'true' : 'false', 'aria-label': label, title: label || null, disabled, key,
    onClick: () => onChange(!isOn),
  }, h('span', { class: 'switch-knob' }));
}

/// A labelled toggle row (Toggle with MToggleStyle).
export function ToggleRow(title, isOn, onChange, { disabled = false, cls, key } = {}) {
  return h('label', { class: cx('toggle-row', cls), key },
    h('span', { class: 'grow' }, title),
    Switch(isOn, onChange, { label: title, disabled }));
}

export function Slider(value, range, onChange, { label = '', disabled = false, key, onCommit } = {}) {
  const [low, high] = range;
  const fraction = Math.min(1, Math.max(0, (value - low) / (high - low)));
  const set = (el, event) => {
    const box = el.getBoundingClientRect();
    const travel = Math.max(1, box.width - 16);
    const position = Math.min(1, Math.max(0, (event.clientX - box.left - 8) / travel));
    onChange(low + position * (high - low));
  };
  return h('div', {
    class: 'slider', role: 'slider', tabIndex: 0, 'aria-label': label, 'aria-valuenow': Math.round(fraction * 100), 'aria-valuemin': 0, 'aria-valuemax': 100,
    'aria-valuetext': Math.round(fraction * 100) + '%', 'aria-disabled': disabled ? 'true' : null, style: { '--f': fraction }, key,
    onPointerDown: event => {
      if (disabled || event.button !== 0) return;
      const el = event.currentTarget;
      el.setPointerCapture(event.pointerId); el.classList.add('dragging');
      set(el, event);
      const move = e => set(el, e);
      const up = () => { el.classList.remove('dragging'); el.removeEventListener('pointermove', move); el.removeEventListener('pointerup', up); el.removeEventListener('pointercancel', up); if (onCommit) onCommit(); };
      el.addEventListener('pointermove', move); el.addEventListener('pointerup', up); el.addEventListener('pointercancel', up);
    },
    onKeyDown: event => {
      const step = (high - low) / 20;
      if (event.key === 'ArrowRight' || event.key === 'ArrowUp') { onChange(Math.min(high, value + step)); if (onCommit) onCommit(); event.preventDefault(); }
      if (event.key === 'ArrowLeft' || event.key === 'ArrowDown') { onChange(Math.max(low, value - step)); if (onCommit) onCommit(); event.preventDefault(); }
    },
  }, h('span', { class: 'slider-track' }), h('span', { class: 'slider-fill' }), h('span', { class: 'slider-knob' }));
}

/// MTextField. `value` and `onInput` keep the text in the caller's state.
export function TextField(placeholder, value, onInput, { symbol, prominent = false, selectionStyle = false, autofocus = false, onSubmit, onEscape, key, type = 'text', cls, maxLength, readOnly } = {}) {
  return h('div', { class: cx('field', { prominent, selection: selectionStyle }, cls), key },
    symbol ? icon(symbol, 12) : null,
    h('input', {
      type, value, placeholder, 'aria-label': placeholder, spellcheck: false, autocomplete: 'off', maxlength: maxLength || null, readOnly: readOnly || null,
      onInput: event => onInput(event.target.value),
      onKeyDown: event => {
        if (event.key === 'Enter' && onSubmit) { onSubmit(); event.preventDefault(); }
        else if (event.key === 'Escape') { if (onEscape) onEscape(); else event.target.blur(); event.stopPropagation(); }
      },
      onMount: autofocus ? el => requestAnimationFrame(() => { el.focus(); el.select(); }) : null,
    }),
    value && !readOnly ? h('button', {
      class: 'field-clear press', type: 'button', 'aria-label': T("очистить", "Очистить"), tabIndex: -1, enter: 'fade', exit: 'fade',
      onClick: event => { onInput(''); const input = event.currentTarget.parentNode.querySelector('input'); if (input) input.focus(); },
    }, icon('xmark.circle.fill', 12)) : null);
}

export function KeyHint(keys, props) { return h('span', { class: 'keyhint' + (props && props.class ? ' ' + props.class : ''), key: props && props.key }, keys); }

const siteHost = host => (host || '').replace(/^www\./i, '');

/// Site letter shown until a favicon is known. `plain` drops the plate for tiles that draw their own.
export function Monogram(host, size = 16, plain = false) {
  const letter = (siteHost(host)[0] || '').toUpperCase();
  return h('span', { class: cx('mono-icon', { plain }), style: { '--s': size + 'px' }, 'aria-hidden': 'true' },
    letter || icon('globe', size * (plain ? 0.66 : 0.6), plain ? 'medium' : 'regular'));
}

const failed = new Set();
/// Favicon of a site, or its monogram until one is known. `site` is { host, icon, ink }.
export function SiteIcon(site, size = 16, plain = false) {
  const src = site && site.icon && !failed.has(site.icon) ? site.icon : null;
  if (!src) return Monogram(site && site.host, size, plain);
  if (site.ink) return h('span', { class: 'site-icon ink', style: { '--s': size + 'px', '--src': `url("${src}")` }, 'aria-hidden': 'true', key: 'ink' });
  return h('span', { class: 'site-icon', style: { '--s': size + 'px' }, 'aria-hidden': 'true', key: 'img' },
    h('img', { src, alt: '', draggable: false, onError: () => { failed.add(src); invalidate(); } }));
}

/// SiteIcon on a list-row plate (`tiled` on macOS): a favicon at 60 % of the tile, a monogram fills the tile itself.
export function SiteTile(site, size) {
  if (!(site && site.icon && !failed.has(site.icon))) return Monogram(site && site.host, size);
  return h('span', { class: 'lib-icon tiled', style: { width: size + 'px', height: size + 'px', 'border-radius': size * 0.3 + 'px' } }, SiteIcon(site, Math.round(size * 0.6)));
}

/// Progress ring driven by real progress, never spinning on its own.
export function ProgressRing(progress, size = 16) {
  const r = (size - 2) / 2 - 1, length = 2 * Math.PI * r;
  const shown = Math.max(0.06, Math.min(1, progress || 0));
  return h('span', {
    class: 'ring', style: { '--s': size + 'px' }, 'aria-hidden': 'true',
    html: `<svg viewBox="0 0 ${size} ${size}" fill="none" stroke-width="2"><circle class="ring-track" cx="${size / 2}" cy="${size / 2}" r="${r}"/><circle class="ring-value" cx="${size / 2}" cy="${size / 2}" r="${r}" stroke-linecap="round" stroke-dasharray="${length.toFixed(2)}" stroke-dashoffset="${(length * (1 - shown)).toFixed(2)}"/></svg>`,
    // innerHTML would restart the transition; later updates only move the dash offset.
    onUpdate: el => { const value = el.querySelector('.ring-value'); if (value) value.style.strokeDashoffset = (length * (1 - shown)).toFixed(2); },
  });
}

export function Hairline(props) { return h('div', { class: 'hairline' + (props && props.class ? ' ' + props.class : ''), style: props && props.style }); }

export function EmptyState(symbol, text) {
  return h('div', { class: 'empty', key: 'empty' }, h('span', { class: 'empty-icon' }, icon(symbol, 16)), h('span', null, text));
}

export function LinkRow(title, symbol, onClick, key) {
  return h('button', { class: 'linkrow', type: 'button', onClick, key }, h('span', { class: 'clip' }, title), icon(symbol, 10.5, 'semibold'));
}

/// SettingsGroup: title, rows on a surface, footnote.
export function Group(title, rows, { footnote, key } = {}) {
  return h('section', { class: 'group', key },
    title ? h('div', { class: 'group-title' }, title) : null,
    h('div', { class: 'group-body' }, rows),
    footnote ? h('div', { class: 'group-note' }, footnote) : null);
}

/// SettingRow: labels on the left, the control on the right; the control wraps under the labels when there is no room.
export function Setting(title, trailing, { detail, info, key, cls } = {}) {
  return h('div', { class: cx('setting', cls), key },
    h('div', { class: 'setting-labels' },
      h('div', { class: 'setting-title' }, h('span', null, title), info || null),
      detail ? h('div', { class: 'setting-detail' }, detail) : null),
    trailing ? h('div', { class: 'setting-trailing' }, trailing) : null);
}

/// Vertical navigation with a selection plate that travels between items (NavItem with matchedGeometryEffect).
export function Nav(items, selected, onSelect, { compact = false } = {}) {
  const index = Math.max(0, items.findIndex(item => item.id === selected));
  return h('div', { class: cx('nav', { compact }), role: 'tablist', 'aria-orientation': 'vertical', style: { '--i': index } },
    h('span', { class: 'nav-thumb' }),
    items.map(item => h('button', {
      class: 'nav-item press', type: 'button', role: 'tab', 'aria-selected': item.id === selected ? 'true' : 'false', title: item.title, 'aria-label': item.title, key: item.id,
      onClick: () => onSelect(item.id),
    }, icon(item.symbol, 12), compact ? null : h('span', { class: 'clip' }, item.title))));
}
