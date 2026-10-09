// Tiny DOM builder and an event bus the desktop pieces talk through.
export function h(tag, attrs, ...children) {
  const el = document.createElement(tag);
  for (const [key, value] of Object.entries(attrs || {})) {
    if (value == null || value === false) continue;
    if (key === 'class') el.className = value;
    else if (key === 'text') el.textContent = value;
    else if (key === 'style' && typeof value === 'object') {
      for (const [prop, v] of Object.entries(value)) {
        if (prop.startsWith('--')) el.style.setProperty(prop, v);
        else el.style[prop] = v;
      }
    }
    else if (key === 'dataset') Object.assign(el.dataset, value);
    else if (key.startsWith('on') && typeof value === 'function') el.addEventListener(key.slice(2), value);
    else if (value === true) el.setAttribute(key, '');
    else el.setAttribute(key, value);
  }
  append(el, children);
  return el;
}

export function append(el, children) {
  for (const child of children.flat(Infinity)) {
    if (child == null || child === false) continue;
    el.append(child instanceof Node ? child : document.createTextNode(String(child)));
  }
  return el;
}

export const clear = (el) => { el.replaceChildren(); return el; };

export function createBus() {
  const handlers = new Map();
  return {
    on(name, fn) { (handlers.get(name) || handlers.set(name, new Set()).get(name)).add(fn); return () => handlers.get(name).delete(fn); },
    emit(name, ...args) { for (const fn of handlers.get(name) || []) fn(...args); }
  };
}

export const reducedMotion = () => matchMedia('(prefers-reduced-motion: reduce)').matches;
export const coarsePointer = () => matchMedia('(hover: none), (pointer: coarse)').matches;
export const isMac = /Mac|iPhone|iPad/.test(navigator.platform || navigator.userAgent);

export function clamp(value, min, max) { return Math.min(max, Math.max(min, value)); }

export function formatClock(date, lang) {
  const locale = lang === 'ru' ? 'ru-RU' : 'en-US';
  const day = date.toLocaleDateString(locale, { weekday: 'short', day: 'numeric', month: 'short' });
  const time = date.toLocaleTimeString(locale, { hour: '2-digit', minute: '2-digit', hour12: false });
  return `${day}  ${time}`;
}

export async function copyText(text) {
  try {
    await navigator.clipboard.writeText(text);
    return true;
  } catch {
    const area = h('textarea', { style: { position: 'fixed', opacity: '0' } });
    area.value = text;
    document.body.append(area);
    area.select();
    let ok = false;
    try { ok = document.execCommand('copy'); } catch {}
    area.remove();
    return ok;
  }
}
