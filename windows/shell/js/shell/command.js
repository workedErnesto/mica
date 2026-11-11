// The command bar over the page and the suggestion list it shares with the start page field
// (Shell/CommandBar on macOS). Suggestions come from the host: open tabs, bookmarks and history never leave it
// in bulk, only the eight rows that match what is typed.

import { h, cx } from '../core/dom.js';
import { icon } from '../core/icons.js';
import { T } from '../core/text.js';
import { KeyHint, Hairline } from '../ui/controls.js';
import { request } from '../core/host.js';
import { state, ui, update, send, selected } from './model.js';

const symbols = { open: 'arrow.up.right', search: 'magnifyingglass', tab: 'square.on.square', bookmark: 'bookmark', history: 'clock' };

/// Asks the host for suggestions for the text of `box` (ui.command or ui.start) and keeps only the latest answer.
export function suggest(box, text) {
  box.text = text; box.highlighted = 0;
  const seq = ++box.seq;
  if (!text.trim()) { box.items = []; update(); return; }
  update();
  request('suggest', { text }).then(items => { if (box.seq === seq) { box.items = items || []; update(null, 'snappy'); } });
}

export function activate(suggestion) { send('suggestion.open', { url: suggestion.url || null, tab: suggestion.tabId || null }); }

/// Enter: the highlighted row when the user moved to it or the first row is an address or a search; else the text itself.
export function submit(box) {
  const items = box.items;
  const chosen = items[box.highlighted];
  if (chosen && (box.highlighted > 0 || chosen.kind === 'open' || chosen.kind === 'search')) activate(chosen);
  else if (box.text.trim()) send('navigate', { text: box.text });
  else return false;
  return true;
}

/// Arrow keys shared by the floating command bar and the start page field. Returns true when handled.
export function suggestionKeys(box, event) {
  const count = box.items.length;
  if (!count) return false;
  if (event.key === 'ArrowDown') { box.highlighted = Math.min(count - 1, box.highlighted + 1); update(); return true; }
  if (event.key === 'ArrowUp') { box.highlighted = Math.max(0, box.highlighted - 1); update(); return true; }
  return false;
}

export function SuggestionList(box, choose) {
  return h('div', { class: 'suggestions', role: 'listbox' }, box.items.map((entry, index) => h('button', {
    class: cx('suggestion press', { highlighted: index === box.highlighted }), type: 'button', role: 'option', 'aria-selected': index === box.highlighted ? 'true' : 'false', key: entry.id, tabIndex: -1,
    onPointerEnter: () => { if (box.highlighted !== index) { box.highlighted = index; update(); } },
    // The field must keep the focus, or the list would close under the pointer.
    onPointerDown: event => event.preventDefault(),
    onClick: () => choose(entry),
  },
    h('span', { class: 'suggestion-symbol' }, icon(symbols[entry.kind] || 'globe', 11)),
    h('span', { class: 'suggestion-title clip' }, entry.title),
    h('span', { class: 'suggestion-detail clip' }, entry.detail),
    h('span', { class: 'spacer' }),
    index === box.highlighted ? h('span', { class: 'suggestion-return' }, icon('return', 10, 'semibold')) : null)));
}

export function closeCommandBar() { send('commandBar', { on: false }); }

export function CommandBar() {
  const box = ui.command;
  const choose = entry => { activate(entry); closeCommandBar(); };
  return h('div', { class: 'command-layer', key: 'command', enter: 'fade', exit: { name: 'fade', float: false } },
    h('div', { class: 'command-scrim', onPointerDown: closeCommandBar }),
    h('div', { class: 'command raised', role: 'dialog', 'aria-label': T("адресная строка", "Адресная строка"), enter: 'command' },
      h('div', { class: 'command-field' },
        h('span', { class: 'command-glass' }, icon('magnifyingglass', 15)),
        h('input', {
          class: 'command-input', type: 'text', value: box.text, placeholder: T("адрес или поиск", "Адрес или поиск"), 'aria-label': T("адресная строка", "Адресная строка"), spellcheck: false, autocomplete: 'off',
          onInput: event => suggest(box, event.target.value),
          onKeyDown: event => {
            if (event.key === 'Escape') { closeCommandBar(); event.preventDefault(); event.stopPropagation(); }
            else if (event.key === 'Enter') { if (submit(box)) closeCommandBar(); event.preventDefault(); }
            else if (suggestionKeys(box, event)) event.preventDefault();
          },
          // Opens with the page address selected, ready to be replaced or copied.
          onMount: el => { el.focus(); el.select(); requestAnimationFrame(() => { if (document.activeElement !== el) { el.focus(); el.select(); } }); },
        }),
        KeyHint('esc')),
      box.items.length ? [Hairline(), h('div', { class: 'command-list', key: 'list' }, SuggestionList(box, choose))] : null));
}

/// The bar opens with the address of the selected tab in it.
export function prepareCommandBar() {
  const tab = selected();
  ui.command.text = tab && tab.url ? tab.url : '';
  ui.command.items = []; ui.command.highlighted = 0; ui.command.seq++;
}

export { state };
