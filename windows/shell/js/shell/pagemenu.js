// The context menu of a web page as a mica menu (PageMenu.swift on macOS). The host sends WebView2's items for the
// click, already worded and filtered; a chosen row goes back as its WebView2 command id or as mica's own search row.

import { openMenuAt, divider } from '../ui/menu.js';
import { send } from '../core/host.js';

export function openPageMenu({ id, items, x, y }) {
  const hole = document.querySelector('.page-hole');
  const rect = hole ? hole.getBoundingClientRect() : { left: 0, top: 0 };
  const entries = list => list.map(item => item.divider ? divider : {
    title: item.title,
    enabled: item.enabled !== false,
    checked: item.checked || undefined,
    submenu: item.submenu ? entries(item.submenu) : undefined,
    action: () => send('pageMenu.choose', { id, command: item.command ?? null, search: item.search ?? null }),
  });
  openMenuAt(entries(items), rect.left + x, rect.top + y, () => send('pageMenu.choose', { id, command: null }));
}
