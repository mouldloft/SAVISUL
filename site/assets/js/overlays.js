// Keyboard surfaces: command bar (⌥Space), clipboard history (⌃⌥V) and the window switcher (⌥Tab).
import { h, clear } from './dom.js';
import { icon, mark } from './icons.js';
import { t, lang, onLang } from './i18n.js';
import { CONFIG } from './config.js';

// MARK: Math

export function evaluate(input) {
  const src = input.replace(/,/g, '.').replace(/×/g, '*').replace(/÷/g, '/').replace(/\s+/g, '');
  if (!/^[\d.+\-*/^()%]+$/.test(src) || !/\d/.test(src) || !/[+\-*/^%]/.test(src.replace(/^-/, ''))) return null;
  let i = 0;
  const peek = () => src[i];
  const number = () => {
    const start = i;
    while (/[\d.]/.test(src[i] || '')) i++;
    const value = Number(src.slice(start, i));
    if (Number.isNaN(value) || start === i) throw new Error('nan');
    if (peek() === '%') { i++; return value / 100; }
    return value;
  };
  const factor = () => {
    if (peek() === '-') { i++; return -factor(); }
    if (peek() === '(') { i++; const v = expr(); if (src[i++] !== ')') throw new Error('paren'); return v; }
    return number();
  };
  const power = () => { let v = factor(); while (peek() === '^') { i++; v = v ** factor(); } return v; };
  const term = () => {
    let v = power();
    while (peek() === '*' || peek() === '/') { const op = src[i++]; const r = power(); v = op === '*' ? v * r : v / r; }
    return v;
  };
  const expr = () => {
    let v = term();
    while (peek() === '+' || peek() === '-') { const op = src[i++]; const r = term(); v = op === '+' ? v + r : v - r; }
    return v;
  };
  try {
    const value = expr();
    if (i !== src.length || !Number.isFinite(value)) return null;
    return Math.round(value * 1e10) / 1e10;
  } catch { return null; }
}

const UNITS = {
  length: { km: 1000, m: 1, cm: 0.01, mm: 0.001, mi: 1609.344, ft: 0.3048, in: 0.0254, yd: 0.9144 },
  mass: { kg: 1, g: 0.001, lb: 0.45359237, oz: 0.028349523 },
  temp: { c: 'c', f: 'f', k: 'k' }
};
const ALIASES = {
  km: 'km', 'км': 'km', kilometers: 'km', kilometres: 'km', m: 'm', 'м': 'm', meters: 'm', metres: 'm', cm: 'cm', 'см': 'cm', mm: 'mm', 'мм': 'mm',
  mi: 'mi', mile: 'mi', miles: 'mi', 'миля': 'mi', 'мили': 'mi', 'миль': 'mi', ft: 'ft', feet: 'ft', foot: 'ft', 'фут': 'ft', 'футов': 'ft', 'фута': 'ft',
  in: 'in', inch: 'in', inches: 'in', 'дюйм': 'in', 'дюймов': 'in', 'дюйма': 'in', yd: 'yd', yards: 'yd',
  kg: 'kg', 'кг': 'kg', g: 'g', 'г': 'g', lb: 'lb', lbs: 'lb', pounds: 'lb', 'фунт': 'lb', 'фунтов': 'lb', 'фунта': 'lb', oz: 'oz', ounces: 'oz', 'унций': 'oz',
  c: 'c', '°c': 'c', celsius: 'c', 'с': 'c', '°с': 'c', f: 'f', '°f': 'f', fahrenheit: 'f', k: 'k', kelvin: 'k'
};
// Sample rates, labeled as such in the UI; the app itself downloads daily rates.
const RATES = { usd: 1, eur: 0.92, gbp: 0.79, rub: 96, uah: 41.2, jpy: 149 };
const CURRENCY = {
  '$': 'usd', usd: 'usd', 'доллар': 'usd', 'долларов': 'usd', 'доллара': 'usd', '€': 'eur', eur: 'eur', euro: 'eur', euros: 'eur', 'евро': 'eur',
  '£': 'gbp', gbp: 'gbp', '₽': 'rub', rub: 'rub', 'руб': 'rub', 'рублей': 'rub', 'рубля': 'rub', 'рубли': 'rub', 'рублях': 'rub', uah: 'uah', '₴': 'uah', 'гривен': 'uah', 'гривнах': 'uah', jpy: 'jpy', '¥': 'jpy'
};
const SYMBOL = { usd: '$', eur: '€', gbp: '£', rub: '₽', uah: '₴', jpy: '¥' };

export function convert(query) {
  const m = query.trim().toLowerCase().match(/^(-?[\d.,]+)\s*([^\s\d]+)\s+(?:in|to|into|в|во|->|→)\s+([^\s\d]+)$/);
  if (!m) return null;
  const amount = Number(m[1].replace(',', '.'));
  if (!Number.isFinite(amount)) return null;
  const locale = lang === 'ru' ? 'ru-RU' : 'en-US';
  const from = CURRENCY[m[2]], to = CURRENCY[m[3]];
  if (from && to) {
    const value = (amount / RATES[from]) * RATES[to];
    return { text: `${value.toLocaleString(locale, { maximumFractionDigits: 2 })} ${SYMBOL[to]}`, detail: `${amount.toLocaleString(locale)} ${SYMBOL[from]} · ${t('cmdRates')}` };
  }
  const a = ALIASES[m[2]], b = ALIASES[m[3]];
  if (!a || !b) return null;
  const kind = Object.keys(UNITS).find((k) => a in UNITS[k] && b in UNITS[k]);
  if (!kind) return null;
  let value;
  if (kind === 'temp') {
    const toC = { c: (v) => v, f: (v) => (v - 32) * 5 / 9, k: (v) => v - 273.15 }[a](amount);
    value = { c: toC, f: toC * 9 / 5 + 32, k: toC + 273.15 }[b];
  } else value = (amount * UNITS[kind][a]) / UNITS[kind][b];
  const label = { c: '°C', f: '°F', k: 'K' };
  return { text: `${value.toLocaleString(locale, { maximumFractionDigits: 2 })} ${label[b] || b}`, detail: `${amount.toLocaleString(locale)} ${label[a] || a}` };
}

const RU = 'йцукенгшщзхъфывапролджэячсмитьбю';
const EN = 'qwertyuiop[]asdfghjkl;\'zxcvbnm,.';
export const fixLayout = (text) => [...text.toLowerCase()].map((c) => { const i = RU.indexOf(c); return i >= 0 ? EN[i] : c; }).join('');

// MARK: Clipboard store

function seedHistory() {
  return [
    { kind: 'text', text: 'git commit -m "island: snap tabs to the notch"', time: Date.now() - 4 * 60000 },
    { kind: 'color', text: '#DBC7A3', time: Date.now() - 9 * 60000 },
    { kind: 'link', text: 'https://lrclib.net/docs', time: Date.now() - 26 * 60000 },
    { kind: 'file', text: `SAVISUL-${CONFIG.version}.dmg`, time: Date.now() - 40 * 60000 },
    { kind: 'image', text: 'Screenshot 18.04.png', time: Date.now() - 95 * 60000 },
    { kind: 'text', text: 'Standup moved to 10:30, same link.', time: Date.now() - 180 * 60000 }
  ];
}

function itemIcon(item) {
  if (item.kind === 'color') return h('span', { class: 'clip-swatch', style: { background: item.text } });
  const glyph = { text: 'type', link: 'link', file: 'page', image: 'image' }[item.kind] || 'type';
  return h('span', { class: 'clip-icon' }, icon(glyph, 15));
}

function ago(time) {
  const m = Math.max(1, Math.round((Date.now() - time) / 60000));
  if (m < 60) return t('dlMin', m);
  return t('dlHour', Math.round(m / 60));
}

// MARK: Overlays

export function createOverlays(bus, desktop) {
  const history = seedHistory();
  const layer = h('div', { class: 'overlay-layer' });
  document.body.append(layer);
  let open = null;

  const addClip = (item) => {
    const text = String(item.text || '').trim().slice(0, 500);
    if (!text) return;
    const existing = history.findIndex((entry) => entry.text === text);
    if (existing >= 0) history.splice(existing, 1);
    history.unshift({ kind: item.kind || (/^https?:\/\//.test(text) ? 'link' : /^#[0-9a-f]{6}$/i.test(text) ? 'color' : 'text'), text, time: Date.now(), fromPage: item.fromPage });
    if (history.length > 1000) history.length = 1000;
  };
  bus.on('copy', (item) => {
    addClip(item);
    bus.emit('peek', 'copied', item.text.length > 34 ? `${item.text.slice(0, 32)}…` : item.text);
  });
  document.addEventListener('copy', () => {
    if (layer.contains(document.activeElement)) return;
    const text = String(getSelection() || '').trim();
    if (text) addClip({ text, fromPage: true });
  });

  function close() {
    if (!open) return;
    open.el.classList.remove('show');
    open.el.classList.add('closing');
    const el = open.el;
    setTimeout(() => el.remove(), 180);
    open.restore?.focus?.();
    open = null;
  }

  function show(kind, el, restore) {
    close();
    layer.append(el);
    requestAnimationFrame(() => el.classList.add('show'));
    open = { kind, el, restore };
  }

  // Command bar

  function commandBar() {
    const input = h('input', { class: 'cmd-input', type: 'text', placeholder: t('cmdPlaceholder'), 'aria-label': t('menuSearch'), autocomplete: 'off', spellcheck: 'false' });
    const results = h('div', { class: 'cmd-results', role: 'listbox' });
    let items = [];
    let index = 0;

    const build = () => {
      const raw = input.value.trim();
      const q = raw.toLowerCase();
      const sections = [];
      const math = evaluate(raw);
      if (math != null) sections.push([t('cmdCalc'), [{ glyph: 'plus', title: math.toLocaleString(lang === 'ru' ? 'ru-RU' : 'en-US', { maximumFractionDigits: 10 }), detail: `${raw} =`, run: () => bus.emit('copy', { kind: 'text', text: String(math) }) }]]);
      const conv = convert(raw);
      if (conv) sections.push([t('cmdConvert'), [{ glyph: 'width', title: conv.text, detail: conv.detail, run: () => bus.emit('copy', { kind: 'text', text: conv.text }) }]]);

      const search = (term) => {
        const out = [];
        const apps = t('apps').filter((name) => !term || name.toLowerCase().includes(term)).slice(0, term ? 5 : 4);
        if (apps.length) out.push([t('cmdApps'), apps.map((name) => ({ glyph: 'window', title: name, run: () => bus.emit('peek', 'opening', name) }))]);
        const wins = desktop.listWindows().filter((w) => !term || w.title.toLowerCase().includes(term));
        if (wins.length) out.push([t('cmdWindows'), wins.map((w) => ({ glyph: w.glyph, title: w.title, detail: w.open ? '' : '—', run: () => desktop.openWindow(w.id) }))]);
        const panel = [['energy', 'bolt', 'pEnergy'], ['sound', 'speaker', 'pSound'], ['system', 'cpu', 'pSystem'], ['work', 'code', 'pWork'], ['tools', 'grid', 'pTools']]
          .filter(([, , key]) => !term || t(key).toLowerCase().includes(term));
        if (term && panel.length) out.push([t('cmdMenu'), panel.map(([id, glyph, key]) => ({ glyph, title: `SAVISUL › ${t(key)}`, run: () => desktop.openPanel(id) }))]);
        const clips = history.filter((c) => term && c.text.toLowerCase().includes(term)).slice(0, 3);
        if (clips.length) out.push([t('cmdClipboard'), clips.map((c) => ({ glyph: 'clipboard', title: c.text, detail: ago(c.time), run: () => bus.emit('peek', 'pasted', c.text.slice(0, 32)) }))]);
        return out;
      };
      let found = search(q);
      let fixed = '';
      if (q && /[а-яё]/i.test(q) && !found.length && math == null && !conv) {
        fixed = fixLayout(q);
        found = search(fixed);
      }
      if (fixed && found.length) sections.push([t('cmdLayout', fixed), []]);
      sections.push(...found);
      if (q && math == null && !conv) sections.push(['', [{ glyph: 'search', title: t('cmdWeb', raw), run: () => bus.emit('peek', 'opening', 'Google') }]]);

      clear(results);
      items = [];
      for (const [label, list] of sections) {
        if (label) results.append(h('div', { class: 'cmd-section', text: label }));
        for (const item of list) {
          const row = h('button', { class: 'cmd-row', type: 'button', role: 'option', onclick: () => choose(items.indexOf(row)) },
            h('span', { class: 'cmd-icon' }, icon(item.glyph, 16)),
            h('span', { class: 'cmd-title', text: item.title }),
            item.detail ? h('span', { class: 'cmd-detail', text: item.detail }) : null);
          row.run = item.run;
          items.push(row);
          results.append(row);
        }
      }
      if (!items.length) results.append(h('div', { class: 'cmd-empty', text: t('cmdEmpty') }));
      index = 0;
      mark();
    };
    const mark = () => items.forEach((row, i) => { row.classList.toggle('on', i === index); row.setAttribute('aria-selected', String(i === index)); if (i === index) row.scrollIntoView({ block: 'nearest' }); });
    const choose = (i) => { const row = items[i]; if (!row) return; close(); row.run(); };

    input.addEventListener('input', build);
    input.addEventListener('keydown', (event) => {
      if (event.key === 'ArrowDown') { event.preventDefault(); index = Math.min(items.length - 1, index + 1); mark(); }
      else if (event.key === 'ArrowUp') { event.preventDefault(); index = Math.max(0, index - 1); mark(); }
      else if (event.key === 'Enter') { event.preventDefault(); choose(index); }
      else if (event.key === 'Escape') { event.preventDefault(); close(); }
    });
    const el = h('div', { class: 'overlay cmd', role: 'dialog', 'aria-label': t('menuSearch') },
      h('div', { class: 'cmd-field' }, icon('search', 20), input, h('kbd', { text: '⌥Space' })),
      results,
      h('div', { class: 'overlay-hint', text: t('cmdHint') }));
    build();
    return { el, focus: () => input.focus() };
  }

  // Clipboard history

  function clipboard() {
    const input = h('input', { class: 'clip-input', type: 'search', placeholder: t('clipSearch'), 'aria-label': t('clipSearch') });
    const list = h('div', { class: 'clip-list', role: 'listbox' });
    const preview = h('div', { class: 'clip-preview' });
    let shown = [];
    let index = 0;
    const kinds = t('clipKinds');
    const render = () => {
      const q = input.value.trim().toLowerCase();
      shown = history.filter((c) => !q || c.text.toLowerCase().includes(q)).slice(0, 40);
      clear(list);
      shown.forEach((item, i) => list.append(h('button', {
        class: `clip-row${i === index ? ' on' : ''}`, type: 'button', role: 'option', 'aria-selected': String(i === index),
        onclick: () => { index = i; paste(false); }, onpointermove: () => { if (index !== i) { index = i; mark(); } }
      }, itemIcon(item), h('span', { class: 'clip-text', text: item.text }), h('span', { class: 'clip-when', text: item.fromPage ? t('clipFromPage') : ago(item.time) }))));
      if (!shown.length) list.append(h('div', { class: 'cmd-empty', text: t('clipEmpty') }));
      index = Math.min(index, Math.max(0, shown.length - 1));
      mark();
    };
    const mark = () => {
      [...list.children].forEach((row, i) => { row.classList.toggle('on', i === index); row.setAttribute?.('aria-selected', String(i === index)); if (i === index) row.scrollIntoView?.({ block: 'nearest' }); });
      const item = shown[index];
      clear(preview);
      if (!item) return;
      preview.append(h('div', { class: 'clip-kind' }, itemIcon(item), kinds[item.kind] || kinds.text),
        item.kind === 'color' ? h('div', { class: 'clip-big-swatch', style: { background: item.text } }) : null,
        h('div', { class: `clip-full ${item.kind}`, text: item.text }));
    };
    const paste = (plain) => {
      const item = shown[index];
      if (!item) return;
      close();
      bus.emit('peek', plain ? 'plain' : 'pasted', item.text.length > 34 ? `${item.text.slice(0, 32)}…` : item.text);
    };
    input.addEventListener('input', () => { index = 0; render(); });
    input.addEventListener('keydown', (event) => {
      if (event.key === 'ArrowDown') { event.preventDefault(); index = Math.min(shown.length - 1, index + 1); mark(); }
      else if (event.key === 'ArrowUp') { event.preventDefault(); index = Math.max(0, index - 1); mark(); }
      else if (event.key === 'Enter') { event.preventDefault(); paste(event.shiftKey); }
      else if (event.key === 'Escape') { event.preventDefault(); close(); }
    });
    const el = h('div', { class: 'overlay clip', role: 'dialog', 'aria-label': t('clipTitle') },
      h('div', { class: 'clip-head' }, icon('clipboard', 17), h('b', { text: t('clipTitle') }), input, h('kbd', { text: '⌃⌥V' })),
      h('div', { class: 'clip-body' }, list, preview),
      h('div', { class: 'overlay-hint', text: t('clipHint') }));
    render();
    return { el, focus: () => input.focus() };
  }

  // Window switcher

  let switcher = null;
  function openSwitcher(step = 1) {
    const wins = desktop.listWindows().filter((w) => w.open);
    if (!wins.length) return;
    if (!switcher) {
      const row = h('div', { class: 'switch-row' });
      const el = h('div', { class: 'overlay switcher', role: 'dialog', 'aria-label': 'Switcher' }, row, h('div', { class: 'overlay-hint', text: t('switcherHint') }));
      switcher = { el, row, index: 0, wins };
      show('switcher', el, document.activeElement);
    }
    switcher.wins = wins;
    switcher.index = (switcher.index + step + wins.length) % wins.length;
    clear(switcher.row);
    wins.forEach((w, i) => switcher.row.append(h('button', {
      class: `switch-tile${i === switcher.index ? ' on' : ''}`, type: 'button', onclick: () => { switcher.index = i; commitSwitcher(); }
    }, h('span', { class: `switch-thumb ${w.id}` }, w.id === 'panel' ? mark(30) : icon(w.glyph, 30)), h('span', { class: 'switch-title', text: w.title }))));
  }
  function commitSwitcher(action) {
    if (!switcher) return;
    const w = switcher.wins[switcher.index];
    switcher = null;
    close();
    if (!w) return;
    if (action === 'close') desktop.closeWindow(w.id);
    else if (action === 'minimize') desktop.minimizeWindow(w.id);
    else desktop.openWindow(w.id);
  }

  // MARK: Keys

  const typing = (target) => target.closest?.('input, textarea, [contenteditable="true"]') && !layer.contains(target);

  document.addEventListener('keydown', (event) => {
    const code = event.code;
    if (switcher) {
      if (event.key === 'Tab') { event.preventDefault(); openSwitcher(event.shiftKey ? -1 : 1); return; }
      if (['KeyQ', 'KeyW'].includes(code)) { event.preventDefault(); commitSwitcher('close'); return; }
      if (['KeyM', 'KeyH'].includes(code)) { event.preventDefault(); commitSwitcher('minimize'); return; }
      if (event.key === 'Escape') { switcher = null; close(); return; }
      if (event.key === 'Enter') { event.preventDefault(); commitSwitcher(); return; }
    }
    if (typing(event.target)) return;
    if (event.altKey && !event.ctrlKey && !event.metaKey && code === 'Space') { event.preventDefault(); toggle('cmd'); }
    else if (event.altKey && event.ctrlKey && code === 'KeyV') { event.preventDefault(); toggle('clip'); }
    else if (event.altKey && !event.ctrlKey && !event.metaKey && event.key === 'Tab') { event.preventDefault(); openSwitcher(event.shiftKey ? -1 : 1); }
    else if (event.key === 'Escape' && open) close();
  });
  document.addEventListener('keyup', (event) => {
    if (switcher && (event.key === 'Alt' || event.key === 'Option')) commitSwitcher();
  });
  layer.addEventListener('pointerdown', (event) => { if (event.target === layer) { switcher = null; close(); } });

  function toggle(kind) {
    if (open?.kind === kind) { close(); return; }
    const restore = document.activeElement;
    const view = kind === 'cmd' ? commandBar() : clipboard();
    show(kind, view.el, restore);
    setTimeout(view.focus, 30);
  }

  onLang(() => { if (open && open.kind !== 'switcher') { const kind = open.kind; close(); toggle(kind); } });

  return { openCommand: () => toggle('cmd'), openClipboard: () => toggle('clip'), openSwitcher: () => openSwitcher(0), close, addClip };
}
