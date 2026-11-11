// Profile icon on its background, a tile with the same concentric rounding as site tiles (ProfileMark on macOS).
// The glyph is white or ink as the profile chooses; the host resolves "auto" by contrast into `lightGlyph`.

import { h } from '../core/dom.js';
import { svg } from '../core/icons.js';

export function ProfileMark(profile, size = 20, extra) {
  return h('span', {
    class: 'profile-mark' + (extra && extra.class ? ' ' + extra.class : ''), 'aria-hidden': 'true', key: extra && extra.key,
    style: { width: size + 'px', height: size + 'px', 'border-radius': (size * 0.3) + 'px', background: profile.background, color: profile.lightGlyph ? '#fff' : '#121213', ...(extra && extra.style) },
    html: svg(profile.icon, size * 0.5, 'semibold'),
  });
}
