// The live desktop: menu bar (also the site's navigation), windows with snapping, the Dock, and the phone layout.
import { h, clear, clamp, reducedMotion, formatClock } from './dom.js';
import { icon, mark } from './icons.js';
import { t, lang, setLang, onLang } from './i18n.js';
import { CONFIG } from './config.js';
import { createIsland } from './island.js';
import { createPanel } from './panel.js';
import { createBrowser } from './browser.js';
import { createOverlays } from './overlays.js';

const MENU_H = 34;
const DOCK_RESERVE = 92;
const GAP = 8;
const PHONE = 760;

export function createDesktop(root, bus) {
  const area = root.querySelector('.windows');
  const islandHost = root.querySelector('.island-host');
  const menubar = root.querySelector('.menubar');
  const dockEl = root.querySelector('.dock');
  const hero = root.querySelector('.hero-copy');

  const island = createIsland(islandHost, bus);
  const panel = createPanel(bus);
  const browser = createBrowser(bus);

  const windows = new Map();
  let z = 10;
  let focused = null;
  const phone = () => innerWidth < PHONE;

  // MARK: Windows

  function makeWindow(id, { title, glyph, content, kind = 'window', className = '' }) {
    const titleEl = h('span', { class: 'win-title' });
    const lights = h('div', { class: 'lights' },
      h('button', { class: 'light close', type: 'button', 'aria-label': 'Close', onclick: () => closeWindow(id) }),
      h('button', { class: 'light min', type: 'button', 'aria-label': 'Minimize', onclick: () => minimizeWindow(id) }),
      h('button', { class: 'light zoom', type: 'button', 'aria-label': 'Zoom', onclick: () => snap(id, win.snapped === 'max' ? 'restore' : 'max') }));
    const bar = kind === 'window' ? h('div', { class: 'win-bar' }, lights, titleEl, h('span', { class: 'win-spacer' })) : null;
    const el = h('section', { class: `win ${kind} ${className}`, 'data-id': id, hidden: true, 'aria-label': title() }, bar, content);
    area.append(el);
    const win = { id, el, bar, titleEl, title, glyph, kind, open: false, minimized: false, frame: null, saved: null, snapped: null, cycle: 0 };
    windows.set(id, win);
    el.addEventListener('pointerdown', (event) => {
      const active = document.activeElement;
      if (active && active !== document.body && !el.contains(active) && active.matches?.('input, textarea')) active.blur();
      if (event.target.closest('.win-bar')) win.el.focus?.();
      focus(id);
    }, true);
    if (bar) dragging(win);
    return win;
  }

  function place(win, frame, animate = false) {
    win.frame = { ...frame };
    if (phone()) return;
    const { el } = win;
    if (animate && !reducedMotion()) {
      el.classList.add('gliding');
      clearTimeout(win.glide);
      win.glide = setTimeout(() => el.classList.remove('gliding'), 420);
    }
    Object.assign(el.style, { left: `${frame.x}px`, top: `${frame.y}px`, width: `${frame.w}px`, height: frame.h ? `${frame.h}px` : '' });
  }

  function focus(id) {
    const win = windows.get(id);
    if (!win) return;
    focused = id;
    win.el.style.zIndex = String(++z);
    for (const w of windows.values()) w.el.classList.toggle('focused', w.id === id);
    renderDock();
  }

  function dockRect(id) {
    const tile = dockEl.querySelector(`[data-dock="${id}"]`);
    return tile?.getBoundingClientRect();
  }

  // macOS-style open: the window grows out of its Dock icon.
  let booting = true;
  function animateFrom(win, from, reverse = false) {
    if (booting || reducedMotion() || phone() || !from) return Promise.resolve();
    const r = win.el.getBoundingClientRect();
    const dx = from.left + from.width / 2 - (r.left + r.width / 2);
    const dy = from.top + from.height / 2 - (r.top + r.height / 2);
    const s = Math.max(0.08, from.width / r.width);
    const frames = [{ transform: `translate(${dx}px, ${dy}px) scale(${s})`, opacity: 0, filter: 'blur(6px)' }, { transform: 'none', opacity: 1, filter: 'blur(0)' }];
    return win.el.animate(reverse ? frames.reverse() : frames, { duration: reverse ? 320 : 460, easing: 'cubic-bezier(.16, 1, .3, 1)' }).finished.catch(() => {});
  }

  function openWindow(id) {
    const win = windows.get(id);
    if (!win) return;
    if (phone()) { showPhone(id); return; }
    const wasHidden = !win.open || win.minimized;
    win.open = true;
    win.minimized = false;
    if (!win.frame) place(win, defaultFrame(id) || { x: Math.round(area.clientWidth / 2 - 144), y: MENU_H + 160, w: 288, h: null });
    win.el.hidden = false;
    focus(id);
    if (wasHidden) animateFrom(win, id === 'panel' ? menubar.querySelector('.status-savisul')?.getBoundingClientRect() : dockRect(id));
    renderDock();
  }

  async function closeWindow(id) {
    const win = windows.get(id);
    if (!win || !win.open) return;
    win.open = false;
    win.minimized = false;
    if (!phone()) await animateFrom(win, id === 'panel' ? menubar.querySelector('.status-savisul')?.getBoundingClientRect() : dockRect(id), true);
    win.el.hidden = true;
    if (focused === id) focused = null;
    renderDock();
  }

  async function minimizeWindow(id) {
    const win = windows.get(id);
    if (!win || !win.open) return;
    win.minimized = true;
    if (!phone()) await animateFrom(win, dockRect(id), true);
    win.el.hidden = true;
    renderDock();
  }

  // MARK: Snapping

  const bounds = () => {
    const w = area.clientWidth;
    const hgt = area.clientHeight;
    return { x: GAP, y: MENU_H + GAP, w: w - GAP * 2, h: hgt - MENU_H - DOCK_RESERVE - GAP };
  };

  function snapFrame(where) {
    const b = bounds();
    const half = (b.w - GAP) / 2;
    const frames = {
      left: { x: b.x, y: b.y, w: half, h: b.h },
      right: { x: b.x + half + GAP, y: b.y, w: half, h: b.h },
      left23: { x: b.x, y: b.y, w: (b.w - GAP) * 2 / 3, h: b.h },
      right23: { x: b.x + (b.w - GAP) / 3 + GAP, y: b.y, w: (b.w - GAP) * 2 / 3, h: b.h },
      left13: { x: b.x, y: b.y, w: (b.w - GAP) / 3, h: b.h },
      right13: { x: b.x + (b.w - GAP) * 2 / 3 + GAP, y: b.y, w: (b.w - GAP) / 3, h: b.h },
      tl: { x: b.x, y: b.y, w: half, h: (b.h - GAP) / 2 },
      tr: { x: b.x + half + GAP, y: b.y, w: half, h: (b.h - GAP) / 2 },
      max: { x: b.x + 24, y: b.y + 8, w: b.w - 48, h: b.h - 8 }
    };
    return frames[where];
  }

  function snap(id, where) {
    const win = windows.get(id);
    if (!win || win.kind !== 'window' || phone()) return;
    if (!win.open || win.minimized) openWindow(id);
    if (where === 'restore') {
      if (win.saved) place(win, win.saved, true);
      win.snapped = null;
      win.cycle = 0;
      return;
    }
    if (!win.snapped) win.saved = { ...win.frame };
    // Repeating a half narrows it: ½ → ⅔ → ⅓, like the app.
    let target = where;
    if (where === 'left' || where === 'right') {
      const steps = where === 'left' ? ['left', 'left23', 'left13'] : ['right', 'right23', 'right13'];
      win.cycle = steps.includes(win.snapped) ? (steps.indexOf(win.snapped) + 1) % 3 : 0;
      target = steps[win.cycle];
    }
    win.snapped = target;
    place(win, snapFrame(target), true);
    focus(id);
  }

  const preview = h('div', { class: 'snap-preview', 'aria-hidden': 'true' }, h('span', { text: t('snapHint') }));
  area.append(preview);

  function dragging(win) {
    let start = null;
    win.bar.addEventListener('pointerdown', (event) => {
      if (event.button !== 0 || event.target.closest('button') || phone()) return;
      event.preventDefault();
      win.bar.setPointerCapture(event.pointerId);
      const frame = win.frame;
      if (win.snapped && win.saved) {
        // Pulling a snapped window out restores its size under the pointer.
        const ratio = (event.clientX - area.getBoundingClientRect().left - frame.x) / frame.w;
        win.frame = { ...win.saved, x: event.clientX - area.getBoundingClientRect().left - win.saved.w * ratio, y: frame.y };
        win.snapped = null;
        place(win, win.frame);
      }
      start = { x: event.clientX, y: event.clientY, frame: { ...win.frame }, target: null };
      win.el.classList.add('dragging');
    });
    win.bar.addEventListener('pointermove', (event) => {
      if (!start) return;
      const a = area.getBoundingClientRect();
      const x = clamp(start.frame.x + event.clientX - start.x, -start.frame.w + 120, a.width - 120);
      const y = clamp(start.frame.y + event.clientY - start.y, MENU_H, a.height - 60);
      place(win, { ...start.frame, x, y });
      const px = event.clientX - a.left;
      const py = event.clientY - a.top;
      let target = null;
      if (px < 18 && py < MENU_H + 60) target = 'tl';
      else if (px > a.width - 18 && py < MENU_H + 60) target = 'tr';
      else if (px < 18) target = 'left';
      else if (px > a.width - 18) target = 'right';
      else if (py < MENU_H + 6) target = 'max';
      start.target = target;
      if (target) {
        const f = snapFrame(target);
        Object.assign(preview.style, { left: `${f.x}px`, top: `${f.y}px`, width: `${f.w}px`, height: `${f.h}px` });
        preview.classList.add('show');
      } else preview.classList.remove('show');
    });
    const end = () => {
      if (!start) return;
      const { target, frame } = start;
      start = null;
      win.el.classList.remove('dragging');
      preview.classList.remove('show');
      if (target) {
        win.saved = { ...frame, x: win.frame.x, y: Math.max(MENU_H + GAP, win.frame.y) };
        win.cycle = 0;
        win.snapped = target;
        place(win, snapFrame(target), true);
        if (win.id === 'note') bus.emit('snapped', target);
      }
    };
    win.bar.addEventListener('pointerup', end);
    win.bar.addEventListener('pointercancel', end);
  }

  // MARK: Layout

  function defaultFrame(id) {
    const W = area.clientWidth;
    const H = area.clientHeight;
    if (id === 'panel') {
      // The app's panel is 400 × 656; it only gets shorter when the window is.
      const w = 400;
      const hh = Math.min(656, H - MENU_H - DOCK_RESERVE - 12);
      return { x: W - w - 12, y: MENU_H + 8, w, h: hh };
    }
    if (id === 'browser') {
      const w = Math.min(980, W - 140);
      const hh = Math.min(640, H - MENU_H - DOCK_RESERVE - 30);
      return { x: Math.round((W - w) / 2), y: MENU_H + 22, w, h: hh };
    }
    if (id === 'terminal') {
      const w = Math.min(620, W - 80);
      return { x: Math.round(W * 0.18), y: Math.round(H * 0.3), w, h: 300 };
    }
    // The note goes where the headline and the panel leave room.
    const w = 288;
    const hh = 330;
    const heroBox = hero.getBoundingClientRect();
    const a = area.getBoundingClientRect();
    const heroRight = heroBox.right - a.left;
    const heroBottom = heroBox.bottom - a.top;
    const panelLeft = windows.get('panel')?.open ? windows.get('panel').frame.x : W;
    const heroTop = hero.querySelector('h1').getBoundingClientRect().top - a.top;
    if (panelLeft - heroRight - 48 >= w) return { x: Math.round(heroRight + (panelLeft - heroRight - w) / 2), y: Math.round(Math.max(MENU_H + 150, heroTop + 6)), w, h: null };
    if (H - DOCK_RESERVE - heroBottom - 24 >= hh * 0.85) return { x: Math.round(heroBox.left - a.left), y: Math.round(heroBottom + 24), w, h: null };
    return booting ? null : { x: Math.round(panelLeft - w - 24), y: MENU_H + 140, w, h: null };
  }

  function layout(initial = false) {
    if (phone()) return;
    for (const win of windows.values()) {
      if (initial || !win.frame) win.frame = null;
      if (win.open && !win.minimized) {
        const f = win.snapped && win.snapped !== 'restore' ? snapFrame(win.snapped) : (win.frame && !initial ? win.frame : defaultFrame(win.id));
        if (!f) continue;
        const W = area.clientWidth;
        const H = area.clientHeight;
        f.w = Math.min(f.w, W - 16);
        f.x = clamp(f.x, 8 - f.w + 160, W - 160);
        f.y = clamp(f.y, MENU_H + 4, H - 80);
        place(win, f);
      }
    }
  }

  // MARK: Note, terminal

  const noteList = h('ul', { class: 'note-list' });
  const noteBody = h('div', { class: 'note-body' }, h('h3', { class: 'note-title' }), noteList, h('p', { class: 'note-foot' }));
  const NOTE_ACTIONS = {
    island: () => island.expand('home'),
    search: () => overlays.openCommand(),
    clipboard: () => overlays.openClipboard(),
    switch: () => overlays.openSwitcher(),
    snap: () => snap('note', 'left'),
    browser: () => openWindow('browser'),
    panel: () => openWindow('panel')
  };
  const tried = new Set();
  bus.on('island-touched', () => { if (!tried.has('island')) { tried.add('island'); renderNote(); } });
  bus.on('snapped', () => { if (!tried.has('snap')) { tried.add('snap'); renderNote(); } });
  function renderNote() {
    noteBody.querySelector('.note-title').textContent = t('noteTitle');
    noteBody.querySelector('.note-foot').textContent = t('noteFoot');
    clear(noteList);
    for (const [id, text] of t(phone() ? 'noteItemsTouch' : 'noteItems')) {
      noteList.append(h('li', null, h('button', {
        type: 'button', class: `note-item${tried.has(id) ? ' done' : ''}`,
        onclick: () => { tried.add(id); NOTE_ACTIONS[id](); renderNote(); }
      }, h('span', { class: 'note-check' }), h('span', { text }))));
    }
  }

  const termBody = h('div', { class: 'term' });
  function renderTerminal() {
    clear(termBody);
    for (const [kind, text] of t('termLines')) {
      termBody.append(h('div', { class: `term-line ${kind}` }, kind === 'cmd' ? h('span', { class: 'prompt', text: '~ % ' }) : null, text.replace('{0}', CONFIG.version)));
    }
    termBody.append(h('div', { class: 'term-actions' },
      h('a', { class: 'term-link', href: CONFIG.dmg, download: '' }, icon('download', 14), t('termDownload', CONFIG.version)),
      h('a', { class: 'term-link', href: CONFIG.help[lang] || CONFIG.help.en, download: '' }, icon('page', 14), t('termHelp'))),
    h('div', { class: 'term-line' }, h('span', { class: 'prompt', text: '~ % ' }), h('span', { class: 'cursor' })));
  }

  makeWindow('panel', { title: () => t('winPanel'), glyph: 'grid', content: panel.root, kind: 'popover' });
  makeWindow('note', { title: () => t('winNote'), glyph: 'note', content: noteBody, className: 'note-win' });
  makeWindow('browser', { title: () => t('winBrowser'), glyph: 'globe', content: browser.root, className: 'browser-win' });
  makeWindow('terminal', { title: () => t('winTerminal'), glyph: 'terminal', content: termBody, className: 'terminal-win' });
  const browserBar = windows.get('browser').bar;
  browserBar.querySelector('.win-title').replaceWith(browser.chrome.querySelector('.browser-tabs'));
  browser.chrome.prepend(browserBar);

  // MARK: Menu bar

  let openMenu = null;
  function dropdown(trigger, items) {
    const menu = h('div', { class: 'menu', role: 'menu' }, items.map((item) => item === '-' ? h('hr') : h(item.href ? 'a' : 'button', {
      class: 'menu-item', role: 'menuitem', href: item.href, download: item.download ? '' : null, type: item.href ? null : 'button',
      target: item.external ? '_blank' : null, rel: item.external ? 'noopener' : null,
      onclick: () => { closeMenus(); item.run?.(); }
    }, item.check != null ? h('span', { class: 'menu-check' }, item.check ? icon('check', 13) : null) : null, h('span', { class: 'grow', text: item.label }), item.key ? h('span', { class: 'menu-key', text: item.key }) : null)));
    trigger.after(menu);
    return menu;
  }
  function closeMenus() {
    openMenu?.menu.remove();
    openMenu?.trigger.setAttribute('aria-expanded', 'false');
    openMenu = null;
  }
  function toggleMenu(trigger, build) {
    if (openMenu?.trigger === trigger) { closeMenus(); return; }
    closeMenus();
    trigger.setAttribute('aria-expanded', 'true');
    openMenu = { trigger, menu: dropdown(trigger, build()) };
  }
  document.addEventListener('pointerdown', (event) => { if (openMenu && !event.target.closest('.menu, .menu-trigger')) closeMenus(); });
  document.addEventListener('keydown', (event) => { if (event.key === 'Escape') closeMenus(); });

  const clock = h('span', { class: 'clock' });
  const tickClock = () => {
    const now = new Date();
    const time = now.toLocaleTimeString(lang === 'ru' ? 'ru-RU' : 'en-US', { hour: '2-digit', minute: '2-digit', hour12: false });
    clear(clock).append(h('span', { class: 'clock-day', text: formatClock(now, lang).replace(time, '').trim() }), h('span', { class: 'clock-time', text: time }));
  };
  setInterval(tickClock, 15000);

  function renderMenubar() {
    const appItems = () => [
      { label: t('menuAbout'), href: '#guide' },
      '-',
      { label: t('menuDownloadMac'), href: CONFIG.dmg, download: true },
      { label: t('menuZip'), href: CONFIG.zip, download: true },
      CONFIG.github ? { label: t('menuGithub'), href: CONFIG.github, external: true } : null,
      '-',
      { label: t('menuPolicy'), href: 'privacy.html' },
      { label: t('menuLicense'), href: 'license.html' },
      { label: t('menuContact'), href: `mailto:${CONFIG.email}` }
    ].filter(Boolean);
    const appTrigger = h('button', { class: 'menu-trigger app-name', type: 'button', 'aria-haspopup': 'true', 'aria-expanded': 'false' }, mark(17), h('b', { text: 'SAVISUL' }));
    appTrigger.addEventListener('click', () => toggleMenu(appTrigger, appItems));
    const langTrigger = h('button', { class: 'menu-trigger input-source', type: 'button', 'aria-haspopup': 'true', 'aria-expanded': 'false', 'aria-label': t('menuLanguage'), text: lang.toUpperCase() });
    langTrigger.addEventListener('click', () => toggleMenu(langTrigger, () => [
      { label: 'English', check: lang === 'en', run: () => setLang('en') },
      { label: 'Русский', check: lang === 'ru', run: () => setLang('ru') }
    ]));
    const status = h('button', { class: 'status-item status-savisul', type: 'button', 'aria-label': t('menuPanel'), title: `${t('menuPanel')} ⌃⌥S`, onclick: () => togglePanel() }, mark(18));
    const search = h('button', { class: 'status-item', type: 'button', 'aria-label': t('menuSearch'), title: `${t('menuSearch')} ⌥Space`, onclick: () => overlays.openCommand() }, icon('search', 15));
    clear(menubar).append(
      h('div', { class: 'menu-left' },
        h('div', { class: 'menu-wrap' }, appTrigger),
        h('a', { class: 'menu-link', href: '#guide', text: t('menuGuide') }),
        h('a', { class: 'menu-link', href: '#chrome', text: t('menuChrome') }),
        h('a', { class: 'menu-link', href: '#privacy', text: t('menuPrivacy') }),
        h('a', { class: 'menu-link', href: '#open-source', text: t('menuOpen') }),
        h('a', { class: 'menu-link', href: '#download', text: t('menuDownload') })),
      h('div', { class: 'menu-right' },
        status, search,
        h('div', { class: 'menu-wrap' }, langTrigger),
        h('span', { class: 'status-item static', 'aria-hidden': 'true' }, icon('wifi', 15)),
        h('span', { class: 'status-item static battery-item', 'aria-hidden': 'true' }, h('span', { text: '82%' }), icon('battery', 19)),
        clock));
    tickClock();
  }

  function togglePanel(tab) {
    const win = windows.get('panel');
    if (tab) panel.setTab(tab);
    if (win.open && !win.minimized && !tab && focused === 'panel') closeWindow('panel');
    else openWindow('panel');
  }

  // MARK: Dock

  const DOCK = [
    { id: 'panel', label: () => t('dockSavisul'), art: () => h('img', { src: 'assets/img/icon-256.webp', alt: '', width: '256', height: '256', draggable: 'false' }) },
    { id: 'browser', label: () => t('winBrowser'), art: () => h('span', { class: 'tile browser-tile' }, icon('globe', 30)) },
    { id: 'note', label: () => t('winNote'), art: () => h('span', { class: 'tile note-tile' }, icon('note', 28)) },
    { id: 'terminal', label: () => t('winTerminal'), art: () => h('span', { class: 'tile terminal-tile' }, icon('terminal', 28)) },
    '-',
    { id: 'download', label: () => t('dockDownload'), art: () => h('span', { class: 'tile download-tile' }, icon('download', 28)), href: CONFIG.dmg }
  ];

  function renderDock() {
    if (!dockEl.firstChild) {
      for (const item of DOCK) {
        if (item === '-') { dockEl.append(h('span', { class: 'dock-sep', 'aria-hidden': 'true' })); continue; }
        const label = h('span', { class: 'dock-label' });
        const el = h(item.href ? 'a' : 'button', {
          class: 'dock-item', 'data-dock': item.id, type: item.href ? null : 'button', href: item.href || null, download: item.href ? '' : null,
          onclick: () => {
            if (item.href) { bus.emit('peek', 'download', CONFIG.version); return; }
            if (item.id === 'panel') togglePanel();
            else if (phone()) showPhone(item.id);
            else openWindow(item.id);
          }
        }, label, h('span', { class: 'dock-art' }, item.art()), h('span', { class: 'dock-dot', 'aria-hidden': 'true' }));
        dockEl.append(el);
      }
    }
    for (const item of DOCK) {
      if (item === '-') continue;
      const el = dockEl.querySelector(`[data-dock="${item.id}"]`);
      const win = windows.get(item.id);
      el.querySelector('.dock-label').textContent = item.label();
      el.setAttribute('aria-label', item.label());
      el.classList.toggle('running', !!win?.open);
      el.classList.toggle('active', phone() ? phoneView === item.id : focused === item.id && !!win?.open && !win.minimized);
    }
  }

  // Magnification, the Dock's own motion.
  dockEl.addEventListener('pointermove', (event) => {
    if (reducedMotion() || event.pointerType !== 'mouse') return;
    for (const item of dockEl.querySelectorAll('.dock-item')) {
      const r = item.getBoundingClientRect();
      const d = Math.abs(event.clientX - (r.left + r.width / 2));
      item.style.setProperty('--mag', (1 + 0.42 * Math.max(0, 1 - d / 150)).toFixed(3));
    }
  });
  dockEl.addEventListener('pointerleave', () => { for (const item of dockEl.querySelectorAll('.dock-item')) item.style.setProperty('--mag', '1'); });

  // MARK: Phone

  let phoneView = 'panel';
  function showPhone(id) {
    phoneView = id;
    for (const win of windows.values()) {
      win.open = win.id === id;
      win.el.hidden = win.id !== id;
    }
    root.dataset.phoneView = id;
    renderDock();
  }

  let wasPhone = null;
  function applyMode() {
    const now = phone();
    if (now === wasPhone) { layout(); return; }
    wasPhone = now;
    root.classList.toggle('phone', now);
    if (now) {
      for (const win of windows.values()) Object.assign(win.el.style, { left: '', top: '', width: '', height: '', zIndex: '' });
      showPhone(phoneView);
    } else {
      for (const win of windows.values()) { win.open = false; win.el.hidden = true; win.frame = null; }
      if (innerWidth >= 1100) openWindow('panel');
      if (defaultFrame('note')) openWindow('note');
      layout(true);
    }
    renderNote();
  }

  // MARK: Keys

  document.addEventListener('keydown', (event) => {
    if (event.target.closest?.('input, textarea, [contenteditable="true"]')) return;
    const ctrlAlt = event.ctrlKey && event.altKey && !event.metaKey;
    if (ctrlAlt && event.code === 'KeyS') { event.preventDefault(); togglePanel(); return; }
    if (event.altKey && event.shiftKey && event.code === 'KeyN') { event.preventDefault(); openWindow('browser'); browser.openNotch(); return; }
    if (!ctrlAlt) return;
    const target = focused && windows.get(focused)?.kind === 'window' ? focused : 'note';
    const map = { ArrowLeft: 'left', ArrowRight: 'right', Enter: 'max', Backspace: 'restore', KeyU: 'tl', KeyI: 'tr' };
    const where = map[event.code] || map[event.key];
    if (where) { event.preventDefault(); snap(target, where); }
  });

  const overlays = createOverlays(bus, {
    listWindows: () => [...windows.values()].map((w) => ({ id: w.id, title: w.title(), glyph: w.glyph, open: w.open && !w.minimized })),
    openWindow, closeWindow, minimizeWindow,
    openPanel: (tab) => togglePanel(tab)
  });

  bus.on('panel', (tab) => togglePanel(tab));
  bus.on('panel-close', () => closeWindow('panel'));
  bus.on('open-window', (id) => openWindow(id));
  bus.on('open-browser', () => { openWindow('browser'); setTimeout(() => browser.openNotch(), 500); });

  // Display off: the screen goes dark until the next click or key, like the app's utility.
  const dark = h('div', { class: 'display-off', 'aria-hidden': 'true' });
  root.append(dark);
  bus.on('display-off', () => {
    dark.classList.add('on');
    const wake = () => { dark.classList.remove('on'); removeEventListener('keydown', wake, true); };
    setTimeout(() => { dark.addEventListener('pointerdown', wake, { once: true }); addEventListener('keydown', wake, true); }, 300);
    setTimeout(wake, 4000);
  });

  onLang(() => {
    renderMenubar();
    renderDock();
    renderNote();
    renderTerminal();
    preview.querySelector('span').textContent = t('snapHint');
    for (const win of windows.values()) { win.titleEl.textContent = win.title(); win.el.setAttribute('aria-label', win.title()); }
  });

  renderMenubar();
  renderNote();
  renderTerminal();
  for (const win of windows.values()) win.titleEl.textContent = win.title();
  renderDock();
  applyMode();
  booting = false;
  let resizeTimer;
  addEventListener('resize', () => { clearTimeout(resizeTimer); resizeTimer = setTimeout(applyMode, 120); });

  return {
    island, panel, browser, overlays,
    openWindow, closeWindow, snap,
    openPanel: (tab) => { if (tab) panel.setTab(tab); openWindow('panel'); },
    openBrowser: () => { openWindow('browser'); setTimeout(() => browser.openNotch(), 500); }
  };
}
