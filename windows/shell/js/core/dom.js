// Minimal keyed virtual DOM for the mica shell. No dependencies.
//
// h(tag, props, ...children) builds a vnode; patch(parent, vnodes) reconciles the real DOM with it.
// Besides attributes and events a vnode may carry:
//   key        identity among siblings
//   ref        called with the element after it is created
//   enter      transition played when the element appears (see motion.js), skipped on the first mount
//   exit       transition played before the element is removed; the element leaves the flow at once
//   flip       element takes part in position animation when a render is animated (data-flip)
//   onMount    called once after the element is in the document
//   onUpdate   called after every patch of the element
//   html       inner HTML (icons)

const TEXT = '#text';
const SVG_NS = 'http://www.w3.org/2000/svg';
const special = new Set(['key', 'ref', 'enter', 'exit', 'flip', 'onMount', 'onUpdate', 'html']);
const asProperty = new Set(['value', 'checked', 'disabled', 'selected', 'indeterminate', 'readOnly', 'tabIndex', 'draggable', 'spellcheck']);

export function h(tag, props, ...children) {
  const flat = [];
  flatten(children, flat);
  return { tag, props: props || {}, children: flat, key: props && props.key != null ? props.key : null, el: null };
}

function flatten(list, out) {
  for (const item of list) {
    if (item == null || item === false || item === true) continue;
    if (Array.isArray(item)) flatten(item, out);
    else if (typeof item === 'object') out.push(item);
    else out.push({ tag: TEXT, text: String(item), props: {}, children: [], key: null, el: null });
  }
}

/// Class list from strings, arrays and { name: condition } objects.
export function cx(...parts) {
  let out = '';
  for (const part of parts) {
    if (!part) continue;
    if (typeof part === 'string') out += (out ? ' ' : '') + part;
    else if (Array.isArray(part)) { const inner = cx(...part); if (inner) out += (out ? ' ' : '') + inner; }
    else for (const name in part) if (part[name]) out += (out ? ' ' : '') + name;
  }
  return out;
}

const hooks = { enter: null, exit: null };
/// motion.js installs the transition runners here, so this module stays free of animation code.
export function setTransitionHooks(enter, exit) { hooks.enter = enter; hooks.exit = exit; }

let live = false;
let mounted = [];

/// Reconciles `parent` with `vnodes`. Returns the vnodes to pass as `previous` next time.
export function patch(parent, previous, vnodes) {
  const next = [];
  flatten([vnodes], next);
  patchChildren(parent, previous || [], next, parent.namespaceURI === SVG_NS);
  const run = mounted; mounted = [];
  for (const [vnode, fn] of run) fn(vnode.el);
  live = true;
  return next;
}

function create(vnode, svg) {
  if (vnode.tag === TEXT) { vnode.el = document.createTextNode(vnode.text); return vnode.el; }
  const inSvg = svg || vnode.tag === 'svg';
  const el = inSvg ? document.createElementNS(SVG_NS, vnode.tag) : document.createElement(vnode.tag);
  vnode.el = el;
  setProps(el, {}, vnode.props, inSvg);
  if (vnode.props.html == null) for (const child of vnode.children) el.appendChild(create(child, inSvg && vnode.tag !== 'foreignObject'));
  if (vnode.props.ref) vnode.props.ref(el);
  if (vnode.props.onMount) mounted.push([vnode, vnode.props.onMount]);
  if (vnode.props.onUpdate) mounted.push([vnode, vnode.props.onUpdate]);
  return el;
}

function setProps(el, old, props, svg) {
  for (const name in old) if (!(name in props) && !special.has(name)) setProp(el, name, old[name], null, svg);
  for (const name in props) {
    if (special.has(name)) continue;
    const value = props[name], before = old[name];
    if (value !== before || (name === 'value' && el.value !== value)) setProp(el, name, before, value, svg);
  }
  if (props.html !== old.html) el.innerHTML = props.html == null ? '' : props.html;
  if (props.flip) { if (!old.flip) el.setAttribute('data-flip', ''); } else if (old.flip) el.removeAttribute('data-flip');
}

function setProp(el, name, before, value, svg) {
  if (name === 'class') { if (svg) el.setAttribute('class', value || ''); else el.className = value || ''; return; }
  if (name === 'style') { setStyle(el, before, value); return; }
  if (name[0] === 'o' && name[1] === 'n') { el[name.toLowerCase()] = value || null; return; }
  if (!svg && asProperty.has(name)) {
    if (name === 'value') { const text = value == null ? '' : String(value); if (el.value !== text) el.value = text; }
    else el[name] = value == null ? (name === 'tabIndex' ? -1 : false) : value;
    return;
  }
  if (value == null || value === false) el.removeAttribute(name);
  else el.setAttribute(name, value === true ? '' : value);
}

function setStyle(el, before, value) {
  if (typeof value === 'string' || typeof before === 'string' || value == null) { el.style.cssText = typeof value === 'string' ? value : ''; before = null; if (typeof value === 'string' || value == null) return; }
  if (before) for (const name in before) if (!(name in value)) el.style.removeProperty(name);
  for (const name in value) {
    const next = value[name];
    if (before && before[name] === next) continue;
    if (next == null || next === false) el.style.removeProperty(name);
    else el.style.setProperty(name, typeof next === 'number' && !name.startsWith('--') && !unitless.has(name) ? next + 'px' : String(next));
  }
}
const unitless = new Set(['opacity', 'flex', 'flex-grow', 'flex-shrink', 'z-index', 'font-weight', 'line-height', 'order', 'scale', 'aspect-ratio']);

function same(a, b) { return a.tag === b.tag && a.key === b.key; }

function patchNode(old, vnode, svg) {
  const el = vnode.el = old.el;
  if (vnode.tag === TEXT) { if (old.text !== vnode.text) el.nodeValue = vnode.text; return; }
  const inSvg = svg || vnode.tag === 'svg';
  setProps(el, old.props, vnode.props, inSvg);
  if (vnode.props.html == null) patchChildren(el, old.props.html == null ? old.children : [], vnode.children, inSvg && vnode.tag !== 'foreignObject');
  if (vnode.props.onUpdate) mounted.push([vnode, vnode.props.onUpdate]);
}

function patchChildren(parent, oldList, newList, svg) {
  // Match by key, then by position among the unkeyed of the same tag.
  const keyed = new Map();
  const loose = [];
  for (const old of oldList) { if (old.key != null) keyed.set(old.tag + '\u0000' + old.key, old); else loose.push(old); }
  let looseIndex = 0;
  const used = new Set();
  const fresh = [];
  for (const vnode of newList) {
    let old = null;
    if (vnode.key != null) old = keyed.get(vnode.tag + '\u0000' + vnode.key) || null;
    else {
      while (looseIndex < loose.length && used.has(loose[looseIndex])) looseIndex++;
      const candidate = loose[looseIndex];
      if (candidate && same(candidate, vnode)) { old = candidate; looseIndex++; }
      else {
        // The shape changed here: take the next unkeyed node of the same tag, if any.
        for (let i = looseIndex; i < loose.length; i++) if (!used.has(loose[i]) && same(loose[i], vnode)) { old = loose[i]; break; }
      }
    }
    if (old && !used.has(old)) { used.add(old); patchNode(old, vnode, svg); }
    else { create(vnode, svg); fresh.push(vnode); }
  }
  for (const old of oldList) if (!used.has(old)) remove(parent, old);
  // Put the elements in order, moving only what is out of place; leaving elements are skipped over.
  let next = null;
  for (let i = newList.length - 1; i >= 0; i--) {
    const el = newList[i].el;
    let after = el.parentNode === parent ? el.nextSibling : undefined;
    while (after && after.__leaving) after = after.nextSibling;
    if (after !== next) parent.insertBefore(el, next);
    next = el;
  }
  if (live && hooks.enter) for (const vnode of fresh) if (vnode.props.enter) hooks.enter(vnode.el, vnode.props.enter);
}

function remove(parent, old) {
  const el = old.el;
  if (!el || el.parentNode !== parent) return;
  if (live && hooks.exit && old.props && old.props.exit && el.nodeType === 1 && !el.__leaving) {
    el.__leaving = true;
    hooks.exit(el, old.props.exit, () => { if (el.parentNode) el.parentNode.removeChild(el); });
  } else if (!el.__leaving) parent.removeChild(el);
}
