// Parts of the content card around a web page: the find bar and the error page (Page on macOS).

import { h, cx } from '../core/dom.js';
import { icon } from '../core/icons.js';
import { T } from '../core/text.js';
import { IconButton, Button } from '../ui/controls.js';
import { state, ui, update, send } from './model.js';

export function FindBar(tab) {
  const find = ui.find;
  const close = () => { send('find.close'); };
  const run = back => send('find.run', { query: find.query, back });
  return h('div', { class: 'findbar raised', key: 'find', role: 'search', enter: 'slide-top', exit: { name: 'slide-top', float: false } },
    h('span', { class: 'findbar-glass' }, icon('text.magnifyingglass', 12)),
    h('input', {
      class: 'findbar-input', type: 'text', value: find.query, placeholder: T("найти на странице", "Найти на странице"), 'aria-label': T("найти на странице", "Найти на странице"), spellcheck: false,
      onInput: event => { find.query = event.target.value; run(false); },
      onKeyDown: event => {
        if (event.key === 'Enter') { run(event.shiftKey); event.preventDefault(); }
        else if (event.key === 'Escape') { close(); event.preventDefault(); event.stopPropagation(); }
      },
      onMount: el => requestAnimationFrame(() => { el.focus(); el.select(); }),
      ref: el => { findInput = el; },
    }),
    state.findResult && state.findResult.found === false && find.query ? h('span', { class: 'findbar-miss', key: 'miss', enter: 'fade', exit: 'fade' }, T("не найдено", "Не найдено")) : null,
    state.findResult && state.findResult.total > 0 && find.query ? h('span', { class: 'findbar-count tabular', key: 'count' }, `${state.findResult.index}/${state.findResult.total}`) : null,
    IconButton('chevron.up', T("предыдущее совпадение", "Предыдущее совпадение"), { size: 24, onClick: () => run(true) }),
    IconButton('chevron.down', T("следующее совпадение", "Следующее совпадение"), { size: 24, onClick: () => run(false) }),
    IconButton('xmark', T("закрыть поиск", "Закрыть поиск"), { size: 24, onClick: close }));
}

let findInput = null;
export function focusFind() { if (findInput && findInput.isConnected) { findInput.focus(); findInput.select(); } }

export function ErrorPage(tab) {
  const error = tab.error;
  const symbol = tab.phase === 'terminated' ? 'arrow.triangle.2.circlepath' : error.certificate ? 'lock.trianglebadge.exclamationmark' : 'wifi.exclamationmark';
  return h('div', { class: 'error-page', key: 'error', enter: 'fade', exit: 'fade' },
    h('div', { class: 'error-column' },
      h('span', { class: 'error-icon' }, icon(symbol, 18)),
      h('div', { class: 'error-title' }, tab.phase === 'terminated' ? T("страница остановлена", "Страница остановлена") : T("страница недоступна", "Страница недоступна")),
      tab.host ? h('div', { class: 'error-host selectable' }, tab.host) : null,
      h('div', { class: 'error-text selectable' }, error.message),
      h('div', { class: 'row', style: { gap: '8px', 'margin-top': '8px' } },
        Button(tab.phase === 'terminated' ? T("восстановить", "Восстановить") : T("повторить", "Повторить"), { kind: 'primary', onClick: () => send('tab.reload', { id: tab.id }) }),
        Button(T("назад", "Назад"), { disabled: !tab.canBack, onClick: () => send('tab.back', { id: tab.id }) }))));
}

export { cx };
