// Window layout (BrowserRoot on macOS): top bar across the window, tabs at the top or in a sidebar on either side,
// the content card with an optional library panel beside it, and window-level overlays.
//
// The web page itself is not drawn here: the host keeps a WebView2 per tab and places it over the hole this
// shell leaves in the content card (`.page-hole`). Its rectangle is reported after every render, so the page
// follows the card through every animation frame of a layout change.

import { h, cx } from '../core/dom.js';
import { geometry, motion } from '../gen/tokens.g.js';
import { springs, isReduced } from '../core/motion.js';
import { T } from '../core/text.js';
import { state, ui, update, send, selected, layout as currentLayout, horizontal, coversPage } from './model.js';
import { TopBar } from './topbar.js';
import { Sidebar, TabStrip } from './tabs.js';
import { StartScreen } from './start.js';
import { CommandBar } from './command.js';
import { CustomizePanel } from './customize.js';
import { FindBar, ErrorPage } from './page.js';
import { LibraryPanel } from './library.js';
import { Overlays } from './overlays.js';
import { MenuLayer, PopoverLayer } from '../ui/menu.js';

const BAR = geometry.chrome.bar, GUTTER = geometry.radius.gutter, RAIL = geometry.chrome.rail;

function resizeHandle(sign) {
  return h('div', {
    class: 'resize-handle', key: 'resize', 'aria-hidden': 'true',
    onPointerDown: event => {
      if (event.button !== 0) return;
      const el = event.currentTarget, start = event.clientX, base = state.prefs.sidebarWidth;
      el.setPointerCapture(event.pointerId);
      const move = e => update(u => { u.sidebarDrag = Math.min(380, Math.max(200, base + (e.clientX - start) * sign)); });
      const up = () => {
        el.removeEventListener('pointermove', move); el.removeEventListener('pointerup', up);
        if (ui.sidebarDrag != null) send('prefs.set', { path: 'sidebarWidth', value: Math.round(ui.sidebarDrag) });
        update(u => { u.sidebarDrag = null; });
      };
      el.addEventListener('pointermove', move); el.addEventListener('pointerup', up);
    },
  });
}

function ContentCard(tab) {
  const start = !!tab && tab.start && !tab.error;
  const glass = state.appearance.glass;
  return h('div', { class: cx('card', { see: start && glass, 'on-start': start }), key: 'card', flip: true, onMount: cardEntrance },
    tab && start ? StartScreen(tab) : null,
    tab && !start ? h('div', { class: 'page-hole', key: 'hole-' + tab.id }) : null,
    tab && tab.error ? ErrorPage(tab) : null,
    state.overlay.find && tab && !start ? FindBar(tab) : null,
    state.overlay.customizingToolbar ? h('div', { class: 'card-dim', key: 'dim', enter: 'fade', exit: 'fade' }) : null);
}

// On the first appearance the start page card rises a little out of the shell. A site's card is not moved or scaled.
function cardEntrance(el) {
  const tab = selected();
  if (ui.entered) return;
  ui.entered = true;
  if (!tab || !tab.start) return;
  if (isReduced()) { el.animate([{ opacity: 0 }, { opacity: 1 }], { duration: motion.entrance.reducedFade * 1000, easing: 'ease-out', fill: 'backwards' }); return; }
  const options = { duration: springs.panel.ms, easing: springs.panel.easing, delay: motion.entrance.stagger * 1000, fill: 'backwards' };
  el.animate([{ opacity: 0 }, { opacity: 1 }], options);
  el.animate([{ translate: `0 ${motion.entrance.rise}px`, scale: motion.entrance.cardScale }, { translate: '0 0', scale: 1 }], options);
}

export function Root() {
  const width = window.innerWidth;
  const layout = currentLayout();
  const edge = horizontal(layout) ? null : layout;
  const collapsed = state.prefs.sidebarCollapsed && !!edge;
  const sidebarWidth = collapsed ? RAIL : (ui.sidebarDrag != null ? ui.sidebarDrag : state.prefs.sidebarWidth);
  const tab = selected();
  const caption = state.window.fullScreen ? 0 : state.system.captionInset;
  const panel = state.panel;
  const panelWidth = Math.min(340, width * 0.4);
  const sidebar = edge ? h('div', {
    class: cx('sidebar-host', edge, { collapsed, dragging: ui.sidebarDrag != null }), key: 'sidebar-' + edge, style: { width: sidebarWidth + 'px' },
    enter: edge === 'left' ? 'slide-leading' : 'slide-trailing', exit: { name: edge === 'left' ? 'slide-leading' : 'slide-trailing', float: true },
  }, Sidebar(edge, collapsed), collapsed ? null : resizeHandle(edge === 'left' ? 1 : -1)) : null;

  return h('div', { class: cx('root', 'layout-' + layout, { private: state.window.isPrivate, covered: coversPage() }) },
    h('div', { class: 'shell-fill', key: 'fill' }),
    layout === 'tabsAbove'
      ? [
          h('div', { class: 'band', key: 'band', style: { 'padding-left': GUTTER + 'px', 'padding-right': caption + GUTTER + 'px', height: (state.window.fullScreen ? BAR : state.system.captionHeight || BAR) + 'px' } },
            TabStrip(true, width - caption - 2 * GUTTER)),
          h('div', { class: 'bar-under', key: 'bar-under' }, TopBar(layout, width, false)),
        ]
      : [
          h('div', { class: 'bar-top', key: 'bar-top' }, TopBar(layout, width, true)),
          layout === 'top' ? h('div', { class: 'strip-host', key: 'strip-host', enter: 'fade', exit: 'fade' }, TabStrip(false, width - 2 * GUTTER)) : null,
        ],
    h('div', { class: 'body', key: 'body' },
      edge === 'left' ? sidebar : null,
      h('div', { class: 'workspace', key: 'workspace', style: { 'padding-left': edge === 'left' ? '0' : GUTTER + 'px', 'padding-right': edge === 'right' ? '0' : GUTTER + 'px' } },
        ContentCard(tab),
        panel ? h('div', { class: 'library-host', key: 'library-' + panel, style: { width: panelWidth + 'px' }, enter: 'slide-trailing', exit: { name: 'slide-trailing', float: true } }, LibraryPanel(panel)) : null,
        state.overlay.customizingToolbar ? h('div', { class: 'customize-host', key: 'customize-host' }, CustomizePanel()) : null),
      edge === 'right' ? sidebar : null),
    state.overlay.commandBar ? CommandBar() : null,
    Overlays(),
    PopoverLayer(),
    MenuLayer(),
    ui.tooltip ? h('div', { class: 'tooltip', key: 'tooltip', style: { left: ui.tooltip.x + 'px', top: ui.tooltip.y + 'px' } }, ui.tooltip.text) : null);
}

export { T };
