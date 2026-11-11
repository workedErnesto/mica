// Interface text. Russian variants are written at the call site: T("строчный", "Обычный"); English comes from
// shared/strings/en.txt keyed by the regular Russian text, exactly as Mica.Core.Copy does. The style (lowercase
// or regular) and the language belong to the profile of the window. Page content, addresses and user data never
// pass through here.

import { english } from '../gen/strings.g.js';
import { keymap } from '../gen/tokens.g.js';

let lowercase = true;
let language = 'ru';

export function setTextStyle(style) {
  lowercase = style.lowercase !== false;
  language = style.language === 'en' ? 'en' : 'ru';
  document.documentElement.lang = language;
}

export function T(low, regular) {
  if (language === 'en') {
    const pair = english[regular];
    if (pair) return lowercase ? pair[0] : pair[1];
  }
  return lowercase ? low : regular;
}

export function lang() { return language; }
export function isLowercase() { return lowercase; }

/// «text» in Russian, "text" in English.
export function quoted(text) { return language === 'en' ? '“' + text + '”' : '«' + text + '»'; }

/// First Windows shortcut of a command from shared/keymap.json, as shown in menus and tooltips: "Ctrl+T".
export function keys(command) {
  const list = keymap[command];
  return list && list.length ? label(list[0]) : '';
}

function label(shortcut) {
  return shortcut.split('+').map(part => {
    switch (part) {
      case 'Left': return '←';
      case 'Right': return '→';
      case 'PageDown': return 'PgDn';
      case 'PageUp': return 'PgUp';
      case 'Delete': return 'Del';
      case 'Add': return '+';
      case 'Subtract': return '-';
      default: return part;
    }
  }).join('+');
}

/// Tooltip text with the shortcut after it.
export function withKeys(text, command) {
  const hint = keys(command);
  return hint ? text + ' ' + hint : text;
}

const sizeUnits = { ru: ['Б', 'КБ', 'МБ', 'ГБ'], en: ['B', 'KB', 'MB', 'GB'] };
export function fileSize(bytes) {
  if (!(bytes >= 0)) return '';
  const units = sizeUnits[language];
  let value = bytes, unit = 0;
  while (value >= 1000 && unit < units.length - 1) { value /= 1000; unit++; }
  const digits = unit === 0 || value >= 100 ? 0 : 1;
  return value.toLocaleString(language === 'en' ? 'en-US' : 'ru-RU', { maximumFractionDigits: digits, minimumFractionDigits: 0 }) + ' ' + units[unit];
}

export function locale() { return language === 'en' ? 'en-US' : 'ru-RU'; }
