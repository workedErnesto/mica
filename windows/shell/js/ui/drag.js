// Dragging inside the shell: tabs onto tabs, toolbar buttons into zones, start page sites onto each other.
// Pointer events with capture instead of HTML drag and drop: the preview follows the pointer on the compositor,
// drop targets are found by hit testing, and nothing depends on OLE drag support of the host.
//
// A source calls dragSource(kind, id) for its pointerdown handler. A target carries data-drop="<kind>" and
// data-drop-id; while a drag of that kind is over it, it gets the attribute data-drop-over. The drop handler
// registered with onDrop(kind, fn) receives (id, targetId, targetElement).

import { isReduced, springs } from '../core/motion.js';

const handlers = {};
export function onDrop(kind, fn) { handlers[kind] = fn; }

let active = null;
export function dragging() { return active; }

export function dragSource(kind, id, options) {
  return event => {
    if (event.button !== 0 || active) return;
    const source = event.currentTarget;
    const startX = event.clientX, startY = event.clientY;
    let ghost = null, over = null, moved = false;
    const targetAt = (x, y) => {
      for (const el of document.elementsFromPoint(x, y)) {
        const target = el.closest && el.closest(`[data-drop~="${kind}"]`);
        if (target && !(target.dataset.dropId === String(id) && !target.dataset.dropSelf)) return target;
      }
      return null;
    };
    const setOver = next => {
      if (over === next) return;
      if (over) over.removeAttribute('data-drop-over');
      over = next;
      if (over) over.setAttribute('data-drop-over', '');
    };
    const move = e => {
      const dx = e.clientX - startX, dy = e.clientY - startY;
      if (!moved) {
        if (Math.hypot(dx, dy) < 4) return;
        moved = true;
        active = { kind, id };
        document.documentElement.setAttribute('data-dragging', kind);
        const rect = source.getBoundingClientRect();
        ghost = (options && options.preview ? options.preview(source) : source.cloneNode(true));
        ghost.classList.add('drag-ghost');
        ghost.removeAttribute('data-flip');
        ghost.style.transform = 'none'; ghost.style.translate = '0 0';
        Object.assign(ghost.style, { position: 'fixed', left: rect.left + 'px', top: rect.top + 'px', width: rect.width + 'px', height: rect.height + 'px', margin: '0', pointerEvents: 'none', zIndex: '950' });
        if (options && options.preview) { ghost.style.left = (e.clientX - 17) + 'px'; ghost.style.top = (e.clientY - 17) + 'px'; ghost.style.width = ''; ghost.style.height = ''; }
        document.body.appendChild(ghost);
        source.setAttribute('data-drag-source', '');
        if (!isReduced()) ghost.animate([{ transform: 'scale(1)', opacity: 1 }, { transform: 'scale(1.03)', opacity: 0.92 }], { duration: springs.press.ms, easing: springs.press.easing, fill: 'forwards', composite: 'add' });
        else ghost.style.opacity = '0.92';
        ghost.__origin = { x: startX, y: startY, moved: !!(options && options.preview) };
      }
      ghost.style.translate = ghost.__origin.moved ? `${e.clientX - startX - (ghost.__skip || 0)}px ${e.clientY - startY}px` : `${dx}px ${dy}px`;
      setOver(targetAt(e.clientX, e.clientY));
    };
    const finish = (e, cancelled) => {
      window.removeEventListener('pointermove', move, true);
      window.removeEventListener('pointerup', up, true);
      window.removeEventListener('pointercancel', cancel, true);
      window.removeEventListener('keydown', key, true);
      if (!moved) return;
      const target = cancelled ? null : over;
      setOver(null);
      source.removeAttribute('data-drag-source');
      document.documentElement.removeAttribute('data-dragging');
      active = null;
      const gone = ghost;
      const fade = gone.animate([{ opacity: 0.92 }, { opacity: 0 }], { duration: 120, easing: 'ease-out', fill: 'forwards' });
      fade.onfinish = () => gone.remove();
      setTimeout(() => gone.remove(), 200);
      // The click that ends a drag must not also activate the element under the pointer.
      const swallow = ev => { ev.stopPropagation(); ev.preventDefault(); };
      window.addEventListener('click', swallow, { capture: true, once: true });
      setTimeout(() => window.removeEventListener('click', swallow, true), 0);
      if (target && handlers[kind]) handlers[kind](id, target.dataset.dropId || null, target);
    };
    const up = e => finish(e, false);
    const cancel = e => finish(e, true);
    const key = e => { if (e.key === 'Escape') { finish(e, true); e.stopPropagation(); } };
    window.addEventListener('pointermove', move, true);
    window.addEventListener('pointerup', up, true);
    window.addEventListener('pointercancel', cancel, true);
    window.addEventListener('keydown', key, true);
  };
}
