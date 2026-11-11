// Motion of the mica shell: the same springs as macOS (shared/tokens.json), as CSS `linear()` easings.
//
// SwiftUI's spring(response:dampingFraction:) is a damped harmonic oscillator with angular frequency
// 2π / response and damping ratio dampingFraction. Its analytic step response is sampled here into a `linear()`
// easing, so a CSS transition or a Web Animation follows the very curve SwiftUI draws.
// Actions happen at once; animations follow and never block input. With "Animation effects" off in Windows
// (the Reduce Motion counterpart) movement is skipped and only opacity and colour change.

import { motion as tokens } from '../gen/tokens.g.js';
import { setTransitionHooks } from './dom.js';

export function springValue(response, damping, t) {
  const omega = 2 * Math.PI / response;
  if (damping >= 1) return 1 - Math.exp(-omega * t) * (1 + omega * t);
  const decay = damping * omega, wd = omega * Math.sqrt(1 - damping * damping);
  return 1 - Math.exp(-decay * t) * (Math.cos(wd * t) + decay / wd * Math.sin(wd * t));
}

/// Time after which the spring stays within 0.1% of its target.
export function settle(response, damping) {
  const omega = 2 * Math.PI / response;
  return Math.log(1000) / (Math.min(damping, 1) * omega);
}

export function spring(response, damping) {
  const duration = settle(response, damping);
  const steps = Math.max(24, Math.round(duration * 120));
  const points = [];
  for (let i = 0; i <= steps; i++) points.push(i === steps ? '1' : springValue(response, damping, duration * i / steps).toFixed(4));
  return { response, damping, duration, ms: Math.round(duration * 1000), easing: 'linear(' + points.join(',') + ')' };
}

export const springs = {
  press: spring(tokens.press.response, tokens.press.damping),
  snappy: spring(tokens.snappy.response, tokens.snappy.damping),
  panel: spring(tokens.panel.response, tokens.panel.damping),
  /// Icon of a start page site tile on hover.
  bouncy: spring(tokens.bouncy.response, tokens.bouncy.damping),
  /// Shell menus (MicaMenu) and form popovers (StickyPopover) on macOS.
  menu: spring(0.2, 0.9),
  popover: spring(0.24, 0.88),
  /// One glyph of the assembling wordmark (AssembleRenderer.spring).
  letter: spring(tokens.wordmark.letterDuration, 0.78),
};
export const hover = { ms: Math.round(tokens.hover.duration * 1000), easing: 'ease-out' };

let reduced = false;
export function isReduced() { return reduced; }
export function setReduced(value) {
  reduced = !!value;
  document.documentElement.toggleAttribute('data-reduced-motion', reduced);
}

/// Publishes the springs as custom properties: --spring-snappy, --spring-snappy-ms and so on.
export function installMotion() {
  const style = document.documentElement.style;
  for (const name in springs) {
    style.setProperty('--spring-' + name, springs[name].easing);
    style.setProperty('--spring-' + name + '-ms', springs[name].ms + 'ms');
  }
  // Start tile glow (motion.aura) as unitless numbers: --aura-blur, --aura-icon-scale and so on.
  for (const key in tokens.aura) style.setProperty('--aura-' + key.replace(/[A-Z]/g, c => '-' + c.toLowerCase()), tokens.aura[key]);
  setTransitionHooks(enter, exit);
}

const presets = {
  // Individual transform properties (scale, translate) are used, so a transition composes with whatever
  // `transform` places the element (tabs in the strip are positioned by translateX).
  // Motion.pop: scale 0.96 with opacity.
  pop: { from: { opacity: 0, scale: tokens.popScale }, spring: 'snappy' },
  fade: { from: { opacity: 0 }, fade: true },
  // Motion.slide(edge): moves in from the edge by its own size, with opacity.
  'slide-top': { from: { opacity: 0, translate: '0 -100%' }, spring: 'snappy' },
  'slide-bottom': { from: { opacity: 0, translate: '0 100%' }, spring: 'panel' },
  'slide-leading': { from: { opacity: 0, translate: '-100% 0' }, spring: 'panel' },
  'slide-trailing': { from: { opacity: 0, translate: '100% 0' }, spring: 'panel' },
  // ModalCard: scale 0.97 with opacity.
  modal: { from: { opacity: 0, scale: 0.97 }, spring: 'snappy' },
  // Command bar: scale 0.97 from the top edge and 6 px down.
  command: { from: { opacity: 0, translate: '0 -6px', scale: 0.97 }, spring: 'snappy' },
  // Toolbar palette: scale 0.98 from the top and 8 px down.
  palette: { from: { opacity: 0, translate: '0 -8px', scale: 0.98 }, spring: 'panel' },
};

function resolve(spec) {
  if (typeof spec === 'string') return { ...presets[spec], name: spec };
  return { ...presets[spec.name], ...spec };
}

function reducedFrames(frames) { return { opacity: frames.opacity == null ? 1 : frames.opacity }; }

export function enter(el, spec) {
  const preset = resolve(spec);
  if (preset.run) { preset.run(el); return; }
  const from = reduced ? reducedFrames(preset.from) : preset.from;
  const curve = preset.fade || reduced ? hover : springs[preset.spring || 'snappy'];
  const options = { duration: curve.ms, easing: curve.easing, fill: 'backwards', delay: preset.delay || 0 };
  if (from.opacity != null && !preset.fade && !reduced) {
    // Opacity follows the same spring as the movement, as SwiftUI's combined transitions do.
    el.animate([{ opacity: from.opacity }, { opacity: 1 }], options);
    const rest = { ...from }; delete rest.opacity;
    if (Object.keys(rest).length) el.animate([rest, neutral(rest)], options);
  } else el.animate([from, neutral(from)], options);
}

function neutral(frames) {
  const out = {};
  for (const name in frames) out[name] = name === 'opacity' || name === 'scale' ? 1 : name === 'translate' ? '0 0' : 'none';
  return out;
}

export function exit(el, spec, done) {
  const preset = resolve(spec);
  // The element leaves the layout at once and fades where it stood, as a removed SwiftUI view does.
  if (preset.float !== false) float(el);
  el.style.pointerEvents = 'none';
  el.setAttribute('aria-hidden', 'true');
  const to = reduced ? reducedFrames(preset.out || preset.from) : (preset.out || preset.from);
  const curve = preset.fade || preset.outFade || reduced ? hover : springs[preset.spring || 'snappy'];
  const ms = preset.outMs || curve.ms;
  const animation = el.animate([neutral(to), to], { duration: ms, easing: preset.outMs ? 'ease-out' : curve.easing, fill: 'forwards' });
  let finished = false;
  const finish = () => { if (finished) return; finished = true; done(); };
  animation.onfinish = finish; animation.oncancel = finish;
  setTimeout(finish, ms + 80);
}

function float(el) {
  const parent = el.offsetParent;
  if (!parent || getComputedStyle(el).position === 'absolute' || getComputedStyle(el).position === 'fixed') return;
  const left = el.offsetLeft, top = el.offsetTop, width = el.offsetWidth, height = el.offsetHeight;
  el.style.position = 'absolute'; el.style.left = left + 'px'; el.style.top = top + 'px';
  el.style.width = width + 'px'; el.style.height = height + 'px'; el.style.margin = '0';
  el.style.boxSizing = 'border-box';
}

// Position animation (FLIP) for one render: measure before the DOM changes, then let every element that moved
// travel from where it was with a spring. This is what SwiftUI does for views whose frame changes inside an animation.
export function measure(root) {
  if (reduced) return null;
  const first = new Map();
  for (const el of root.querySelectorAll('[data-flip]')) if (!el.__leaving) first.set(el, el.getBoundingClientRect());
  return first;
}

export function play(root, first, name) {
  if (!first || reduced) return;
  const curve = springs[name] || springs.snappy;
  const deltas = new Map();
  const moved = [];
  for (const el of root.querySelectorAll('[data-flip]')) {
    if (el.__leaving) continue;
    const before = first.get(el);
    if (!before) continue;
    const now = el.getBoundingClientRect();
    let dx = before.left - now.left, dy = before.top - now.top;
    deltas.set(el, [dx, dy]);
    // A child of an element that also moved travels with it; only its own share is animated.
    const outer = el.parentElement && el.parentElement.closest('[data-flip]');
    if (outer && deltas.has(outer)) { const [ox, oy] = deltas.get(outer); dx -= ox; dy -= oy; }
    if (Math.abs(dx) < 0.5 && Math.abs(dy) < 0.5) continue;
    moved.push([el, dx, dy]);
  }
  for (const [el, dx, dy] of moved) {
    el.animate([{ translate: `${dx}px ${dy}px` }, { translate: '0px 0px' }], { duration: curve.ms, easing: curve.easing, composite: 'add' });
  }
}

/// A spring driven by hand, for values that follow the pointer and must keep their velocity (drags).
export function animateSpring(name, apply, done) {
  const curve = springs[name] || springs.snappy;
  if (reduced) { apply(1); done && done(); return () => {}; }
  const start = performance.now();
  let frame = 0, stopped = false;
  const tick = now => {
    if (stopped) return;
    const t = (now - start) / 1000;
    if (t >= curve.duration) { apply(1); done && done(); return; }
    apply(springValue(curve.response, curve.damping, t));
    frame = requestAnimationFrame(tick);
  };
  frame = requestAnimationFrame(tick);
  return () => { stopped = true; cancelAnimationFrame(frame); };
}
