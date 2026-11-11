// State and the render loop of the shell.
//
// `state` is the last snapshot from the host; `ui` is what only the shell knows (open menus, typed text, drags).
// Any change schedules one render. A render may be animated: elements marked `flip` then travel from their old
// place with a spring, as views do inside SwiftUI's withAnimation. Without an animation the change is immediate,
// so resizing the window or a tab's progress never makes anything drift.

import { patch } from './dom.js';
import { measure, play, setReduced } from './motion.js';
import { setTextStyle } from './text.js';

export let state = null;
export const ui = {
  menu: null,            // open shell menu: { entries, x, y, origin, id }
  submenu: null,
  popover: null,         // form popover: { id, anchor: DOMRect, render }
  tooltip: null,
  sidebarDrag: null,     // sidebar width while its edge is dragged
  drag: null,            // what is being dragged: { kind, id, x, y, over }
  command: { text: '', highlighted: 0, items: [], seq: 0 },
  start: { text: '', highlighted: 0, items: [], seq: 0, focused: false, seed: Math.floor(Math.random() * 1000) },
  find: { query: '', found: true },
  settings: {},
  library: {},
  entered: false,        // the window entrance has started
};

let root = null;
let view = null;
let tree = null;
let scheduled = false;
let pendingSpring = null;
const afterRender = [];
const stateWatchers = [];

export function mount(element, render) { root = element; view = render; }

/// Called with (previous, next) before the first render of a new snapshot; returns a spring name to animate it.
export function watchState(fn) { stateWatchers.push(fn); }

export function setState(next) {
  const previous = state;
  // Large parts come only when they changed; otherwise the last copy stays.
  if (previous) {
    if (next.library === undefined) next.library = previous.library;
    if (next.settings === undefined) next.settings = previous.settings;
  }
  if (!next.library) next.library = {};
  state = next;
  setTextStyle(next.text);
  setReduced(next.system.reducedMotion);
  if (previous) for (const fn of stateWatchers) { const spring = fn(previous, next); if (spring) animate(spring); }
  invalidate();
}

/// Marks the next render as animated with the named spring ("snappy", "panel", "press").
export function animate(spring) {
  if (!pendingSpring || spring === 'panel') pendingSpring = spring;
  invalidate();
}

/// Changes shell-only state and redraws. `spring` animates the change.
export function update(change, spring) {
  if (change) change(ui);
  if (spring) animate(spring); else invalidate();
}

export function invalidate() {
  if (scheduled) return;
  scheduled = true;
  queueMicrotask(flush);
}

export function onRendered(fn) { afterRender.push(fn); }

function flush() {
  scheduled = false;
  if (!state || !root) return;
  const spring = pendingSpring; pendingSpring = null;
  const first = spring ? measure(root) : null;
  if (spring) {
    // Size transitions (sidebar width, panel width, tab widths) run only for animated renders.
    document.documentElement.setAttribute('data-anim', spring);
    clearTimeout(flush.timer);
    flush.timer = setTimeout(() => document.documentElement.removeAttribute('data-anim'), 620);
  }
  tree = patch(root, tree, view());
  if (spring) play(root, first, spring);
  const run = afterRender.splice(0);
  for (const fn of run) fn();
  for (const fn of layoutWatchers) fn();
}

const layoutWatchers = [];
/// Called after every render, for code that reports geometry to the host.
export function watchLayout(fn) { layoutWatchers.push(fn); }

/// Renders now instead of at the end of the task; used before measuring.
export function flushNow() { if (scheduled) flush(); }
