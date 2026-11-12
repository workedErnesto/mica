// Window-level overlays: settings, onboarding, clearing data, where to open a profile, questions of the host
// (ModalCard on macOS), and the quit-hold plate.

import { h, cx } from '../core/dom.js';
import { T, keys, quoted, lang } from '../core/text.js';
import { Button, Segmented, Switch, Group, SiteTile } from '../ui/controls.js';
import { icon } from '../core/icons.js';
import { ProfileMark } from '../ui/profile.js';
import { springs, isReduced } from '../core/motion.js';
import { state, ui, update, send } from './model.js';
import { SettingsView, OnboardingView } from './settings.js';

/// Window-level card over a dimmed shell and page. A click on the scrim or Esc calls `dismiss` when given.
function Modal(key, width, height, body, dismiss) {
  return h('div', {
    class: 'modal-layer', key, enter: 'fade', exit: { name: 'fade', float: false },
    onKeyDown: event => { if (event.key === 'Escape' && dismiss) { dismiss(); event.stopPropagation(); } },
  },
    h('div', { class: 'scrim', onPointerDown: dismiss || null }),
    h('div', { class: 'modal', role: 'dialog', 'aria-modal': 'true', enter: 'modal', exit: { name: 'modal', float: false }, style: { width: width + 'px', height: height ? height + 'px' : null } }, body));
}

function count(n) {
  if (lang() === 'en') return n + ' ' + (n === 1 ? 'entry' : 'entries');
  const ten = n % 10, hundred = n % 100;
  return n + ' ' + (ten === 1 && hundred !== 11 ? 'запись' : ten >= 2 && ten <= 4 && !(hundred >= 12 && hundred <= 14) ? 'записи' : 'записей');
}

/// Clears browsing data of regular windows for a chosen period; the last choice is remembered.
function ClearData() {
  const c = state.clearData;
  const set = (key, value) => send('clearData.set', { key, value });
  const option = (key, title, detail) => h('div', { class: 'setting', key },
    h('div', { class: 'setting-labels' }, h('div', { class: 'setting-title' }, title), h('div', { class: 'setting-detail' }, detail)),
    Switch(c[key], value => set(key, value), { label: title }));
  return h('div', { class: 'clear-data' },
    h('div', { class: 'col', style: { gap: '4px' } },
      h('div', { class: 'modal-title' }, T("очистить данные", "Очистить данные")),
      h('div', { class: 'modal-lead' }, T("только обычные окна. закладки и открытые вкладки останутся", "Только обычные окна. Закладки и открытые вкладки останутся"))),
    h('div', { class: 'col', style: { gap: '8px' } },
      h('div', { class: 'group-title' }, T("период", "Период")),
      Segmented(c.period, [{ value: 'hour', title: T("час", "Час") }, { value: 'day', title: T("сутки", "Сутки") }, { value: 'week', title: T("неделя", "Неделя") }, { value: 'month', title: T("4 недели", "4 недели") }, { value: 'all', title: T("всё время", "Всё время") }],
        value => set('period', value), { minWidth: 424, label: T("период", "Период") })),
    Group(null, [
      option('history', T("история посещений", "История посещений"), c.visits === 0 ? T("за этот период записей нет", "За этот период записей нет") : count(c.visits)),
      option('siteData', T("cookie и данные сайтов", "Cookie и данные сайтов"), T("вы выйдете из аккаунтов на сайтах, открытых за этот период", "Вы выйдете из аккаунтов на сайтах, открытых за этот период")),
      option('cache', T("кэш", "Кэш"), T("страницы загрузятся заново, это безопасно", "Страницы загрузятся заново, это безопасно")),
      option('permissions', T("разрешения сайтов", "Разрешения сайтов"), T("камера, микрофон и уведомления, за всё время: у решений нет даты", "Камера, микрофон и уведомления, за всё время: у решений нет даты")),
    ]),
    h('div', { class: 'row', style: { gap: '8px', 'justify-content': 'flex-end' } },
      Button(T("отмена", "Отмена"), { kind: 'ghost', onClick: () => send('clearData.close') }),
      Button(c.working ? T("очищаем…", "Очищаем…") : T("очистить", "Очистить"), { kind: 'destructive', disabled: c.working || !(c.history || c.siteData || c.cache || c.permissions), onClick: () => send('clearData.run') })));
}

/// Where to open a profile chosen in the profile menu: the composition of a system question drawn by mica.
function ProfilePrompt(profile) {
  const remember = !!ui.rememberProfile;
  const choose = where => { send('profile.open', { id: profile.id, where, remember }); ui.rememberProfile = false; };
  return h('div', { class: 'prompt' },
    ProfileMark(profile, 56, { class: 'prompt-mark', style: { 'box-shadow': `0 5px 24px ${profile.background}59` } }),
    h('div', { class: 'prompt-title' }, T("открыть профиль ", "Открыть профиль ") + quoted(profile.name) + '?'),
    h('div', { class: 'prompt-text' }, T("в этом окне закреплённые вкладки сменятся закреплёнными вкладками профиля, остальные вкладки останутся. в новом окне это окно не изменится.", "В этом окне закреплённые вкладки сменятся закреплёнными вкладками профиля, остальные вкладки останутся. В новом окне это окно не изменится.")),
    h('div', { class: 'col', style: { gap: '8px', width: '100%' } },
      Button(T("в новом окне", "В новом окне"), { kind: 'primary', fill: true, autofocus: true, onClick: () => choose('newWindow') }),
      Button(T("в этом окне", "В этом окне"), { fill: true, onClick: () => choose('here') }),
      Button(T("отмена", "Отмена"), { kind: 'ghost', fill: true, onClick: () => send('profilePrompt.close') })),
    h('label', { class: 'toggle-row prompt-remember', title: T("ответ можно поменять в настройках, в разделе «профили».", "Ответ можно поменять в настройках, в разделе «профили».") },
      h('span', null, T("запомнить выбор", "Запомнить выбор")), Switch(remember, value => update(() => { ui.rememberProfile = value; }), { label: T("запомнить выбор", "Запомнить выбор") })));
}

/// A question or message from the host (ContentDialog before): the app icon or the asking site's icon, title, text and buttons; the last is the
/// default. Composed like the profile question; long text scrolls inside the card.
function Alert(alert) {
  const values = ui.alertValues && ui.alertValues.id === alert.id ? ui.alertValues : (ui.alertValues = { id: alert.id, list: (alert.fields || []).map(field => field.value || '') });
  const answer = index => send('alert.answer', { id: alert.id, index, values: values.list });
  const buttons = alert.buttons && alert.buttons.length ? alert.buttons : ['OK'];
  return h('div', { class: 'prompt alert' },
    alert.site ? h('span', { class: 'prompt-mark app-mark' }, SiteTile(alert.site, 56))
      : alert.mark ? h('img', { class: 'prompt-mark app-mark', src: alert.mark, alt: '', width: 56, height: 56, draggable: false }) : null,
    h('div', { class: 'prompt-title' }, alert.title),
    alert.text ? h('div', { class: 'prompt-text selectable' }, alert.text) : null,
    (alert.fields || []).length ? h('div', { class: 'col', style: { gap: '8px', width: '100%', 'margin-bottom': '14px' } }, alert.fields.map((field, index) => h('div', { class: 'field', key: index },
      h('input', { type: field.secret ? 'password' : 'text', value: values.list[index], placeholder: field.label, 'aria-label': field.label || alert.title, spellcheck: false,
        onInput: event => { values.list[index] = event.target.value; },
        onKeyDown: event => { if (event.key === 'Enter') { answer((alert.buttons || ['OK']).length - 1); event.preventDefault(); } },
        onMount: index === 0 ? el => requestAnimationFrame(() => { el.focus(); el.select(); }) : null })))) : null,
    alert.choices ? h('div', { class: 'col', style: { gap: '4px', width: '100%' } }, alert.choices.map((choice, index) => h('button', { class: 'menu-row choice', type: 'button', key: index, onClick: () => send('alert.answer', { id: alert.id, index: 100 + index }) }, choice))) : null,
    h('div', { class: 'col', style: { gap: '8px', width: '100%' } },
      buttons.slice().reverse().map((title, reversed) => {
        const index = buttons.length - 1 - reversed;
        return Button(title, { kind: index === buttons.length - 1 ? (alert.destructive ? 'destructive' : 'primary') : index === 0 && buttons.length > 1 ? 'ghost' : 'secondary', fill: true, autofocus: index === buttons.length - 1, onClick: () => answer(index), key: index });
      })));
}

/// A password question (PasswordPrompt on macOS): the site's icon with a key, the host, the account or the generated
/// password on a plate, or the saved accounts as rows. Buttons: the last is the default, index 0 is "not now", the rest
/// are quieter, in that order. Account choices come as raw user names, an empty one when the account has none.
function PasswordAlert(alert) {
  const card = alert.password, buttons = alert.buttons || [];
  const answer = index => send('alert.answer', { id: alert.id, index });
  const account = name => h('span', { class: 'account-line' }, icon('person', 12), h('span', { class: cx('clip', { muted: !name }) }, name || T("без имени пользователя", "Без имени пользователя")));
  const order = buttons.length > 1 ? [buttons.length - 1, 0, ...buttons.map((_, i) => i).slice(1, -1)] : [0];
  const choices = alert.choices || null;
  return h('div', { class: 'prompt' },
    h('span', { class: 'prompt-mark password-mark' },
      SiteTile(card, 56),
      h('span', { class: 'password-badge' }, icon('key', 10.5, 'semibold'))),
    h('div', { class: 'prompt-title password-title' }, alert.title),
    h('div', { class: 'prompt-text password-host clip', title: card.origin }, card.host),
    choices
      ? h('div', { class: 'password-plate choices' }, choices.map((choice, index) => h('button', {
          class: 'account-choice press', type: 'button', key: index, 'data-default': index === 0 || null, onClick: () => answer(100 + index),
        }, account(choice))))
      : h('div', { class: 'password-plate' }, card.secret != null ? h('span', { class: 'mono selectable password-secret' }, card.secret) : account(card.account || '')),
    h('div', { class: 'col', style: { gap: '8px', width: '100%' } },
      order.map(index => Button(buttons[index], {
        kind: choices ? 'secondary' : index === buttons.length - 1 ? 'primary' : index === 0 ? 'secondary' : 'ghost',
        fill: true, autofocus: !choices && index === buttons.length - 1, onClick: () => answer(index), key: index,
      }))));
}

/// The plate shown while the quit shortcut is held: its outline draws clockwise from the top over the hold time.
function QuitHold() {
  return h('div', { class: 'quit-hold-layer', key: 'quit', 'aria-live': 'assertive', enter: 'pop', exit: { name: 'fade', float: false } },
    h('div', { class: 'quit-hold raised', role: 'status' },
      h('svg', { class: 'quit-ring', 'aria-hidden': 'true', onMount: drawRing, html: '' }),
      h('div', { class: 'quit-title' }, T("закрытие mica", "Закрытие mica")),
      h('div', { class: 'quit-hint' }, T("удерживайте ", "Удерживайте ") + keys('quit'))));
}

function drawRing(svg) {
  const box = svg.parentNode.getBoundingClientRect();
  const w = box.width, hgt = box.height, r = 16;
  svg.setAttribute('viewBox', `0 0 ${w} ${hgt}`);
  svg.setAttribute('width', w); svg.setAttribute('height', hgt);
  // A rounded rectangle path that starts at the middle of the top edge, so the stroke grows clockwise from there.
  const d = `M ${w / 2} 1 H ${w - r} A ${r - 1} ${r - 1} 0 0 1 ${w - 1} ${r} V ${hgt - r} A ${r - 1} ${r - 1} 0 0 1 ${w - r} ${hgt - 1} H ${r} A ${r - 1} ${r - 1} 0 0 1 1 ${hgt - r} V ${r} A ${r - 1} ${r - 1} 0 0 1 ${r} 1 Z`;
  svg.innerHTML = `<path d="${d}" pathLength="1" fill="none" stroke-width="2" stroke-linecap="round"/>`;
  const path = svg.firstChild;
  path.style.strokeDasharray = '1 1';
  path.animate([{ strokeDashoffset: 1 }, { strokeDashoffset: 0 }], { duration: (state.overlay.quitHold || 2) * 1000, easing: 'linear', fill: 'forwards' });
}

export function Overlays() {
  const o = state.overlay, width = window.innerWidth;
  const profile = o.profilePrompt ? state.profiles.find(entry => entry.id === o.profilePrompt) : null;
  return [
    o.settings ? Modal('settings', 860, 660, SettingsView(Math.min(860, width - 48)), () => send('settings.close')) : null,
    o.onboarding ? Modal('onboarding', 860, 660, OnboardingView(Math.min(860, width - 48)), null) : null,
    o.clearData && state.clearData ? Modal('clear', 480, null, ClearData(), () => send('clearData.close')) : null,
    profile ? Modal('profile-prompt', 300, null, ProfilePrompt(profile), () => send('profilePrompt.close')) : null,
    o.alert ? Modal('alert-' + o.alert.id, o.alert.password ? 300 : 320, null, o.alert.password ? PasswordAlert(o.alert) : Alert(o.alert), o.alert.cancel != null ? () => send('alert.answer', { id: o.alert.id, index: o.alert.cancel }) : null) : null,
    o.quitHold ? QuitHold() : null,
  ];
}

export { springs, isReduced, cx };
