// Settings and onboarding (Settings and Onboarding on macOS): a window-level card with a column of sections on the
// shell colour and the content on the canvas. The host sends `state.settings` while either is open.

import { h, cx } from '../core/dom.js';
import { icon } from '../core/icons.js';
import { T, keys, quoted, isLowercase, lang, locale } from '../core/text.js';
import { profileCatalog, geometry } from '../gen/tokens.g.js';
import { Button, IconButton, Segmented, Switch, Slider, TextField, Group, Setting, Nav, Monogram, KeyHint, LinkRow, SiteTile } from '../ui/controls.js';
import { openPopover, closePopover } from '../ui/menu.js';
import { ProfileMark } from '../ui/profile.js';
import { request } from '../core/host.js';
import { state, ui, update, send, setPref } from './model.js';
import { AddressText, capabilityName } from './topbar.js';

const sections = [
  ['space', 'sidebar.squares.left'], ['appearance', 'paintbrush'], ['start', 'square.grid.2x2'], ['profiles', 'person.crop.circle'],
  ['search', 'shield.lefthalf.filled'], ['session', 'square.stack'], ['transfer', 'square.and.arrow.down.on.square'],
  ['permissions', 'hand.raised'], ['passwords', 'key'], ['about', 'info.circle'],
];

export function sectionTitle(id) {
  switch (id) {
    case 'space': return T("пространство", "Пространство");
    case 'appearance': return T("оформление", "Оформление");
    case 'start': return T("начальная страница", "Начальная страница");
    case 'profiles': return T("профили", "Профили");
    case 'search': return T("поиск и защита", "Поиск и защита");
    case 'session': return T("сессия и память", "Сессия и память");
    case 'transfer': return T("перенос данных", "Перенос данных");
    case 'permissions': return T("разрешения сайтов", "Разрешения сайтов");
    case 'passwords': return T("пароли", "Пароли");
    default: return 'mica';
  }
}

const S = () => state.settings || {};
const P = () => state.prefs;
const local = () => ui.settings;

/// A labelled switch row (Toggle with MToggleStyle inside a group).
function ToggleSetting(title, isOn, onChange, { detail, disabled, key } = {}) {
  return Setting(title, Switch(isOn, onChange, { label: title, disabled }), { detail, key });
}

function percent(value) { return h('span', { class: 'value-label tabular' }, Math.round(value) + '%'); }

// Pickers shared by settings and onboarding.

export function LayoutPicker(minWidth = 260) {
  return Segmented(P().layout, [
    { value: 'left', title: T("слева", "Слева") }, { value: 'top', title: T("под адресом", "Под адресом") },
    { value: 'tabsAbove', title: T("над адресом", "Над адресом") }, { value: 'right', title: T("справа", "Справа") },
  ], value => setPref('layout', value), { minWidth, label: T("вкладки", "Вкладки") });
}

export function ThemePicker(minWidth = 380) {
  return Segmented(P().theme, [
    { value: 'system', title: T("системная", "Системная") }, { value: 'light', title: T("светлая", "Светлая") },
    { value: 'dark', title: T("тёмная", "Тёмная") }, { value: 'custom', title: T("кастом", "Кастом") },
  ], value => setPref('theme', value), { minWidth, label: T("тема", "Тема") });
}

/// Each option is written in the style it selects; language names in their own language.
export function CasePicker(minWidth = 260) {
  const en = lang() === 'en';
  return Segmented(isLowercase(), [{ value: true, title: en ? 'lowercase' : 'со строчной' }, { value: false, title: en ? 'Standard' : 'Обычный' }],
    value => setPref('lowercase', value), { minWidth, label: T("текст интерфейса", "Текст интерфейса") });
}
export function LanguagePicker(minWidth = 260) {
  return Segmented(lang(), [{ value: 'ru', title: isLowercase() ? 'русский' : 'Русский' }, { value: 'en', title: isLowercase() ? 'english' : 'English' }],
    value => setPref('language', value), { minWidth, label: T("язык", "Язык") });
}

export function NameRows() {
  return [
    Setting(T("имя", "Имя"), h('div', { style: { width: '220px' } }, TextField(T("как к вам обращаться", "Как к вам обращаться"), P().userName, value => setPref('userName', value.slice(0, 32)), { readOnly: !P().greetByName })),
      { detail: T("для приветствия на начальной странице", "Для приветствия на начальной странице"), key: 'name' }),
    ToggleSetting(T("не обращаться по имени", "Не обращаться по имени"), !P().greetByName, value => setPref('greetByName', !value), { key: 'noname' }),
  ];
}

/// Search engines in a grid; the outline of the chosen one travels to the next choice.
export function SearchPicker() {
  const engines = S().engines || [];
  return h('div', { class: 'engines', role: 'radiogroup', 'aria-label': T("поисковик", "Поисковик") }, engines.map(engine => h('button', {
    class: cx('engine press', { selected: engine.id === S().search }), type: 'button', role: 'radio', 'aria-checked': engine.id === S().search ? 'true' : 'false', key: engine.id,
    onClick: () => send('settings.search', { engine: engine.id }),
  }, Monogram(engine.host, 20), h('span', { class: 'grow clip' }, engine.title), engine.id === S().search ? h('span', { key: 'check', enter: 'pop' }, icon('checkmark', 10, 'bold')) : null)));
}

const accents = ['#6E56CF', '#3E7BFA', '#0EA5E9', '#1F9D8B', '#3FA34D', '#E8A33D', '#F76B15', '#E5484D'];
export function AccentPicker() {
  const current = (P().accent || '').toUpperCase();
  return h('div', { class: 'swatches', role: 'radiogroup', 'aria-label': T("акцент", "Акцент") },
    accents.map(color => h('button', { class: cx('swatch press', { selected: current === color }), type: 'button', role: 'radio', 'aria-checked': current === color ? 'true' : 'false', 'aria-label': color, key: color, style: { '--c': color }, onClick: () => setPref('accent', color) })),
    ColorWell(accents.includes(current) ? null : current, color => setPref('accent', color), T("свой цвет", "Свой цвет")));
}

/// A ring of hues with a plus or the chosen colour inside; opens mica's colour picker (ColorPanel).
export function ColorWell(color, onChange, label) {
  return h('button', {
    class: cx('colorwell press', { chosen: !!color }), type: 'button', 'aria-label': label, title: label, style: { '--c': color || 'transparent' },
    onClick: event => openPopover('color', event.currentTarget, () => ColorPanel(color || P().accent, onChange), { width: 248 }),
  }, color ? null : icon('plus', 9, 'bold'));
}

function hsv(hex) {
  const n = parseInt(hex.slice(1), 16), r = (n >> 16 & 255) / 255, g = (n >> 8 & 255) / 255, b = (n & 255) / 255;
  const max = Math.max(r, g, b), min = Math.min(r, g, b), d = max - min;
  let hue = 0;
  if (d) hue = max === r ? ((g - b) / d) % 6 : max === g ? (b - r) / d + 2 : (r - g) / d + 4;
  return { h: (hue * 60 + 360) % 360, s: max ? d / max : 0, v: max };
}
function hex({ h: hue, s, v }) {
  const f = k => { const x = (k + hue / 60) % 6; return v - v * s * Math.max(0, Math.min(x, 4 - x, 1)); };
  return '#' + [f(5), f(3), f(1)].map(x => Math.round(x * 255).toString(16).padStart(2, '0')).join('').toUpperCase();
}

function ColorPanel(initial, onChange) {
  const box = ui.color && ui.color.initial === initial ? ui.color : (ui.color = { initial, value: hsv(/^#[0-9a-f]{6}$/i.test(initial || '') ? initial : '#6E56CF') });
  const value = box.value, current = hex(value);
  const set = next => { box.value = next; update(); onChange(hex(next)); };
  const drag = (apply) => event => {
    const el = event.currentTarget; el.setPointerCapture(event.pointerId); el.classList.add('dragging');
    const move = e => { const r = el.getBoundingClientRect(); apply(Math.min(1, Math.max(0, (e.clientX - r.left) / r.width)), Math.min(1, Math.max(0, (e.clientY - r.top) / r.height))); };
    move(event);
    const up = () => { el.classList.remove('dragging'); el.removeEventListener('pointermove', move); el.removeEventListener('pointerup', up); };
    el.addEventListener('pointermove', move); el.addEventListener('pointerup', up);
  };
  return h('div', { class: 'colorpanel' },
    h('div', { class: 'swatches' }, profileCatalog.backgrounds.map(color => h('button', { class: cx('swatch small press', { selected: current === color }), type: 'button', 'aria-label': color, key: color, style: { '--c': color }, onClick: () => { box.value = hsv(color); update(); onChange(color); } }))),
    h('div', { class: 'sv', style: { '--hue': `hsl(${value.h} 100% 50%)` }, role: 'slider', 'aria-label': T("насыщенность и яркость", "Насыщенность и яркость"), 'aria-valuenow': Math.round(value.v * 100), tabIndex: 0,
      onPointerDown: drag((x, y) => set({ ...value, s: x, v: 1 - y })),
      onKeyDown: event => { const step = 0.05; if (event.key === 'ArrowUp') set({ ...value, v: Math.min(1, value.v + step) }); if (event.key === 'ArrowDown') set({ ...value, v: Math.max(0, value.v - step) }); },
    }, h('span', { class: 'sv-knob', style: { left: value.s * 100 + '%', top: (1 - value.v) * 100 + '%', background: current } })),
    h('div', { class: 'hue', role: 'slider', 'aria-label': T("оттенок", "Оттенок"), 'aria-valuenow': Math.round(value.h), tabIndex: 0,
      onPointerDown: drag(x => set({ ...value, h: x * 359.9 })),
      onKeyDown: event => { if (event.key === 'ArrowRight') set({ ...value, h: (value.h + 6) % 360 }); if (event.key === 'ArrowLeft') set({ ...value, h: (value.h + 354) % 360 }); },
    }, h('span', { class: 'hue-knob', style: { left: value.h / 360 * 100 + '%', background: `hsl(${value.h} 100% 50%)` } })),
    h('div', { class: 'row', style: { gap: '8px' } }, h('span', { class: 'color-sample', style: { background: current } }), h('span', { class: 'mono selectable' }, current)));
}

/// The look of a profile in a small window sketch (LayoutPreview on macOS).
function LayoutPreview() {
  const layout = P().layout, collapsed = P().sidebarCollapsed;
  const side = layout === 'left' || layout === 'right';
  return h('div', { class: cx('layout-preview', 'lp-' + layout, { collapsed }), 'aria-hidden': 'true' },
    h('div', { class: 'lp-window' },
      layout === 'tabsAbove' ? h('div', { class: 'lp-tabs top' }, h('i'), h('i'), h('i')) : null,
      h('div', { class: 'lp-bar' }, h('span', { class: 'lp-field' })),
      layout === 'top' ? h('div', { class: 'lp-tabs' }, h('i'), h('i'), h('i')) : null,
      h('div', { class: 'lp-body' },
        side && layout === 'left' ? h('div', { class: 'lp-side' }, h('i'), h('i'), h('i'), h('i')) : null,
        h('div', { class: 'lp-card' }),
        side && layout === 'right' ? h('div', { class: 'lp-side' }, h('i'), h('i'), h('i'), h('i')) : null)));
}

/// Line at the top of settings that a profile owns, so it is clear which profile they change.
function ProfileScope() {
  if (state.profiles.length < 2) return null;
  return h('div', { class: 'profile-scope' }, ProfileMark(state.profile, 18),
    h('span', { class: 'grow clip' }, T("настройки профиля ", "Настройки профиля ") + quoted(state.profile.name)),
    Button(T("профили", "Профили"), { kind: 'ghost', compact: true, onClick: () => send('settings.open', { section: 'profiles', profile: state.profile.id }) }));
}

function AddressGroup() {
  const style = P().address;
  const sample = S().addressSample || [];
  return Group(T("адресная строка", "Адресная строка"), [
    h('div', { class: 'setting', key: 'sample' }, h('div', { class: 'address-sample', role: 'img', 'aria-label': T("пример адресной строки", "Пример адресной строки") }, icon('lock.fill', 10), h('span', { class: 'clip' }, AddressText(sample)))),
    Setting(T("показывать", "Показывать"), Segmented(style.full, [{ value: false, title: T("сайт", "Сайт") }, { value: true, title: T("полный адрес", "Полный адрес") }], value => setPref('address.full', value), { minWidth: 260, label: T("что показывать в адресной строке", "Что показывать в адресной строке") }), { key: 'mode' }),
    ToggleSetting(T("приглушать поддомен", "Приглушать поддомен"), style.dimSubdomain, value => setPref('address.dimSubdomain', value), { key: 'sub', detail: style.full ? T("www и всё, что стоит перед доменом", "www и всё, что стоит перед доменом") : T("всё, что стоит перед доменом", "Всё, что стоит перед доменом") }),
    style.full ? h('div', { key: 'path', enter: 'fade', exit: 'fade' }, ToggleSetting(T("приглушать путь", "Приглушать путь"), style.dimPath, value => setPref('address.dimPath', value), { detail: T("всё, что после домена: /shoes, ?size и #", "Всё, что после домена: /shoes, ?size и #"), key: 'p' })) : null,
  ], { footnote: T("домен сайта всегда остаётся основным цветом, по нему видно, чей это адрес.", "Домен сайта всегда остаётся основным цветом, по нему видно, чей это адрес."), key: 'address' });
}

function DefaultBrowser() {
  const s = S();
  return [
    Group(T("браузер по умолчанию", "Браузер по умолчанию"), [
      Setting(s.isDefault ? T("mica открывает веб-ссылки", "mica открывает веб-ссылки") : T("открывать веб-ссылки в mica", "Открывать веб-ссылки в mica"),
        s.isDefault ? null : Button(T("сделать основным", "Сделать основным"), { compact: true, disabled: s.defaultBusy, onClick: () => send('settings.makeDefault') })),
    ], { footnote: T("windows подтверждает выбор в параметрах: откроется раздел приложений по умолчанию с mica.", "Windows подтверждает выбор в параметрах: откроется раздел приложений по умолчанию с mica."), key: 'default' }),
    s.defaultFailed ? h('div', { class: 'form-error', key: 'default-failed' }, T("не удалось зарегистрировать mica как браузер. попробуйте ещё раз", "Не удалось зарегистрировать mica как браузер. Попробуйте ещё раз")) : null,
  ];
}

function Space() {
  return [
    DefaultBrowser(), ProfileScope(), LayoutPreview(),
    Group(T("раскладка", "Раскладка"), [
      Setting(T("вкладки", "Вкладки"), LayoutPicker(), { key: 'layout' }),
      ToggleSetting(T("свернуть боковую панель до иконок", "Свернуть боковую панель до иконок"), P().sidebarCollapsed, value => setPref('sidebarCollapsed', value), { key: 'collapse' }),
    ], { footnote: T("при ширине окна меньше 760 px вкладки временно переходят наверх. в свёрнутой боковой панели остаются иконки сайтов, ", "При ширине окна меньше 760 px вкладки временно переходят наверх. В свёрнутой боковой панели остаются иконки сайтов, ") + keys('sidebar') + '.', key: 'layout' }),
    Group(T("панель инструментов", "Панель инструментов"), [
      Setting(T("кнопки и адресная строка", "Кнопки и адресная строка"), Button(T("настроить", "Настроить"), { compact: true, onClick: () => { send('settings.close'); send('customize.toolbar', { on: true }); } }), { detail: T("порядок, сторона и длина строки", "Порядок, сторона и длина строки") }),
    ], { footnote: T("кнопки расставляются перетаскиванием прямо в окне: в шапку, вниз боковой панели или обратно в набор. то же меню есть в меню «…» и по правому клику на боковой панели.", "Кнопки расставляются перетаскиванием прямо в окне: в шапку, вниз боковой панели или обратно в набор. То же меню есть в меню «…» и по правому клику на боковой панели."), key: 'toolbar' }),
    AddressGroup(),
  ];
}

export function ThemeGroup() {
  const custom = P().theme === 'custom';
  return Group(T("тема", "Тема"), [
    Setting(T("тема", "Тема"), ThemePicker(), { key: 'theme' }),
    custom ? [
      h('div', { key: 'base', enter: 'fade', exit: 'fade' }, Setting(T("основа", "Основа"), Segmented(P().customBase, [{ value: 'system', title: T("как в системе", "Как в системе") }, { value: 'light', title: T("светлая", "Светлая") }, { value: 'dark', title: T("тёмная", "Тёмная") }], value => setPref('customBase', value), { minWidth: 380, label: T("основа темы", "Основа темы") }))),
      h('div', { key: 'accent', enter: 'fade', exit: 'fade' }, Setting(T("акцент", "Акцент"), AccentPicker())),
      h('div', { key: 'tint', enter: 'fade', exit: 'fade' }, Setting(T("цвет оболочки", "Цвет оболочки"), h('div', { class: 'row', style: { gap: '8px', width: '222px' } }, Slider(P().customTint, [0, 0.6], value => setPref('customTint', value), { label: T("цвет оболочки", "Цвет оболочки") }), percent(P().customTint / 0.6 * 100)), { detail: T("насколько акцент окрашивает фон окна", "Насколько акцент окрашивает фон окна") })),
    ] : null,
  ], { footnote: custom ? T("акцент окрашивает оболочку, переключатели, основные кнопки и индикатор загрузки. страницы сайтов не меняются.", "Акцент окрашивает оболочку, переключатели, основные кнопки и индикатор загрузки. Страницы сайтов не меняются.") : null, key: 'theme' });
}

export function IconPicker() {
  const icons = S().appIcons || [];
  const current = S().appIcon;
  return h('div', { class: 'icon-picker' }, icons.map(entry => h('button', {
    class: cx('app-icon press', { selected: entry.id === current }), type: 'button', key: entry.id, title: entry.title, 'aria-label': entry.title, 'aria-pressed': entry.id === current ? 'true' : 'false',
    onClick: () => send('settings.appIcon', { id: entry.id }),
  }, h('img', { src: entry.image, alt: '', width: 44, height: 44, draggable: false }))));
}

function Appearance() {
  return [
    ProfileScope(), LayoutPreview(), ThemeGroup(),
    Group(T("материал оболочки", "Материал оболочки"), [
      ToggleSetting(T("матовое стекло", "Матовое стекло"), P().frosted, value => setPref('frosted', value), { key: 'frost' }),
      Setting(T("прозрачность", "Прозрачность"), h('div', { class: 'row', style: { gap: '8px', width: '222px' } }, Slider(P().transparency, [0, 1], value => setPref('transparency', value), { label: T("прозрачность", "Прозрачность"), disabled: !P().frosted }), percent(P().transparency * 100)), { key: 'amount' }),
    ], { footnote: T("размытие и прозрачность относятся только к оболочке, страницы остаются непрозрачными. выключенные «эффекты прозрачности» windows и контрастные темы имеют приоритет.", "Размытие и прозрачность относятся только к оболочке, страницы остаются непрозрачными. Выключенные «Эффекты прозрачности» Windows и контрастные темы имеют приоритет."), key: 'material' }),
    Group(T("иконка приложения", "Иконка приложения"), [h('div', { class: 'setting', key: 'icons' }, IconPicker())],
      { footnote: T("иконка меняется на панели задач и в переключателе окон, пока mica открыта. ярлыки в меню «пуск» и закреплённый значок остаются стандартными.", "Иконка меняется на панели задач и в переключателе окон, пока mica открыта. Ярлыки в меню «Пуск» и закреплённый значок остаются стандартными."), key: 'icon' }),
    Group(T("язык и текст", "Язык и текст"), [
      Setting(T("язык", "Язык"), LanguagePicker(), { key: 'lang' }),
      Setting(T("текст интерфейса", "Текст интерфейса"), CasePicker(), { key: 'case' }),
    ], { footnote: T("у каждого профиля свои язык и регистр, здесь они меняются для профиля этого окна. страницы сайтов, адреса и ваши данные не переводятся.", "У каждого профиля свои язык и регистр, здесь они меняются для профиля этого окна. Страницы сайтов, адреса и ваши данные не переводятся."), key: 'language' }),
  ];
}

const startSectionTitle = section => section === 'custom' ? T("свои сайты", "Свои сайты") : section === 'frequent' ? T("часто открываете", "Часто открываете") : T("закладки", "Закладки");

function StartSettings() {
  const start = P().start;
  const all = start.sections.concat(['custom', 'frequent', 'bookmarks'].filter(section => !start.sections.includes(section)));
  const draft = local().shortcut || (local().shortcut = { text: '', invalid: false });
  const add = () => request('start.saveShortcut', { id: null, address: draft.text, title: '' }).then(ok => update(() => { if (ok) { draft.text = ''; draft.invalid = false; } else draft.invalid = true; }));
  return [
    ProfileScope(),
    Group(T("приветствие", "Приветствие"), NameRows(), { footnote: T("с именем над поиском появляется приветствие, без имени остаётся знак mica. имя хранится только на этом компьютере.", "С именем над поиском появляется приветствие, без имени остаётся знак mica. Имя хранится только на этом компьютере."), key: 'greeting' }),
    Group(T("что показывать", "Что показывать"), [
      ToggleSetting(T("приветствие или знак mica", "Приветствие или знак mica"), start.wordmark, value => send('start.wordmark', { on: value }), { key: 'mark' }),
      all.map(section => {
        const visible = start.sections.includes(section);
        return h('div', { key: section, flip: true }, Setting(startSectionTitle(section), h('span', { class: 'row', style: { gap: '12px' } },
          Switch(visible, value => send('start.setVisible', { section, on: value }), { label: startSectionTitle(section) }),
          h('span', { class: 'row' },
            IconButton('chevron.up', T("выше", "Выше") + ': ' + startSectionTitle(section), { size: 22, disabled: !visible || start.sections[0] === section, onClick: () => send('start.shiftSection', { section, by: -1 }) }),
            IconButton('chevron.down', T("ниже", "Ниже") + ': ' + startSectionTitle(section), { size: 22, disabled: !visible || start.sections[start.sections.length - 1] === section, onClick: () => send('start.shiftSection', { section, by: 1 }) })))));
      }),
      Setting(T("сайтов в ряду", "Сайтов в ряду"), Segmented(start.frequentCount, [4, 8, 12, 16].map(value => ({ value, title: String(value) })), value => send('start.frequentCount', { value }), { compact: true, minWidth: 180, label: T("сайтов в ряду", "Сайтов в ряду") }), { detail: T("в каждом разделе, остальные переходят на следующий ряд", "В каждом разделе, остальные переходят на следующий ряд"), key: 'count' }),
    ], { footnote: T("стрелки меняют порядок разделов. частые сайты считаются по истории обычных окон и не показываются в окне инкогнито.", "Стрелки меняют порядок разделов. Частые сайты считаются по истории обычных окон и не показываются в окне инкогнито."), key: 'show' }),
    Group(T("свои сайты", "Свои сайты"), [
      start.shortcuts.map((shortcut, index) => h('div', { key: shortcut.id, flip: true, enter: 'fade', exit: 'fade' }, Setting(shortcut.title || shortcut.host || shortcut.url, h('span', { class: 'row' },
        IconButton('chevron.up', T("выше", "Выше"), { size: 22, disabled: index === 0, onClick: () => send('start.shiftShortcut', { id: shortcut.id, by: -1 }) }),
        IconButton('chevron.down', T("ниже", "Ниже"), { size: 22, disabled: index === start.shortcuts.length - 1, onClick: () => send('start.shiftShortcut', { id: shortcut.id, by: 1 }) }),
        IconButton('minus.circle', T("удалить ", "Удалить ") + (shortcut.host || ''), { size: 22, onClick: () => send('start.removeShortcut', { id: shortcut.id }) })), { detail: shortcut.url }))),
      h('div', { class: 'setting col', key: 'add', style: { 'align-items': 'stretch' } },
        h('div', { class: 'row', style: { gap: '8px' } },
          h('div', { class: 'grow' }, TextField(T("адрес сайта", "Адрес сайта"), draft.text, value => { draft.text = value; draft.invalid = false; send('settings.draft', { text: value }); update(); }, { symbol: 'plus', onSubmit: add })),
          Button(T("добавить", "Добавить"), { compact: true, disabled: !draft.text.trim(), onClick: add })),
        draft.invalid ? h('div', { class: 'form-error', key: 'invalid' }, T("нужен адрес сайта, а не поисковый запрос", "Нужен адрес сайта, а не поисковый запрос")) : null),
    ], { footnote: T("на начальной странице плитки можно перетаскивать, контекстное меню изменяет и удаляет их.", "На начальной странице плитки можно перетаскивать, контекстное меню изменяет и удаляет их."), key: 'own' }),
    start.hiddenHosts.length ? Group(T("скрытые из частых", "Скрытые из частых"), start.hiddenHosts.map(host => Setting(host, Button(T("вернуть", "Вернуть"), { kind: 'ghost', compact: true, onClick: () => send('start.unhideHost', { host }) }), { key: host })), { key: 'hidden' }) : null,
  ];
}

function SearchSettings() {
  const s = S();
  const filterStatus = !s.blocking ? T("блокировка выключена", "Блокировка выключена")
    : s.blockerCompiling ? T("подготовка фильтров…", "Подготовка фильтров…")
    : s.blockerUpdating ? T("обновление…", "Обновление…")
    : s.blockerIssue || (s.blockerUpdated ? T("обновлены ", "Обновлены ") + new Date(s.blockerUpdated).toLocaleString(locale(), { day: 'numeric', month: 'short', hour: 'numeric', minute: '2-digit' })
      : T("встроенные списки готовы", "Встроенные списки готовы"));
  return [
    Group(T("поиск", "Поиск"), [h('div', { class: 'setting', key: 'engines' }, SearchPicker())], { footnote: T("запрос из адресной строки уходит только выбранному поисковику", "Запрос из адресной строки уходит только выбранному поисковику"), key: 'search' }),
    Group(T("блокировка", "Блокировка"), [
      ToggleSetting(T("блокировать рекламу и трекеры", "Блокировать рекламу и трекеры"), s.blocking, value => send('settings.set', { key: 'blocking', value }), { detail: T("встроенные фильтры uBlock Origin", "Встроенные фильтры uBlock Origin"), key: 'block' }),
      Setting(T("списки фильтров", "Списки фильтров"), Button(T("обновить", "Обновить"), { kind: 'ghost', compact: true, disabled: !s.blocking || s.blockerUpdating, onClick: () => send('settings.updateBlocklist') }),
        { detail: filterStatus, info: InfoTip(T("списки фильтров", "Списки фильтров"), T("mica обновляет списки каждый день без cookie. блокировка работает и в инкогнито. отключить её для отдельного сайта можно в сведениях о сайте. после изменения перезагрузите страницу.", "mica обновляет списки каждый день без cookie. Блокировка работает и в инкогнито. Отключить её для отдельного сайта можно в сведениях о сайте. После изменения перезагрузите страницу.")), key: 'list' }),
    ], { key: 'blocking' }),
    Group(T("сайты без блокировки", "Сайты без блокировки"), HostList('blockingExceptions', s.blockingExceptions || []), { footnote: T("добавьте домен: блокировка отключится для него и его поддоменов. после изменения перезагрузите сайт.", "Добавьте домен: блокировка отключится для него и его поддоменов. После изменения перезагрузите сайт."), key: 'exceptions' }),
    Group(T("данные", "Данные"), [Setting(T("история и данные сайтов", "История и данные сайтов"), Button(T("очистить…", "Очистить…"), { kind: 'destructive', compact: true, onClick: () => send('clearData.open') }), { detail: T("cookie, кэш и локальное хранилище обычных окон", "Cookie, кэш и локальное хранилище обычных окон") })], { key: 'data' }),
  ];
}

/// Question mark next to a setting title; the explanation opens on click so the row itself stays short.
function InfoTip(title, text) {
  return h('button', { class: cx('infotip press', { open: false }), type: 'button', 'aria-label': T("что это: ", "Что это: ") + title, onClick: event => openPopover('info', event.currentTarget, () => h('div', { class: 'infotip-body' }, h('div', { class: 'popover-title' }, title), h('div', { class: 'infotip-text' }, text)), { width: 300 }) }, icon('questionmark.circle', 12));
}

/// A list of hosts with an add field (HostListEditor on macOS).
function HostList(key, hosts) {
  const draft = local()[key] || (local()[key] = { text: '' });
  const add = () => {
    const host = draft.text.trim().toLowerCase();
    if (host.length > 253 || !/^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z](?:[a-z0-9-]{0,61}[a-z0-9])?$/.test(host)) { draft.invalid = true; update(); return; }
    send('settings.hosts', { key, hosts: Array.from(new Set(hosts.concat(host))) });
    draft.text = ''; draft.invalid = false; send('settings.draft', { text: '' }); update();
  };
  return [
    h('div', { class: 'setting', key: 'add' }, h('div', { class: 'grow' }, TextField(T("домен, например mail.example.com", "Домен, например mail.example.com"), draft.text, value => { draft.text = value; send('settings.draft', { text: value }); update(); }, { symbol: 'plus', selectionStyle: true, onSubmit: add })), Button(T("добавить", "Добавить"), { compact: true, disabled: !draft.text.trim(), onClick: add })),
    draft.invalid ? h('div', { class: 'setting form-error', key: 'invalid' }, T("нужен домен без пути, например mail.example.com", "Нужен домен без пути, например mail.example.com")) : null,
    hosts.map(host => Setting(host, IconButton('minus.circle', T("удалить ", "Удалить ") + host, { size: 22, onClick: () => send('settings.hosts', { key, hosts: hosts.filter(other => other !== host) }) }), { key: host })),
  ];
}

function SessionSettings() {
  const s = S();
  return [
    Group(T("при запуске", "При запуске"), [
      ToggleSetting(T("восстанавливать окна и вкладки", "Восстанавливать окна и вкладки"), s.restore, value => send('settings.set', { key: 'restore', value }), { key: 'restore' }),
      ToggleSetting(T("загружать сохранённые вкладки при выборе", "Загружать сохранённые вкладки при выборе"), s.lazyRestore, value => send('settings.set', { key: 'lazyRestore', value }), { disabled: !s.restore, key: 'lazy' }),
    ], { footnote: T("это касается только запуска. открытые вами вкладки остаются живыми, включая фоновые. несохранённые формы после сбоя не восстанавливаются.", "Это касается только запуска. Открытые вами вкладки остаются живыми, включая фоновые. Несохранённые формы после сбоя не восстанавливаются."), key: 'startup' }),
    Group(T("всегда загружать при запуске", "Всегда загружать при запуске"), HostList('eagerHosts', s.eagerHosts || []), { footnote: T("например, почта или мессенджер, которым нужны уведомления сразу", "Например, почта или мессенджер, которым нужны уведомления сразу"), key: 'eager' }),
    Group(T("память", "Память"), [Setting(T("выгрузка живых вкладок", "Выгрузка живых вкладок"), h('span', { class: 'value-label' }, T("выключена", "Выключена")))],
      { footnote: T("WebView2 не сообщает надёжно о звонках, формах и WebSocket, поэтому mica не выгружает живые вкладки. автоматического таймера выгрузки нет; скрытые вкладки сами притормаживает Chromium.", "WebView2 не сообщает надёжно о звонках, формах и WebSocket, поэтому mica не выгружает живые вкладки. Автоматического таймера выгрузки нет; скрытые вкладки сами притормаживает Chromium."), key: 'memory' }),
  ];
}

function PermissionSettings() {
  const s = S();
  const decisions = [{ value: 'ask', title: T("спрашивать", "Спрашивать") }, { value: 'allow', title: T("разрешить", "Разрешить") }, { value: 'deny', title: T("запретить", "Запретить") }];
  const system = [['camera', 'ms-settings:privacy-webcam'], ['microphone', 'ms-settings:privacy-microphone'], ['location', 'ms-settings:privacy-location'], ['notifications', 'ms-settings:notifications']];
  return [
    Group('Windows', system.map(([capability, uri]) => Setting(capabilityName(capability), Button(T("открыть", "Открыть"), { compact: true, onClick: () => send('system.settings', { uri }) }), { key: capability })),
      { footnote: T("системный доступ к камере, микрофону, геолокации и уведомлениям меняется в параметрах windows", "Системный доступ к камере, микрофону, геолокации и уведомлениям меняется в параметрах Windows"), key: 'system' }),
    Group(T("уведомления сайтов", "Уведомления сайтов"), [ToggleSetting(T("сайты могут спрашивать разрешение", "Сайты могут спрашивать разрешение"), s.notificationRequests, value => send('settings.set', { key: 'notificationRequests', value }))],
      { footnote: T("уведомления приходят от открытых вкладок. push-уведомления закрытых сайтов не поддерживаются. в окнах инкогнито уведомления запрещены.", "Уведомления приходят от открытых вкладок. Push-уведомления закрытых сайтов не поддерживаются. В окнах инкогнито уведомления запрещены."), key: 'notifications' }),
    Group(T("решения для сайтов", "Решения для сайтов"), (s.permissions || []).length
      ? s.permissions.map(record => Setting(record.origin, Segmented(record.decision, decisions, value => send('site.permission', { origin: record.origin, capability: record.capability, decision: value }), { compact: true, minWidth: 270, label: record.origin }), { detail: capabilityName(record.capability), key: record.origin + record.capability }))
      : [h('div', { class: 'setting muted', key: 'none' }, T("сайты пока ничего не запрашивали", "Сайты пока ничего не запрашивали"))],
      { footnote: T("решения окон инкогнито существуют только внутри окна.", "Решения окон инкогнито существуют только внутри окна."), key: 'decisions' }),
    (s.appLinks || []).length ? Group(T("ссылки в приложениях", "Ссылки в приложениях"),
      s.appLinks.map(record => Setting(record.origin, Button(T("удалить", "Удалить"), { compact: true, onClick: () => send('appLink.remove', { id: record.id }) }), { detail: record.detail, key: record.id })),
      { footnote: T("эти сайты открывают такие ссылки без вопроса", "Эти сайты открывают такие ссылки без вопроса"), key: 'appLinks' }) : null,
  ];
}

const ROW_ICON = geometry.chrome.rowIcon;

function PasswordSettings() {
  const s = S(), p = s.passwords || { logins: [], never: [] };
  const query = local().passwordQuery || '';
  const lower = query.trim().toLocaleLowerCase();
  const logins = p.logins.filter(login => !lower || login.origin.toLocaleLowerCase().includes(lower) || (login.username || '').toLocaleLowerCase().includes(lower));
  return [
    Group(T("автозаполнение", "Автозаполнение"), [
      ToggleSetting(T("предлагать сохранение и создание паролей", "Предлагать сохранение и создание паролей"), s.offerPasswords, value => send('settings.set', { key: 'offerPasswords', value }), { key: 'offer' }),
      ToggleSetting(T("предлагать сохранённые учётные записи", "Предлагать сохранённые учётные записи"), s.fillPasswords, value => send('settings.set', { key: 'fillPasswords', value }), { key: 'fill' }),
    ], { key: 'auto' }),
    p.status ? h('div', { class: 'lib-note selectable', key: 'status' }, p.status) : null,
    Group(T("сохранённые пароли", "Сохранённые пароли"), [
      h('div', { class: 'setting', key: 'search' }, h('div', { class: 'grow' }, TextField(T("поиск по сайту или имени", "Поиск по сайту или имени"), query, value => update(() => { local().passwordQuery = value; }), { symbol: 'magnifyingglass' }))),
      logins.length ? logins.map(login => {
        const revealed = p.revealed === login.id && p.secret, copied = p.copied === login.id;
        // PasswordRow on macOS: the site's icon and host, the user name, the password once revealed; icon actions at the end.
        return h('div', { class: 'setting login-row', key: login.id },
          SiteTile(login, ROW_ICON),
          h('div', { class: 'setting-labels' },
            h('div', { class: 'login-host clip', title: login.origin }, login.host || login.origin),
            h('div', { class: cx('login-user clip selectable', { muted: !login.username }) }, login.username || T("без имени пользователя", "Без имени пользователя")),
            revealed ? h('div', { class: 'mono selectable password-shown', key: 'secret', enter: 'fade' }, p.secret) : null),
          h('div', { class: 'login-actions' },
            IconButton(revealed ? 'eye.slash' : 'eye', revealed ? T("скрыть", "Скрыть") : T("показать", "Показать"), { selected: !!revealed, onClick: () => send('passwords.reveal', { id: login.id }) }),
            IconButton(copied ? 'checkmark' : 'square.on.square', copied ? T("скопировано", "Скопировано") : T("копировать", "Копировать"), { onClick: () => send('passwords.copy', { id: login.id }) }),
            IconButton('trash', T("удалить", "Удалить"), { onClick: () => send('passwords.remove', { id: login.id }) })));
      })
        : h('div', { class: 'setting muted', key: 'none' }, T("пароли не найдены", "Пароли не найдены")),
    ], { key: 'saved' }),
    Group(T("сайты без сохранения", "Сайты без сохранения"), p.never.length
      ? p.never.map(origin => Setting(origin, Button(T("удалить", "Удалить"), { compact: true, onClick: () => send('passwords.removeNever', { origin }) }), { key: origin }))
      : [h('div', { class: 'setting muted', key: 'none' }, T("исключений нет", "Исключений нет"))], { key: 'never' }),
    h('div', { class: 'group-note', key: 'note' }, T("пароли хранятся в зашифрованном файле на этом компьютере. ключ защищён windows для вашей учётной записи. перенос и синхронизация паролей не поддерживаются.", "Пароли хранятся в зашифрованном файле на этом компьютере. Ключ защищён Windows для вашей учётной записи. Перенос и синхронизация паролей не поддерживаются.")),
  ];
}

/// History and bookmarks from another browser. The host finds the browsers and their profiles.
export function Transfer() {
  const t = S().importer || { browsers: [] };
  return [
    Group(T("браузеры на этом компьютере", "Браузеры на этом компьютере"), t.browsers.length
      ? t.browsers.map(browser => Setting(browser.name, h('span', { class: 'row', style: { gap: '8px' } },
          browser.profiles.length > 1 ? Segmented(browser.selected, browser.profiles.map(profile => ({ value: profile.path, title: profile.name })), value => send('import.profile', { browser: browser.id, path: value }), { compact: true, label: browser.name }) : null,
          Button(t.running === browser.id ? T("переносим…", "Переносим…") : T("перенести", "Перенести"), { compact: true, kind: 'primary', disabled: !!t.running, onClick: () => send('import.run', { browser: browser.id }) })),
          { detail: browser.result || browser.detail || null, key: browser.id }))
      : [h('div', { class: 'setting muted', key: 'none' }, T("другие браузеры не найдены", "Другие браузеры не найдены"))],
      { footnote: T("переносятся история и закладки. пароли, cookie и расширения не переносятся.", "Переносятся история и закладки. Пароли, cookie и расширения не переносятся."), key: 'browsers' }),
    t.message ? h('div', { class: cx('lib-note', { danger: t.failed }), key: 'message' }, t.message) : null,
    LinkRow(T("другие источники…", "Другие источники…"), 'folder', () => send('import.choose'), 'other'),
  ];
}

/// Profile gallery and the editor of the chosen profile (ProfileSettings on macOS).
function Profiles() {
  const editing = state.profiles.find(profile => profile.id === (S().editingProfile || state.profile.id)) || state.profile;
  const draft = local().profileName && local().profileName.id === editing.id ? local().profileName : (local().profileName = { id: editing.id, text: editing.name });
  const status = profile => profile.id === state.profile.id ? T("это окно", "Это окно") : profile.open ? T("открыт в другом окне", "Открыт в другом окне") : profile.standard ? T("основной", "Основной") : T("не открыт", "Не открыт");
  return [
    h('div', { class: 'profile-gallery', key: 'gallery' },
      state.profiles.map(profile => h('button', {
        class: cx('profile-card press', { selected: profile.id === editing.id }), type: 'button', key: profile.id, flip: true, enter: 'pop', exit: 'pop',
        onClick: () => send('settings.editProfile', { id: profile.id }), 'aria-pressed': profile.id === editing.id ? 'true' : 'false',
      }, ProfileMark(profile, 44, { class: 'grows' }), h('span', { class: 'profile-card-name clip' }, profile.name), h('span', { class: 'profile-card-status clip' }, status(profile)))),
      state.profiles.length < state.profileLimit ? h('button', { class: 'profile-card add press', type: 'button', key: 'add', flip: true, onClick: () => send('profile.add') },
        h('span', { class: 'profile-add-mark' }, icon('plus', 16, 'regular')), h('span', { class: 'profile-card-name' }, T("новый профиль", "Новый профиль"))) : null),
    Group(null, [Setting(T("профиль из меню открывать", "Профиль из меню открывать"), Segmented(S().profileOpening || 'ask', [{ value: 'ask', title: T("спрашивать", "Спрашивать") }, { value: 'here', title: T("в этом окне", "В этом окне") }, { value: 'newWindow', title: T("в новом окне", "В новом окне") }], value => send('settings.set', { key: 'profileOpening', value }), { compact: true, label: T("профиль из меню открывать", "Профиль из меню открывать") }))], { key: 'opening' }),
    h('div', { class: 'profile-cover', key: 'cover-' + editing.id, enter: 'fade', style: { '--tint': editing.background } },
      ProfileMark(editing, 72, { class: 'cover-mark', style: { 'box-shadow': `0 6px 24px ${editing.background}59` } }),
      h('div', { class: 'col grow', style: { gap: '10px' } },
        h('input', { class: 'profile-name-input', value: draft.text, maxLength: 32, 'aria-label': T("название профиля", "Название профиля"), placeholder: editing.standard ? T("основной", "Основной") : '',
          onInput: event => { draft.text = event.target.value; send('profile.rename', { id: editing.id, name: draft.text }); } }),
        h('div', { class: 'row', style: { gap: '8px', 'flex-wrap': 'wrap' } },
          editing.id === state.profile.id ? h('span', { class: 'value-label' }, T("это окно", "Это окно")) : Button(T("переключить это окно", "Переключить это окно"), { kind: 'primary', compact: true, onClick: () => send('profile.open', { id: editing.id, where: 'here' }) }),
          Button(T("открыть в новом окне", "Открыть в новом окне"), { compact: true, onClick: () => send('profile.open', { id: editing.id, where: 'newWindow' }) }),
          editing.standard ? null : IconButton('trash', T("удалить профиль", "Удалить профиль"), { onClick: () => send('profile.remove', { id: editing.id }) })))),
    Group(T("значок", "Значок"), [
      h('div', { class: 'setting', key: 'icons' }, h('div', { class: 'profile-icons' }, profileCatalog.icons.map(name => h('button', {
        class: cx('profile-icon press', { selected: editing.icon === name }), type: 'button', key: name, 'aria-label': name, 'aria-pressed': editing.icon === name ? 'true' : 'false',
        onClick: () => send('profile.look', { id: editing.id, icon: name }),
      }, ProfileMark({ ...editing, icon: name }, 30))))),
      Setting(T("фон", "Фон"), h('div', { class: 'swatches' }, profileCatalog.backgrounds.map(color => h('button', { class: cx('swatch press', { selected: editing.background.toUpperCase() === color }), type: 'button', key: color, 'aria-label': color, style: { '--c': color }, onClick: () => send('profile.look', { id: editing.id, background: color }) })),
        ColorWell(profileCatalog.backgrounds.includes(editing.background.toUpperCase()) ? null : editing.background, color => send('profile.look', { id: editing.id, background: color }), T("свой цвет", "Свой цвет"))), { key: 'bg' }),
      Setting(T("цвет значка", "Цвет значка"), Segmented(editing.glyph || 'auto', [{ value: 'auto', title: T("авто", "Авто") }, { value: 'light', title: T("белый", "Белый") }, { value: 'dark', title: T("чёрный", "Чёрный") }], value => send('profile.look', { id: editing.id, glyph: value }), { compact: true, label: T("цвет значка", "Цвет значка") }), { key: 'glyph' }),
    ], { key: 'look' }),
  ];
}

function About() {
  const s = S();
  return [
    h('div', { class: 'about-intro', key: 'intro' },
      h('p', null, T("mica — браузер, в котором вкладки не перезагружаются, когда вы к ним возвращаетесь: страница остаётся такой, какой вы её оставили.", "mica — браузер, в котором вкладки не перезагружаются, когда вы к ним возвращаетесь: страница остаётся такой, какой вы её оставили.")),
      h('p', null, T("реклама и трекеры блокируются сразу, расширения ставятся из Chrome Web Store. собственной телеметрии нет.", "Реклама и трекеры блокируются сразу, расширения ставятся из Chrome Web Store. Собственной телеметрии нет."))),
    Group(null, [
      Setting(T("версия", "Версия"), h('span', { class: 'value-label selectable' }, s.version || '?'), { key: 'version' }),
      ToggleSetting(T("проверять обновления каждый день", "Проверять обновления каждый день"), s.updateChecks, value => send('settings.set', { key: 'updateChecks', value }), { key: 'updates' }),
    ], { key: 'about' }),
    h('div', { key: 'again' }, Button(T("пройти знакомство ещё раз", "Пройти знакомство ещё раз"), { onClick: () => send('onboarding.open') })),
  ];
}

function content(id) {
  switch (id) {
    case 'space': return Space();
    case 'appearance': return Appearance();
    case 'start': return StartSettings();
    case 'profiles': return Profiles();
    case 'search': return SearchSettings();
    case 'session': return SessionSettings();
    case 'transfer': return Transfer();
    case 'permissions': return PermissionSettings();
    case 'passwords': return PasswordSettings();
    default: return About();
  }
}

export function SettingsView(width) {
  const section = S().section || 'space';
  const compact = width < 720;
  const close = () => send('settings.close');
  return h('div', { class: 'settings', key: 'settings' },
    h('nav', { class: cx('settings-nav', { compact }) },
      compact ? null : h('div', { class: 'settings-heading' }, T("настройки", "Настройки")),
      Nav(sections.map(([id, symbol]) => ({ id, symbol, title: sectionTitle(id) })), section, id => send('settings.open', { section: id }), { compact }),
      h('div', { class: 'spacer' }),
      compact ? IconButton('xmark', T("готово", "Готово"), { size: 36, onClick: close }) : Button(T("готово", "Готово"), { kind: 'primary', fill: true, onClick: close })),
    h('div', { class: 'settings-content col' },
      h('div', { class: 'grow scroll', style: { 'min-height': 0 } },
        h('div', { class: 'settings-page', key: section, enter: { name: 'fade', run: el => sectionEnter(el) } },
          h('h1', { class: 'settings-title' }, sectionTitle(section)),
          content(section))),
      // Pinned under the scrolling content, as the safe area inset on macOS.
      section === 'about' ? h('div', { class: 'settings-signature', key: 'signature', enter: 'fade', exit: { name: 'fade', float: false } }, T("develop whoa with ❤️", "Develop whoa with ❤️")) : null));
}

import { springs, isReduced } from '../core/motion.js';
function sectionEnter(el) {
  if (isReduced()) { el.animate([{ opacity: 0 }, { opacity: 1 }], { duration: 120, easing: 'ease-out' }); return; }
  const options = { duration: springs.snappy.ms, easing: springs.snappy.easing };
  el.animate([{ opacity: 0 }, { opacity: 1 }], options);
  el.animate([{ translate: '0 8px' }, { translate: '0 0' }], options);
}

// Onboarding: the same layout as settings, with a column of steps.

const steps = [['hand.wave'], ['square.and.arrow.down.on.square'], ['sidebar.squares.left'], ['paintbrush'], ['shield.lefthalf.filled'], ['square.stack']];
function stepName(i) { return [T("знакомство", "Знакомство"), T("перенос данных", "Перенос данных"), T("пространство", "Пространство"), T("оформление", "Оформление"), T("поиск и защита", "Поиск и защита"), T("сессия", "Сессия")][i]; }
function stepTitle(i) { return [T("привет, это mica", "Привет, это mica"), T("всё уже на месте", "Всё уже на месте"), T("ваше пространство", "Ваше пространство"), T("цвет и иконка", "Цвет и иконка"), T("спокойнее с первого запуска", "Спокойнее с первого запуска"), T("работа остаётся с вами", "Работа остаётся с вами")][i]; }
function stepDetail(i) { return [T("язык, имя и стиль текста. всё можно поменять позже в настройках", "Язык, имя и стиль текста. Всё можно поменять позже в настройках"), T("история и закладки из другого браузера. шаг можно пропустить", "История и закладки из другого браузера. Шаг можно пропустить"), T("изменения видны сразу", "Изменения видны сразу"), T("тема окна, акцент и иконка mica на панели задач", "Тема окна, акцент и иконка mica на панели задач"), T("поиск, блокировка и разрешения", "Поиск, блокировка и разрешения"), T("вкладки, сессия и клавиши", "Вкладки, сессия и клавиши")][i]; }

function stepContent(i) {
  const s = S();
  switch (i) {
    case 0: return [
      Group(null, [Setting(T("язык", "Язык"), LanguagePicker(), { key: 'lang' }), Setting(T("текст интерфейса", "Текст интерфейса"), CasePicker(), { key: 'case' }), NameRows()], { key: 'basics' }),
      DefaultBrowser(),
    ];
    case 1: return Transfer();
    case 2: return [LayoutPreview(), Group(null, [Setting(T("вкладки", "Вкладки"), LayoutPicker(), { key: 'layout' }), ToggleSetting(T("матовое стекло оболочки", "Матовое стекло оболочки"), P().frosted, value => setPref('frosted', value), { key: 'frost' })], { key: 'space' })];
    case 3: return [ThemeGroup(), Group(T("иконка приложения", "Иконка приложения"), [h('div', { class: 'setting', key: 'icons' }, IconPicker())], { key: 'icon' })];
    case 4: return [
      Group(T("поисковик", "Поисковик"), [h('div', { class: 'setting', key: 'engines' }, SearchPicker())], { key: 'engine' }),
      Group(null, [ToggleSetting(T("блокировать рекламу и трекеры", "Блокировать рекламу и трекеры"), s.blocking, value => send('settings.set', { key: 'blocking', value }), { detail: T("локальная проверка запросов к известным сторонним доменам", "Локальная проверка запросов к известным сторонним доменам") })], { key: 'block' }),
      h('ol', { class: 'facts', key: 'facts' },
        h('li', null, T("камера, микрофон и геолокация запрашиваются только по запросу сайта, с его адресом в вопросе", "Камера, микрофон и геолокация запрашиваются только по запросу сайта, с его адресом в вопросе")),
        h('li', null, T("окна инкогнито не сохраняют историю, cookie и сессию", "Окна инкогнито не сохраняют историю, cookie и сессию")),
        h('li', null, T("список блокировки обновляется только вручную в настройках", "Список блокировки обновляется только вручную в настройках"))),
    ];
    default: return [
      Group(null, [
        ToggleSetting(T("восстанавливать окна и вкладки", "Восстанавливать окна и вкладки"), s.restore, value => send('settings.set', { key: 'restore', value }), { key: 'restore' }),
        ToggleSetting(T("загружать сохранённые вкладки при выборе", "Загружать сохранённые вкладки при выборе"), s.lazyRestore, value => send('settings.set', { key: 'lazyRestore', value }), { disabled: !s.restore, key: 'lazy' }),
      ], { footnote: T("после открытия вкладки остаются живыми, mica не выгружает страницы по таймеру. после сбоя восстановятся адреса, но не несохранённые формы.", "После открытия вкладки остаются живыми, mica не выгружает страницы по таймеру. После сбоя восстановятся адреса, но не несохранённые формы."), key: 'session' }),
      Group(null, [['address', T("адрес и поиск", "Адрес и поиск")], ['tab', T("новая вкладка", "Новая вкладка")], ['private', T("окно инкогнито", "Окно инкогнито")], ['sidebar', T("боковая панель", "Боковая панель")]]
        .map(([command, title]) => Setting(title, KeyHint(keys(command)), { key: command })), { key: 'keys' }),
    ];
  }
}

export function OnboardingView(width) {
  const step = state.overlay.onboardingStep || 0;
  const compact = width < 720;
  const go = index => send('onboarding.step', { step: index });
  const last = step === steps.length - 1;
  const back = local().onboardingFrom != null && local().onboardingFrom > step;
  local().onboardingFrom = step;
  return h('div', { class: 'settings onboarding', key: 'onboarding' },
    h('nav', { class: cx('settings-nav', { compact }) },
      compact ? null : h('div', { class: 'settings-heading' }, 'mica'),
      Nav(steps.map(([symbol], i) => ({ id: i, symbol, title: stepName(i) })), step, go, { compact })),
    h('div', { class: 'settings-content col' },
      h('div', { class: 'grow scroll', style: { 'min-height': 0 } },
        h('div', { class: 'settings-page', key: 'step-' + step, enter: { name: 'fade', run: el => stepEnter(el, back) } },
          h('h1', { class: 'settings-title' }, stepTitle(step)),
          h('div', { class: 'settings-lead' }, stepDetail(step)),
          stepContent(step))),
      h('div', { class: 'onboarding-footer' },
        step > 0 ? Button(T("назад", "Назад"), { kind: 'ghost', onClick: () => go(step - 1) }) : null,
        h('span', { class: 'spacer' }),
        h('span', { class: 'value-label tabular' }, T("шаг ", "Шаг ") + (step + 1) + ' / ' + steps.length),
        Button(last ? T("начать", "Начать") : T("дальше", "Дальше"), { kind: 'primary', onClick: () => last ? send('onboarding.finish') : go(step + 1) }))));
}

function stepEnter(el, backward) {
  if (isReduced()) { el.animate([{ opacity: 0 }, { opacity: 1 }], { duration: 120, easing: 'ease-out' }); return; }
  const options = { duration: springs.panel.ms, easing: springs.panel.easing };
  el.animate([{ opacity: 0 }, { opacity: 1 }], options);
  el.animate([{ translate: `${backward ? -16 : 16}px 0` }, { translate: '0 0' }], options);
}
