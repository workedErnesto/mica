// Icons of the mica shell on Windows, drawn here on a 20 unit grid with round caps and joins.
// The names are the SF Symbol names the macOS source uses (shared/glyphs.json lists them), so both platforms
// ask for the same sign; SF Symbols themselves may not ship outside Apple platforms, these are mica's own drawings.
// `icon(name, size)` takes the size the macOS code passes to `.font(.system(size:))`: the drawing box is BOX of it,
// which is how large a symbol of that point size is.

import { h } from './dom.js';

const p = d => `<path d="${d}"/>`;
const f = d => `<path d="${d}" fill="currentColor" stroke="none"/>`;
const c = (x, y, r) => `<circle cx="${x}" cy="${y}" r="${r}"/>`;
const dot = (x, y, r = 0.95) => `<circle cx="${x}" cy="${y}" r="${r}" fill="currentColor" stroke="none"/>`;
const r = (x, y, w, hh, rx) => `<rect x="${x}" y="${y}" width="${w}" height="${hh}" rx="${rx}"/>`;
const rf = (x, y, w, hh, rx) => `<rect x="${x}" y="${y}" width="${w}" height="${hh}" rx="${rx}" fill="currentColor" stroke="none"/>`;

function gear() {
  // Eight flat teeth around a ring, the hub open.
  const teeth = 8, outer = 7.6, inner = 5.9, half = Math.PI / teeth;
  const tip = half * 0.52, root = half * 0.82;
  let d = '';
  for (let i = 0; i < teeth; i++) {
    const a = i * 2 * half - Math.PI / 2;
    const pts = [[inner, a - root], [outer, a - tip], [outer, a + tip], [inner, a + root]];
    for (const [radius, angle] of pts) d += (d ? 'L' : 'M') + (10 + radius * Math.cos(angle)).toFixed(2) + ' ' + (10 + radius * Math.sin(angle)).toFixed(2);
  }
  return p(d + 'Z') + c(10, 10, 2.5);
}

const shield = 'M10 2.75l5.75 2.1v4.4c0 3.6-2.3 6.4-5.75 8-3.45-1.6-5.75-4.4-5.75-8v-4.4z';
const eye = p('M2.5 10S5.25 5 10 5s7.5 5 7.5 5-2.75 5-7.5 5-7.5-5-7.5-5z') + c(10, 10, 2.4);
const bell = p('M5.5 13.5V9a4.5 4.5 0 0 1 9 0v4.5l1.25 1.5H4.25zM8.5 17a1.6 1.6 0 0 0 3 0');
const pin = p('M7.25 3.25h5.5M8 3.25v5L5.75 11.5v1h8.5v-1L12 8.25v-5M10 12.5v4.75');
const trash = p('M3.75 5.5h12.5M8 5.5V4a1 1 0 0 1 1-1h2a1 1 0 0 1 1 1v1.5M5.25 5.5l.6 10.1a1.5 1.5 0 0 0 1.5 1.4h5.3a1.5 1.5 0 0 0 1.5-1.4l.6-10.1M8.4 8.5v5.5M11.6 8.5v5.5');
const doc = p('M5.75 2.75h5.5l3.75 3.75v10a.75.75 0 0 1-.75.75h-8.5A.75.75 0 0 1 5 16.5v-13a.75.75 0 0 1 .75-.75zM11 3v3.75h3.75');
const tray = 'M6.5 8H5.5A1.5 1.5 0 0 0 4 9.5v6A1.5 1.5 0 0 0 5.5 17h9a1.5 1.5 0 0 0 1.5-1.5v-6A1.5 1.5 0 0 0 14.5 8h-1';
const sidebarFrame = r(2.5, 4, 15, 12, 2.5);
const hand = p('M7 10V4.75a1 1 0 0 1 2 0V9M9 9V3.75a1 1 0 0 1 2 0V9M11 9V4.5a1 1 0 0 1 2 0V10M13 10V6.5a1 1 0 0 1 2 0v6a4.75 4.75 0 0 1-4.75 4.75h-.6a4.5 4.5 0 0 1-3.5-1.7L3.6 12a1.1 1.1 0 0 1 1.7-1.4L7 12.25V9');
const backSquare = 'M13 7V5.25A2.25 2.25 0 0 0 10.75 3h-5.5A2.25 2.25 0 0 0 3 5.25v5.5A2.25 2.25 0 0 0 5.25 13H7';
const bookmark = 'M6 3.5h8a.75.75 0 0 1 .75.75V16.5L10 13l-4.75 3.5V4.25A.75.75 0 0 1 6 3.5z';
const star = 'M10 2.9l2.2 4.5 4.95.7-3.6 3.5.85 4.9L10 14.2l-4.4 2.3.85-4.9-3.6-3.5 4.95-.7z';
const glass = c(8.75, 8.75, 5) + p('M12.5 12.5l4 4');
const stackedRect = r(6.5, 7, 10.5, 8.5, 2) + p('M13.5 7V5.5a2 2 0 0 0-2-2H5a2 2 0 0 0-2 2V10a2 2 0 0 0 2 2h1.5');

const glyphs = {
  'airplane': p('M10 2.5c.8 0 1.25.9 1.25 2v3.25l5.5 3.5v1.5l-5.5-1.75v3.25l1.75 1.5v1.25L10 16.25 7 17v-1.25l1.75-1.5V11L3.25 12.75v-1.5l5.5-3.5V4.5c0-1.1.45-2 1.25-2z'),
  'archivebox': r(2.75, 4, 14.5, 4, 1.25) + p('M4 8v6.75A1.25 1.25 0 0 0 5.25 16h9.5A1.25 1.25 0 0 0 16 14.75V8M8 11h4'),
  'arrow.clockwise': p('M16.1 10.4a6.1 6.1 0 1 1-6.1-6.1c1.7 0 3.35.68 4.58 1.86L16.1 7.7M16.1 4.3v3.4h-3.4'),
  'arrow.counterclockwise': p('M3.9 10.4a6.1 6.1 0 1 0 6.1-6.1c-1.7 0-3.35.68-4.58 1.86L3.9 7.7M3.9 4.3v3.4h3.4'),
  'arrow.down': p('M10 4v12M5.25 11.25L10 16l4.75-4.75'),
  'arrow.down.circle': c(10, 10, 7) + p('M10 6.5v7M7 10.75l3 3 3-3'),
  'arrow.left': p('M16 10H4M8.75 5.25L4 10l4.75 4.75'),
  'arrow.right': p('M4 10h12M11.25 5.25L16 10l-4.75 4.75'),
  'arrow.triangle.2.circlepath': p('M4.2 9a6 6 0 0 1 10.3-3.2L16 7.3M16 4v3.3h-3.3M15.8 11a6 6 0 0 1-10.3 3.2L4 12.7M4 16v-3.3h3.3'),
  'arrow.up.left.and.arrow.down.right': p('M4.5 4.5l4.25 4.25M4.5 8.25V4.5h3.75M15.5 15.5l-4.25-4.25M15.5 11.75v3.75h-3.75'),
  'arrow.up.right': p('M5.5 14.5l9-9M7.5 5.5h7v7'),
  'bell': bell,
  'bell.slash': bell + p('M3.5 3.5l13 13'),
  'bolt': p('M11 2.75L4.75 11.25h4.5L8.5 17.25l6.75-8.75h-4.5z'),
  'book': p('M10 5.5C8.5 4.4 6.4 4 3.5 4v11c2.9 0 5 .4 6.5 1.5 1.5-1.1 3.6-1.5 6.5-1.5V4c-2.9 0-5 .4-6.5 1.5zM10 5.5v11'),
  'bookmark': p(bookmark),
  'bookmark.fill': `<path d="${bookmark}" fill="currentColor"/>`,
  'briefcase': r(3, 6.5, 14, 9.5, 2) + p('M7.25 6.5V5a1.5 1.5 0 0 1 1.5-1.5h2.5a1.5 1.5 0 0 1 1.5 1.5v1.5M3 11h14'),
  'camera': p('M3 7.25A1.75 1.75 0 0 1 4.75 5.5h1.6l1-1.75h5.3l1 1.75h1.6A1.75 1.75 0 0 1 17 7.25v7A1.75 1.75 0 0 1 15.25 16H4.75A1.75 1.75 0 0 1 3 14.25z') + c(10, 10.75, 2.9),
  'car': p('M3.25 11.5l1.4-4.2A1.9 1.9 0 0 1 6.45 6h7.1a1.9 1.9 0 0 1 1.8 1.3l1.4 4.2M3 11.5h14v3.75H3zM5 15.25v1.25M15 15.25v1.25') + dot(6, 13.4, 0.8) + dot(14, 13.4, 0.8),
  'cart': p('M2.75 3.5h1.9l1.9 8.5h8.2l1.5-6H5.4') + c(7.5, 15.25, 1.1) + c(13.75, 15.25, 1.1),
  'checkmark': p('M4.5 10.5l3.75 3.75L15.5 6'),
  'chevron.down': p('M4.5 7.5L10 13l5.5-5.5'),
  'chevron.left': p('M12.25 4.5L6.75 10l5.5 5.5'),
  'chevron.left.forwardslash.chevron.right': p('M6.5 6L2.75 10l3.75 4M13.5 6l3.75 4-3.75 4M11.5 4.5l-3 11'),
  'chevron.right': p('M7.75 4.5l5.5 5.5-5.5 5.5'),
  'chevron.up': p('M4.5 12.5L10 7l5.5 5.5'),
  'clock': c(10, 10, 7) + p('M10 5.75V10H6.75'),
  'cloud': p('M6 15.5a3.5 3.5 0 0 1-.6-6.95 4.75 4.75 0 0 1 9.25 1A3 3 0 0 1 14.5 15.5z'),
  'cup.and.saucer': p('M4.5 6h9v3.5a4.5 4.5 0 0 1-9 0zM13.5 7h1.25a1.75 1.75 0 0 1 0 3.5H13.3M3.5 16h11'),
  'doc': doc,
  'doc.text': doc + p('M7.5 10.25h5M7.5 13h5'),
  'ellipsis': dot(5, 10, 1.2) + dot(10, 10, 1.2) + dot(15, 10, 1.2),
  'exclamationmark.shield': p(shield) + p('M10 6.75v4') + dot(10, 13.25),
  'exclamationmark.triangle': p('M10 3.5l7 12.25H3z') + p('M10 8v3.5') + dot(10, 13.6),
  'eye': eye,
  'eye.slash': eye + p('M4 3.5l12 13'),
  'eyedropper': p('M11.5 6.5l2 2M4 16l.5-2.5 6.75-6.75 2 2L6.5 15.5zM12.5 5.5l1.2-1.2a1.6 1.6 0 0 1 2.25 2.25l-1.2 1.2'),
  'film': r(3, 4, 14, 12, 2) + p('M6.5 4v12M13.5 4v12M3 8h3.5M3 12h3.5M13.5 8H17M13.5 12H17'),
  'flag': p('M5 17V3.5M5 4.25c3-1.5 5 1.5 9.5 0v6.5c-4.5 1.5-6.5-1.5-9.5 0'),
  'folder': p('M3 6a1.5 1.5 0 0 1 1.5-1.5h3.2l1.6 1.75h6.2A1.5 1.5 0 0 1 17 7.75v6.75a1.5 1.5 0 0 1-1.5 1.5h-11A1.5 1.5 0 0 1 3 14.5z'),
  'gamecontroller': p('M6.5 6.5h7a4 4 0 0 1 3.9 3.1l.5 2.4a2.2 2.2 0 0 1-3.9 1.8l-.9-1.3H6.9l-.9 1.3a2.2 2.2 0 0 1-3.9-1.8l.5-2.4A4 4 0 0 1 6.5 6.5zM6.25 9.5h2.5M7.5 8.25v2.5') + dot(12.4, 9, 0.75) + dot(14, 10.5, 0.75),
  'gearshape': gear(),
  'globe': c(10, 10, 7) + p('M3 10h14M10 3c2.2 2 3.1 4.3 3.1 7s-.9 5-3.1 7c-2.2-2-3.1-4.3-3.1-7s.9-5 3.1-7z'),
  'graduationcap': p('M10 4.5L2.5 8 10 11.5 17.5 8zM5.5 9.6v3.4c1.3 1.2 2.8 1.75 4.5 1.75s3.2-.55 4.5-1.75V9.6M17.5 8v4'),
  'hand.raised': hand,
  'hand.wave': `<g transform="rotate(-14 10 10)">${hand}</g>` + p('M14.75 2.5a3 3 0 0 1 2.5 2.5M2.75 14.5a3 3 0 0 0 2.25 2.5'),
  'headphones': p('M4 13v-2.5a6 6 0 0 1 12 0V13') + r(3.25, 11.5, 3.25, 5.25, 1.4) + r(13.5, 11.5, 3.25, 5.25, 1.4),
  'heart': p('M10 16.25S3.5 12.5 3.5 7.9A3.4 3.4 0 0 1 10 6.5a3.4 3.4 0 0 1 6.5 1.4c0 4.6-6.5 8.35-6.5 8.35z'),
  'house': p('M3.25 9.25L10 3.5l6.75 5.75M5 8v7.75a.75.75 0 0 0 .75.75h8.5a.75.75 0 0 0 .75-.75V8M8.5 16.5v-4.25h3v4.25'),
  'info.circle': c(10, 10, 7) + p('M10 9.25v4.25') + dot(10, 6.75),
  'key': c(10, 6.25, 3.75) + p('M10 10v7.25M10 13.25h2.25M10 15.75h1.75') + dot(10, 5.1, 1),
  'lightbulb': p('M7.5 13.25c-1.4-1-2.25-2.5-2.25-4.25a4.75 4.75 0 0 1 9.5 0c0 1.75-.85 3.25-2.25 4.25v1.25h-5zM8 16.75h4'),
  'link': p('M8.5 11.5a3 3 0 0 0 4.25 0l2.5-2.5A3 3 0 0 0 11 4.75l-1 1M11.5 8.5a3 3 0 0 0-4.25 0l-2.5 2.5A3 3 0 0 0 9 15.25l1-1'),
  'lock.fill': rf(5, 9, 10, 8, 2) + p('M7 9V6.75a3 3 0 0 1 6 0V9'),
  'lock.trianglebadge.exclamationmark': rf(3, 8.5, 8.5, 7, 1.7) + p('M4.75 8.5V6.5a2.5 2.5 0 0 1 5 0v2') + p('M14.6 10.5l3.4 6h-6.8z') + p('M14.6 12.9v1.3'),
  'macwindow': r(2.75, 4, 14.5, 12, 2.25) + p('M2.75 7.5h14.5') + dot(5, 5.75, 0.55) + dot(6.9, 5.75, 0.55) + dot(8.8, 5.75, 0.55),
  'macwindow.badge.plus': p('M11 14H4.5a2 2 0 0 1-2-2V5.5a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v5M2.5 6.75h13M15.5 12.5v5M13 15h5'),
  'magnifyingglass': glass,
  'mappin': c(10, 6.75, 3.25) + p('M10 10v6.75'),
  'mic.fill': rf(7.5, 2.75, 5, 9, 2.5) + p('M5 9.5a5 5 0 0 0 10 0M10 14.5v2.75'),
  'minus': p('M4.5 10h11'),
  'minus.circle': c(10, 10, 7) + p('M6.75 10h6.5'),
  'moon': p('M16 11.5A6.5 6.5 0 0 1 8.5 4a6.5 6.5 0 1 0 7.5 7.5z'),
  'music.note': p('M8 14.5V4.75l7.5-1.5v9.25') + c(6, 14.5, 2) + c(13.5, 12.5, 2),
  'paintbrush': p('M16.25 3.75c-2.5 1-6 4-7.75 7l2 2c3-1.75 6-5.25 7-7.75a.95.95 0 0 0-1.25-1.25zM8 11.5c-2 0-3 1.25-3 2.75 0 1-.75 1.75-1.5 2 2.5.75 6 .25 6.25-2.75'),
  'paintpalette': p('M10 3a7 7 0 1 0 0 14c1 0 1.5-.6 1.5-1.4 0-.9-.6-1.2-.6-2 0-.8.7-1.35 1.6-1.35H14a3 3 0 0 0 3-3C17 5.8 13.9 3 10 3z') + dot(6.4, 9.6, 0.9) + dot(8.5, 6.5, 0.9) + dot(12, 6.25, 0.9),
  'pencil': p('M4 16l.75-3.25 8.5-8.5a1.6 1.6 0 0 1 2.5 2.5l-8.5 8.5zM12 5.5l2.5 2.5'),
  'person': c(10, 6.75, 3.25) + p('M3.75 16.75c.5-3.25 3-5 6.25-5s5.75 1.75 6.25 5'),
  'person.crop.circle': c(10, 10, 7.25) + `<circle cx="10" cy="8.1" r="2.7" fill="currentColor" stroke="none"/>` + f('M4.9 15.1c1.1-2.05 2.95-3.15 5.1-3.15s4 1.1 5.1 3.15A7.2 7.2 0 0 1 10 17.25a7.2 7.2 0 0 1-5.1-2.15z'),
  'photo': r(3, 4.25, 14, 11.5, 2) + c(7.25, 8.25, 1.25) + p('M3.5 14l3.75-3.5 3 2.75 2.5-2.25 3.75 3.5'),
  'pin': pin,
  'pin.fill': f('M7.25 2.5h5.5a.75.75 0 0 1 0 1.5H12v4l2.25 3.1v1.4h-8.5v-1.4L8 8V4h-.75a.75.75 0 0 1 0-1.5z') + p('M10 12.5v4.75'),
  'pin.slash': pin + p('M4 3.5l12 13.5'),
  'plus': p('M10 4.5v11M4.5 10h11'),
  'plus.square': r(3.5, 3.5, 13, 13, 3) + p('M10 7v6M7 10h6'),
  'plus.square.on.square': r(6.5, 6.5, 10.5, 10.5, 2.5) + p('M11.75 9.25v5M9.25 11.75h5') + p('M13.5 6.5V5a2 2 0 0 0-2-2H5a2 2 0 0 0-2 2v6.5a2 2 0 0 0 2 2h1.5'),
  'printer': p('M6 7V3.5h8V7M6 14H4.5A1.5 1.5 0 0 1 3 12.5v-4A1.5 1.5 0 0 1 4.5 7h11A1.5 1.5 0 0 1 17 8.5v4a1.5 1.5 0 0 1-1.5 1.5H14M6 11.5h8v5H6z'),
  'puzzlepiece.extension': p('M8 4.75a1.75 1.75 0 0 1 3.5 0V6h3a1 1 0 0 1 1 1v2.75h-1.25a1.75 1.75 0 0 0 0 3.5H15.5V16a1 1 0 0 1-1 1h-3v-1.25a1.75 1.75 0 0 0-3.5 0V17H5a1 1 0 0 1-1-1v-3h1.25a1.75 1.75 0 0 0 0-3.5H4V7a1 1 0 0 1 1-1h3z'),
  'questionmark.circle': c(10, 10, 7) + p('M7.9 8.1a2.2 2.2 0 1 1 3.3 1.9c-.75.45-1.2.9-1.2 1.75') + dot(10, 13.9),
  'rectangle.on.rectangle': stackedRect,
  'rectangle.on.rectangle.slash': stackedRect + p('M3.5 16.75l13-13.5'),
  'rectangle.topthird.inset.filled': r(3, 4, 14, 12, 2.5) + rf(5, 6, 10, 3, 1),
  'return': p('M16 5v4.5a2 2 0 0 1-2 2H4.5M8 8l-3.5 3.5L8 15'),
  'shield.lefthalf.filled': p(shield) + f('M10 2.75v14.5c3.45-1.6 5.75-4.4 5.75-8v-4.4z'),
  'sidebar.left': sidebarFrame + p('M7.75 4v12') + `<path d="M4.5 6.9h1.4M4.5 9h1.4M4.5 11.1h1.4" stroke-width="1"/>`,
  'sidebar.right': sidebarFrame + p('M12.25 4v12') + `<path d="M14.1 6.9h1.4M14.1 9h1.4M14.1 11.1h1.4" stroke-width="1"/>`,
  'sidebar.squares.left': sidebarFrame + p('M7.75 4v12') + rf(4.3, 6.2, 1.7, 1.7, 0.45) + rf(4.3, 9.15, 1.7, 1.7, 0.45) + rf(4.3, 12.1, 1.7, 1.7, 0.45),
  'slider.horizontal.3': p('M3 5.5h7.25M13.75 5.5H17M3 10h2.25M8.75 10H17M3 14.5h8.25M14.75 14.5H17') + c(12, 5.5, 1.75) + c(7, 10, 1.75) + c(13, 14.5, 1.75),
  'square.and.arrow.down': p(tray + 'M10 2.75v9.5M7 9.5l3 3 3-3'),
  'square.and.arrow.down.on.square': p('M8 9.5H7.25a1.5 1.5 0 0 0-1.5 1.5v4.5a1.5 1.5 0 0 0 1.5 1.5h8a1.5 1.5 0 0 0 1.5-1.5V11a1.5 1.5 0 0 0-1.5-1.5h-.75M11.25 5.5v7.75M8.75 11l2.5 2.5 2.5-2.5M3.25 12V4.5A1.5 1.5 0 0 1 4.75 3H12'),
  'square.and.arrow.up': p(tray + 'M10 12V2.75M7 5.5l3-3 3 3'),
  'square.grid.2x2': r(3.5, 3.5, 5.5, 5.5, 1.5) + r(11, 3.5, 5.5, 5.5, 1.5) + r(3.5, 11, 5.5, 5.5, 1.5) + r(11, 11, 5.5, 5.5, 1.5),
  'square.on.square': r(7, 7, 10, 10, 2.25) + p(backSquare),
  'square.on.square.dashed': r(7, 7, 10, 10, 2.25) + `<path d="${backSquare}" stroke-dasharray="2 2.2"/>`,
  'square.stack': r(4, 7, 12, 9.5, 2.25) + p('M5.5 4.75h9M7 2.5h6'),
  'star': p(star),
  'star.fill': `<path d="${star}" fill="currentColor"/>`,
  'sun.max': c(10, 10, 3.25) + p('M10 2.5v1.75M10 15.75v1.75M2.5 10h1.75M15.75 10h1.75M4.7 4.7l1.25 1.25M14.05 14.05l1.25 1.25M4.7 15.3l1.25-1.25M14.05 5.95l1.25-1.25'),
  'text.magnifyingglass': glass + `<path d="M6.5 7.6h4.5M6.5 10h2.75" stroke-width="1.15"/>`,
  'textformat': p('M2.75 14.5L6.25 5.5 9.75 14.5M4 11.75h4.5') + c(14.25, 11.9, 2.6) + p('M16.85 9.2v5.3'),
  'trash': trash,
  'trash.slash': trash + p('M3.5 17l13-14'),
  'wifi.exclamationmark': p('M3 8.25a10 10 0 0 1 14 0M5.6 11a6.3 6.3 0 0 1 8.8 0M10 12.25v2') + dot(10, 16.4),
  'wrench.and.screwdriver': p('M11.2 8.8L4.5 15.5a1.4 1.4 0 0 1-2-2l6.7-6.7a3.75 3.75 0 0 1 4.6-4.9l-2.3 2.3.4 1.9 1.9.4 2.3-2.3a3.75 3.75 0 0 1-4.9 4.6zM13 13l3.5 3.5'),
  'xmark': p('M5.25 5.25l9.5 9.5M14.75 5.25l-9.5 9.5'),
  'xmark.circle.fill': `<mask id="mica-xcf"><rect width="20" height="20" fill="#fff" stroke="none"/><path d="M7.4 7.4l5.2 5.2M12.6 7.4l-5.2 5.2" stroke="#000" stroke-width="1.6"/></mask><circle cx="10" cy="10" r="7.6" fill="currentColor" stroke="none" mask="url(#mica-xcf)"/>`,
  // Incognito: a hat with a brim over round glasses, the same outline as IncognitoMark on macOS.
  'mica.incognito': f('M5.2 8.6L6.6 3.6Q7 2.4 8.1 2.7Q10 3.6 11.9 2.7Q13 2.4 13.4 3.6L14.8 8.6Z') + rf(1.6, 8.9, 16.8, 1.9, 0.95)
    + `<ellipse cx="5.3" cy="15" rx="2.7" ry="2.4"/><ellipse cx="14.7" cy="15" rx="2.7" ry="2.4"/>` + p('M8 14.6Q10 13.4 12 14.6'),
};

/// Line weight in pixels per point of symbol size, as SF Symbols weights draw it; turned into grid units below so a
/// larger box does not thicken the line.
const strokes = { light: 0.075, regular: 0.09, medium: 0.1, semibold: 0.115, bold: 0.13 };
/// The drawing box per point of symbol size: an SF Symbol of 20 pt is about 30 px wide, and mica's drawings fill
/// about 17 of their 20 units.
const BOX = 1.62;

export const incognito = 'mica.incognito';

export function hasIcon(name) { return name in glyphs; }

/// Raw SVG markup of a glyph at a point size.
export function svg(name, size, weight = 'medium') {
  const box = Math.round(size * BOX * 2) / 2;
  const body = glyphs[name] || glyphs['questionmark.circle'];
  const line = (strokes[weight] || strokes.medium) * size * 20 / box;
  return `<svg viewBox="0 0 20 20" width="${box}" height="${box}" fill="none" stroke="currentColor" stroke-width="${line.toFixed(3)}" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false">${body}</svg>`;
}

export function icon(name, size, weight = 'medium', props) {
  return h('span', { class: 'glyph' + (props && props.class ? ' ' + props.class : ''), html: svg(name, size, weight), style: props && props.style, key: props && props.key });
}

export const iconNames = Object.keys(glyphs);
