(() => {
  if ((window.top !== window && !globalThis.__savisulDemo)) return;

  try { globalThis.SV?.destroy?.(); } catch {}
  document.dispatchEvent(new CustomEvent('savisul:replace'));
  document.querySelectorAll('savisul-notch').forEach((node) => node.remove());

  const SV = {
    tools: {},
    cleanups: [],
    settings: null,
    host: location.hostname.replace(/^www\./, ''),
    // What the notch shows as the site name; the welcome demo stands in a sample site for its extension URL.
    site: globalThis.__savisulDemo?.site || location.hostname.replace(/^www\./, ''),
    alive: true
  };
  // A second injection into the same tab replaces globalThis.SV, so every content file binds
  // `const SV = globalThis.SV` up front; async work of the replaced copy then sees its own `alive` false.
  globalThis.SV = SV;

  // MARK: Lifecycle

  SV.listen = (target, type, handler, options) => {
    target.addEventListener(type, handler, options);
    SV.cleanups.push(() => target.removeEventListener(type, handler, options));
  };

  SV.destroy = () => {
    if (!SV.alive) return;
    SV.alive = false;
    for (const tool of Object.values(SV.tools)) {
      try { tool.stop?.(); } catch {}
    }
    for (const cleanup of SV.cleanups.splice(0)) {
      try { cleanup(); } catch {}
    }
    SV.root?.host?.remove();
    if (globalThis.__savisulKeys === SV.routeKey) globalThis.__savisulKeys = undefined;
  };

  const replaced = () => SV.destroy();
  document.addEventListener('savisul:replace', replaced, { once: true });
  SV.cleanups.push(() => document.removeEventListener('savisul:replace', replaced));

  SV.contextOK = () => {
    try { return !!chrome.runtime?.id; } catch { return false; }
  };

  SV.send = async (type, data = {}) => {
    if (!SV.contextOK()) {
      SV.destroy();
      throw new Error('context');
    }
    const reply = await chrome.runtime.sendMessage({ type, ...data });
    if (reply?.error) throw new Error(reply.error);
    return reply;
  };

  // MARK: Events

  const listeners = new Map();
  SV.on = (name, handler) => {
    if (!listeners.has(name)) listeners.set(name, new Set());
    listeners.get(name).add(handler);
    return () => listeners.get(name)?.delete(handler);
  };
  SV.emit = (name, data) => {
    for (const handler of listeners.get(name) || []) {
      try { handler(data); } catch (error) { console.error('SAVISUL', name, error); }
    }
  };

  // MARK: DOM

  const SVG = 'http://www.w3.org/2000/svg';

  function append(parent, children) {
    for (const child of children.flat(Infinity)) {
      if (child == null || child === false) continue;
      parent.append(child instanceof Node ? child : document.createTextNode(String(child)));
    }
    return parent;
  }

  function h(tag, props, ...children) {
    const el = document.createElement(tag);
    if (props) {
      for (const [key, value] of Object.entries(props)) {
        if (value == null || value === false) continue;
        if (key === 'class') el.className = value;
        else if (key === 'text') el.textContent = value;
        else if (key === 'style') {
          for (const [name, v] of Object.entries(value)) {
            if (v != null) el.style.setProperty(name.startsWith('--') ? name : name.replace(/[A-Z]/g, (c) => '-' + c.toLowerCase()), String(v));
          }
        } else if (key === 'dataset') Object.assign(el.dataset, value);
        else if (key.startsWith('on') && typeof value === 'function') el.addEventListener(key.slice(2).toLowerCase(), value);
        else if (key === 'value' || key === 'checked' || key === 'disabled' || key === 'selected') el[key] = value;
        else el.setAttribute(key, value === true ? '' : String(value));
      }
    }
    return append(el, children);
  }

  SV.h = h;
  SV.append = append;
  SV.clear = (el) => { while (el.firstChild) el.firstChild.remove(); return el; };

  const ICONS = {
    moon: 'M20 14.5A8 8 0 0 1 9.5 4a8 8 0 1 0 10.5 10.5Z',
    sun: 'c12 12 4|M12 2.5v2M12 19.5v2M4.6 4.6 6 6M18 18l1.4 1.4M2.5 12h2M19.5 12h2M4.6 19.4 6 18M18 6l1.4-1.4',
    book: 'M12 7.5C10.3 5.9 7.7 5.2 4 5.3v12.9c3.7-.1 6.3.6 8 2.3 1.7-1.7 4.3-2.4 8-2.3V5.3c-3.7-.1-6.3.6-8 2.2Z|M12 7.5v13',
    pipette: 'M14 6.5 17.5 10|M15.3 5.2l2.3-2.3a2.2 2.2 0 0 1 3.1 3.1l-2.3 2.3|M14 7l3 3-8.6 8.6a2 2 0 0 1-1.4.6H5v-2c0-.5.2-1 .6-1.4Z',
    ruler: 'M3.5 16.5 16.5 3.5l4 4-13 13Z|M7.5 12.5l2 2M10.5 9.5l2 2M13.5 6.5l2 2',
    note: 'M5 4.5h14v9.5l-5.5 5.5H5Z|M13.5 19.5V14H19|M8.5 8.5h7M8.5 11.5h4',
    camera: 'M4 8.5h3.2l1.6-2.5h6.4l1.6 2.5H20v10.5H4Z|c12 13.3 3.4',
    eyeOff: 'M3 3l18 18|M10.6 5.1C11 5 11.5 5 12 5c5 0 8.5 4.5 9.5 7-.6 1.4-1.4 2.7-2.6 3.8|M6.6 6.6C4.6 8 3.2 10 2.5 12c1 2.5 4.5 7 9.5 7 1.8 0 3.4-.5 4.8-1.3|M9.9 9.9a3 3 0 0 0 4.2 4.2',
    type: 'M5 7V5h14v2|M12 5v14|M9 19h6',
    link: 'M10 14a4.5 4.5 0 0 0 6.4 0l3-3a4.5 4.5 0 0 0-6.4-6.4l-1 1|M14 10a4.5 4.5 0 0 0-6.4 0l-3 3a4.5 4.5 0 0 0 6.4 6.4l1-1',
    play: 'r3 5 18 14 3.5|M10.2 9.3v5.4l4.6-2.7Z',
    image: 'r3 4 18 16 3.5|c9 10 1.8|M21 15.5 16 11l-9 9',
    unlock: 'r4.5 11 15 10 2.5|M8 11V7.5a4 4 0 0 1 7.7-1.6',
    pencil: 'M4 20h4L19 9a2.8 2.8 0 0 0-4-4L4 16Z|M13.5 6.5l4 4',
    outline: 'M4 8V5.5A1.5 1.5 0 0 1 5.5 4H8M16 4h2.5A1.5 1.5 0 0 1 20 5.5V8M20 16v2.5a1.5 1.5 0 0 1-1.5 1.5H16M8 20H5.5A1.5 1.5 0 0 1 4 18.5V16|M10.5 4h3M10.5 20h3M4 10.5v3M20 10.5v3',
    sliders: 'M4 7h9M17 7h3M4 17h3M11 17h9|c15 7 2|c9 17 2',
    x: 'M6.5 6.5l11 11M17.5 6.5l-11 11',
    back: 'M14.5 5.5 8 12l6.5 6.5',
    check: 'M5 12.5l4.5 4.5L19 7.5',
    copy: 'r8 8 12 12 2.5|M16 8V6.5A2.5 2.5 0 0 0 13.5 4h-7A2.5 2.5 0 0 0 4 6.5v7A2.5 2.5 0 0 0 6.5 16H8',
    download: 'M12 4v11|M7 10.5l5 5 5-5|M5 20h14',
    trash: 'M4.5 7h15|M10 11v6M14 11v6|M6.5 7l.8 12.1A1.5 1.5 0 0 0 8.8 20.5h6.4a1.5 1.5 0 0 0 1.5-1.4L17.5 7|M9 7V4.5h6V7',
    pin: 'M9 4h6l-.8 5.5L17 13H7l2.8-3.5Z|M12 13v7',
    external: 'M14 4h6v6|M20 4l-9 9|M18 14v4.5a1.5 1.5 0 0 1-1.5 1.5h-11A1.5 1.5 0 0 1 4 18.5v-11A1.5 1.5 0 0 1 5.5 6H10',
    laptop: 'r5 5 14 10 1.8|M2.5 19h19',
    coffee: 'M5 9h11v4.5a5.5 5.5 0 0 1-11 0Z|M16 10.5h1.5a2.5 2.5 0 0 1 0 5H16|M9 3.5V6M12.5 3.5V6',
    displayOff: 'r3 4 18 12 2|M9 20h6M12 16v4|M14.6 7.6a2.8 2.8 0 1 0 1.8 4.8 2.4 2.4 0 0 1-1.8-4.8Z',
    speaker: 'M4 9.5h3.5L12 5.5v13l-4.5-4H4Z|M15.5 9.2a4 4 0 0 1 0 5.6M18.2 6.8a7.5 7.5 0 0 1 0 10.4',
    speakerOff: 'M4 9.5h3.5L12 5.5v13l-4.5-4H4Z|M16 9.5l5 5M21 9.5l-5 5',
    battery: 'r2.5 7.5 17 9 2.5|M21.5 10.5v3',
    bolt: 'M13 3 5.5 13.5H12L11 21l7.5-10.5H12Z',
    cpu: 'r6 6 12 12 2|r9.5 9.5 5 5 .8|M9 3v3M15 3v3M9 18v3M15 18v3M3 9h3M3 15h3M18 9h3M18 15h3',
    folder: 'M3.5 7A1.5 1.5 0 0 1 5 5.5h4l2 2h8A1.5 1.5 0 0 1 20.5 9v8.5A1.5 1.5 0 0 1 19 19H5a1.5 1.5 0 0 1-1.5-1.5Z',
    qr: 'r4 4 6 6 1|r14 4 6 6 1|r4 14 6 6 1|M14 14h2.5v2.5H14ZM17.5 17.5H20V20h-2.5ZM14 20h1M20 14h-1',
    globe: 'c12 12 8.5|M3.5 12h17|M12 3.5c2.4 2.6 3.5 5.4 3.5 8.5s-1.1 5.9-3.5 8.5c-2.4-2.6-3.5-5.4-3.5-8.5s1.1-5.9 3.5-8.5Z',
    page: 'M6 3.5h8l4 4v13H6Z|M14 3.5v4h4|M9 12h6M9 15.5h6',
    crop: 'M7 3v14h14|M3 7h14v14',
    screen: 'r3 4.5 18 12.5 2|M8.5 20.5h7',
    minus: 'M5.5 12h13',
    plus: 'M12 5.5v13M5.5 12h13',
    pip: 'r3 5 18 14 2.5|r12 11.5 6.5 5 1',
    loop: 'M17 3.5l3 3-3 3|M4 12v-.5A5 5 0 0 1 9 6.5h11|M7 20.5l-3-3 3-3|M20 12v.5a5 5 0 0 1-5 5H4',
    keyboard: 'r2.5 6 19 12 2.5|M6.5 10h.01M10 10h.01M13.5 10h.01M17 10h.01M7 14h10',
    search: 'c11 11 6.5|M16 16l4 4',
    sparkle: 'M12 3.5l1.9 5.1 5.1 1.9-5.1 1.9L12 17.5l-1.9-5.1L5 10.5l5.1-1.9Z',
    width: 'M4 12h16|M7.5 8.5 4 12l3.5 3.5|M16.5 8.5 20 12l-3.5 3.5',
    lines: 'M5 6.5h14M5 10.5h14M5 14.5h9M5 18.5h11',
    restore: 'M4.5 12a7.5 7.5 0 1 0 2.2-5.3|M4.5 4.5v4h4',
    pause: 'M9 6v12|M15 6v12',
    stop: 'r6.5 6.5 11 11 2.5',
    wave: 'M4 12h1.5|M8 8v8|M11.5 5v14|M15 9v6|M18.5 11v2'
  };

  SV.addIcons = (more) => Object.assign(ICONS, more);

  SV.icon = (name, size = 18) => {
    const svg = document.createElementNS(SVG, 'svg');
    const attrs = {
      width: size, height: size, viewBox: '0 0 24 24', fill: 'none', stroke: 'currentColor',
      'stroke-width': 1.7, 'stroke-linecap': 'round', 'stroke-linejoin': 'round', 'aria-hidden': 'true', class: 'icon'
    };
    for (const [key, value] of Object.entries(attrs)) svg.setAttribute(key, value);
    for (const part of (ICONS[name] || ICONS.sparkle).split('|')) {
      let node;
      if (part[0] === 'c') {
        const [cx, cy, r] = part.slice(1).split(' ');
        node = document.createElementNS(SVG, 'circle');
        node.setAttribute('cx', cx);
        node.setAttribute('cy', cy);
        node.setAttribute('r', r);
      } else if (part[0] === 'r') {
        const [x, y, width, height, rx] = part.slice(1).split(' ');
        node = document.createElementNS(SVG, 'rect');
        Object.entries({ x, y, width, height, rx: rx || 0 }).forEach(([k, v]) => node.setAttribute(k, v));
      } else {
        node = document.createElementNS(SVG, 'path');
        node.setAttribute('d', part);
      }
      svg.append(node);
    }
    return svg;
  };

  // The four-block SAVISUL mark, same proportions as the app.
  SV.mark = (width = 20) => {
    const svg = document.createElementNS(SVG, 'svg');
    svg.setAttribute('viewBox', '0 0 20 12');
    svg.setAttribute('width', width);
    svg.setAttribute('height', (width * 12) / 20);
    svg.setAttribute('fill', 'currentColor');
    svg.setAttribute('aria-hidden', 'true');
    svg.setAttribute('class', 'mark');
    for (const [x, y, w, hh, r] of [[0, 0, 5.6, 12, 0.78], [7.1, 0, 2.4, 12, 0.34], [11, 0, 9, 5.25, 0.74], [11, 6.75, 9, 5.25, 0.74]]) {
      const rect = document.createElementNS(SVG, 'rect');
      Object.entries({ x, y, width: w, height: hh, rx: r }).forEach(([k, v]) => rect.setAttribute(k, v));
      svg.append(rect);
    }
    return svg;
  };

  // MARK: Page helpers

  SV.pageStyle = (id, css) => {
    let el = document.getElementById(id);
    if (css == null) {
      el?.remove();
      return null;
    }
    if (!el) {
      el = document.createElement('style');
      el.id = id;
      (document.head || document.documentElement).append(el);
    }
    if (el.textContent !== css) el.textContent = css;
    return el;
  };

  SV.isOurs = (node) => {
    for (let el = node; el; el = el.parentNode || el.host) {
      if (el.localName === 'savisul-notch') return true;
    }
    return false;
  };

  SV.elementAt = (x, y) => {
    const el = document.elementFromPoint(x, y);
    if (!el || SV.isOurs(el)) return null;
    return el;
  };

  SV.copy = async (text) => {
    try {
      await navigator.clipboard.writeText(text);
      return true;
    } catch {
      const area = document.createElement('textarea');
      area.value = text;
      area.setAttribute('readonly', '');
      area.style.setProperty('position', 'fixed', 'important');
      area.style.setProperty('opacity', '0', 'important');
      area.style.setProperty('top', '0', 'important');
      document.documentElement.append(area);
      area.select();
      let ok = false;
      try { ok = document.execCommand('copy'); } catch {}
      area.remove();
      return ok;
    }
  };

  SV.clamp = (value, min, max) => Math.min(max, Math.max(min, value));
  SV.sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
  SV.frame = () => new Promise((resolve) => requestAnimationFrame(() => resolve()));
  SV.frames = async (count = 2) => { for (let i = 0; i < count; i++) await SV.frame(); };

  SV.debounce = (fn, ms) => {
    let timer;
    return (...args) => {
      clearTimeout(timer);
      timer = setTimeout(() => fn(...args), ms);
    };
  };

  SV.stamp = (date = new Date()) => {
    const p = (n) => String(n).padStart(2, '0');
    return `${date.getFullYear()}-${p(date.getMonth() + 1)}-${p(date.getDate())} at ${p(date.getHours())}.${p(date.getMinutes())}.${p(date.getSeconds())}`;
  };

  SV.safeName = (text) => (text || '').replace(/[\\/:*?"<>|\u0000-\u001f]+/g, ' ').replace(/\s+/g, ' ').trim().slice(0, 80);

  // MARK: Color

  let scratch;
  SV.parseColor = (value) => {
    if (!value) return null;
    const rgb = value.match(/rgba?\(([^)]+)\)/i);
    if (rgb) {
      const parts = rgb[1].split(/[\s,/]+/).filter(Boolean);
      const num = (p, scale) => (p.endsWith('%') ? (parseFloat(p) / 100) * scale : parseFloat(p));
      return { r: num(parts[0], 255), g: num(parts[1], 255), b: num(parts[2], 255), a: parts[3] != null ? num(parts[3], 1) : 1 };
    }
    const srgb = value.match(/color\(srgb\s+([^)]+)\)/i);
    if (srgb) {
      const p = srgb[1].split(/[\s/]+/).filter(Boolean).map(parseFloat);
      return { r: p[0] * 255, g: p[1] * 255, b: p[2] * 255, a: p[3] ?? 1 };
    }
    const hex = value.match(/^#([0-9a-f]{3,8})$/i);
    if (hex) return SV.hexToRgb(value);
    scratch ||= document.createElement('canvas').getContext('2d');
    scratch.fillStyle = '#000';
    scratch.fillStyle = value;
    const normalized = scratch.fillStyle;
    return normalized === value ? null : SV.parseColor(normalized);
  };

  SV.hexToRgb = (hex) => {
    let h6 = hex.replace('#', '');
    if (h6.length === 3 || h6.length === 4) h6 = h6.split('').map((c) => c + c).join('');
    const n = parseInt(h6.slice(0, 6), 16);
    const a = h6.length === 8 ? parseInt(h6.slice(6, 8), 16) / 255 : 1;
    return { r: (n >> 16) & 255, g: (n >> 8) & 255, b: n & 255, a };
  };

  SV.toHex = ({ r, g, b }) => '#' + [r, g, b].map((v) => Math.round(SV.clamp(v, 0, 255)).toString(16).padStart(2, '0')).join('');

  SV.toHsl = ({ r, g, b }) => {
    r /= 255; g /= 255; b /= 255;
    const max = Math.max(r, g, b);
    const min = Math.min(r, g, b);
    const l = (max + min) / 2;
    let hue = 0;
    let s = 0;
    if (max !== min) {
      const d = max - min;
      s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
      if (max === r) hue = (g - b) / d + (g < b ? 6 : 0);
      else if (max === g) hue = (b - r) / d + 2;
      else hue = (r - g) / d + 4;
      hue *= 60;
    }
    return { h: Math.round(hue), s: Math.round(s * 100), l: Math.round(l * 100) };
  };

  SV.toOklch = ({ r, g, b }) => {
    const lin = (c) => {
      c /= 255;
      return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
    };
    const [R, G, B] = [lin(r), lin(g), lin(b)];
    const l = Math.cbrt(0.4122214708 * R + 0.5363325363 * G + 0.0514459929 * B);
    const m = Math.cbrt(0.2119034982 * R + 0.6806995451 * G + 0.1073969566 * B);
    const s = Math.cbrt(0.0883024619 * R + 0.2817188376 * G + 0.6299787005 * B);
    const L = 0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s;
    const A = 1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s;
    const Bb = 0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s;
    const C = Math.sqrt(A * A + Bb * Bb);
    let H = (Math.atan2(Bb, A) * 180) / Math.PI;
    if (H < 0) H += 360;
    return { l: L, c: C, h: C < 0.0005 ? 0 : H };
  };

  SV.formatColor = (rgb, format) => {
    if (format === 'rgb') return `rgb(${Math.round(rgb.r)} ${Math.round(rgb.g)} ${Math.round(rgb.b)})`;
    if (format === 'hsl') {
      const { h: hue, s, l } = SV.toHsl(rgb);
      return `hsl(${hue} ${s}% ${l}%)`;
    }
    if (format === 'oklch') {
      const { l, c, h: hue } = SV.toOklch(rgb);
      return `oklch(${(l * 100).toFixed(1)}% ${c.toFixed(3)} ${hue.toFixed(1)})`;
    }
    return SV.toHex(rgb).toUpperCase();
  };

  SV.luminance = ({ r, g, b }) => {
    const f = (c) => {
      c /= 255;
      return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
    };
    return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b);
  };

  SV.contrast = (a, b) => {
    const [hi, lo] = [SV.luminance(a), SV.luminance(b)].sort((x, y) => y - x);
    return (hi + 0.05) / (lo + 0.05);
  };

  // The colour a reader actually sees behind an element: first opaque background up the tree.
  SV.backgroundOf = (el) => {
    for (let node = el; node && node.nodeType === 1; node = node.parentElement) {
      const color = SV.parseColor(getComputedStyle(node).backgroundColor);
      if (color && color.a > 0.5) return color;
    }
    return { r: 255, g: 255, b: 255, a: 1 };
  };

  // MARK: Keys

  const keyHandlers = new Set();
  SV.onKey = (handler) => {
    keyHandlers.add(handler);
    return () => keyHandlers.delete(handler);
  };
  SV.routeKey = (event) => {
    for (const handler of [...keyHandlers].reverse()) {
      if (handler(event) === true) {
        event.preventDefault();
        event.stopImmediatePropagation();
        return true;
      }
    }
    return false;
  };
  globalThis.__savisulKeys = SV.routeKey;
  SV.listen(window, 'keydown', (event) => {
    if (event.composedPath().some((node) => node.localName === 'savisul-notch')) return;
    SV.routeKey(event);
  }, true);
})();
