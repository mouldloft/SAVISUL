// A browser window running a replica of the SAVISUL extension's notch on a sample French news page.
import { h, clear } from './dom.js';
import { icon, mark } from './icons.js';
import { t, lang, onLang } from './i18n.js';

const ARTICLE = {
  fr: {
    nav: ['Trains', 'Villes', 'Archives'],
    kicker: 'Rail',
    title: 'Comment les trains de nuit ont appris le silence',
    byline: 'Par Mira Holt · 6 min de lecture',
    p1: 'Quand le dernier train régional quitte le quai, un autre chemin de fer se réveille. Les trains de nuit roulent sur des horaires qui semblent tranquilles sur le papier, mais chaque minute est négociée avec le fret, les équipes de voie et l’arithmétique lente des passagers qui doivent arriver reposés plutôt qu’en avance.',
    p2: 'Les voitures sont de petits exploits d’acoustique. Les planchers flottent sur des supports en caoutchouc, les attelages sont tendus pour que le train démarre sans à-coup, et l’air circule assez lentement pour que personne ne l’entende.',
    quote: 'On pardonne un retard bien plus facilement qu’une nuit passée à se tenir au mur.',
    caption: 'Tarifs de l’automne',
    head: ['Trajet', 'Départ', 'Prix'],
    rows: [['Vienne → Paris', '19:52', '89 €'], ['Berlin → Stockholm', '18:37', '99 €'], ['Zurich → Hambourg', '20:59', '79 €']],
    p3: 'Rien de tout cela ne fonctionne sans les gares. Les départs tardifs exigent des halls ouverts et des salles d’attente chauffées.',
    aside: 'La lettre du dimanche',
    asideBody: 'Un trajet, une gare, une histoire. Chaque semaine.',
    asideButton: 'S’abonner',
    cookie: 'Ce site utilise des cookies pour mesurer l’audience.',
    cookieOk: 'Accepter'
  },
  en: {
    nav: ['Trains', 'Cities', 'Archive'],
    kicker: 'Rail',
    title: 'How night trains learned to be quiet',
    byline: 'By Mira Holt · 6 min read',
    p1: 'When the last regional train leaves the platform, a different railway wakes up. Night trains run on timetables that look leisurely on paper, yet every minute is negotiated with freight, track crews and the slow arithmetic of passengers who must arrive rested rather than early.',
    p2: 'The carriages are small feats of acoustics. Floors float on rubber mounts, couplings are tensioned so the train starts without a jolt, and the air moves slowly enough that nobody hears it.',
    quote: 'People forgive a late arrival far more easily than a night spent bracing against the wall.',
    caption: 'Autumn fares',
    head: ['Route', 'Departs', 'Fare'],
    rows: [['Vienna → Paris', '19:52', '€89'], ['Berlin → Stockholm', '18:37', '€99'], ['Zurich → Hamburg', '20:59', '€79']],
    p3: 'None of this works without the stations. Late departures need open concourses and heated waiting rooms.',
    aside: 'The Sunday letter',
    asideBody: 'One route, one station, one story. Every week.',
    asideButton: 'Subscribe',
    cookie: 'This site uses cookies to measure its audience.',
    cookieOk: 'Accept'
  },
  ru: {
    nav: ['Поезда', 'Города', 'Архив'],
    kicker: 'Железная дорога',
    title: 'Как ночные поезда научились тишине',
    byline: 'Мира Холт · 6 минут чтения',
    p1: 'Когда последний пригородный поезд уходит с платформы, просыпается другая железная дорога. Ночные поезда ходят по расписанию, которое на бумаге выглядит неспешным, но каждая минута в нём согласована с грузовыми составами, путейцами и медленной арифметикой пассажиров, которым важно приехать выспавшимися, а не раньше.',
    p2: 'Вагоны — маленькие чудеса акустики. Полы стоят на резиновых опорах, сцепки натянуты так, чтобы поезд трогался без рывка, а воздух движется так медленно, что его никто не слышит.',
    quote: 'Опоздание прощают куда легче, чем ночь, проведённую упираясь в стену.',
    caption: 'Осенние тарифы',
    head: ['Маршрут', 'Отправление', 'Цена'],
    rows: [['Вена → Париж', '19:52', '89 €'], ['Берлин → Стокгольм', '18:37', '99 €'], ['Цюрих → Гамбург', '20:59', '79 €']],
    p3: 'Без вокзалов ничего этого не работает. Поздним отправлениям нужны открытые залы и тёплые комнаты ожидания.',
    aside: 'Воскресное письмо',
    asideBody: 'Один маршрут, один вокзал, одна история. Каждую неделю.',
    asideButton: 'Подписаться',
    cookie: 'Сайт использует cookie, чтобы считать посетителей.',
    cookieOk: 'Принять'
  }
};

const TRAIN_ART = `<svg viewBox="0 0 640 260" role="img" aria-label="" xmlns="http://www.w3.org/2000/svg">
<defs><linearGradient id="dusk" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#22304f"/><stop offset=".6" stop-color="#b9714f"/><stop offset="1" stop-color="#e6a874"/></linearGradient></defs>
<rect width="640" height="260" fill="url(#dusk)"/><circle cx="470" cy="118" r="34" fill="#f3d3a0"/>
<path d="M0 170 C120 140 220 168 330 150 S540 138 640 160 V260 H0Z" fill="#2a2433"/>
<rect x="70" y="176" width="500" height="44" rx="8" fill="#14121a"/>
${Array.from({ length: 11 }, (_, i) => `<rect x="${92 + i * 43}" y="186" width="26" height="12" rx="2" fill="#f2cf8e"/>`).join('')}
<rect x="0" y="226" width="640" height="5" fill="#0d0c10"/><rect x="0" y="236" width="640" height="24" fill="#0b0a0d"/></svg>`;

const TOOLS = [
  ['color', 'pipette'], ['ruler', 'ruler'], ['note', 'note'], ['shot', 'camera'], ['hide', 'eyeOff'],
  ['fonts', 'type'], ['css', 'inspect'], ['link', 'link'], ['data', 'table'], ['translate', 'translate'],
  ['save', 'download'], ['video', 'play'], ['media', 'film'], ['images', 'image'], ['speak', 'wave']
];
const PAGE = [['reader', 'book'], ['dark', 'moon'], ['copy', 'unlock'], ['edit', 'pencil'], ['outlines', 'outline']];
const BROWSER = [['tabs', 'tabs'], ['sessions', 'save'], ['ai', 'sparkle'], ['shelf', 'tray'], ['bookmarks', 'star'], ['notes', 'note']];
const WORKING = new Set(['color', 'ruler', 'css', 'note', 'hide', 'fonts', 'link', 'translate', 'reader', 'dark', 'edit', 'outlines']);

const toHex = (rgb) => {
  const m = rgb.match(/\d+(\.\d+)?/g);
  if (!m) return '#000000';
  return `#${m.slice(0, 3).map((v) => Math.round(Number(v)).toString(16).padStart(2, '0')).join('')}`.toUpperCase();
};

export function createBrowser(bus) {
  const state = { translated: false, reader: false, dark: false, edit: false, outlines: false, mode: null, hidden: [], note: '', view: 'idle' };

  // MARK: Page

  const page = h('div', { class: 'wp', lang: 'fr' });
  const scroller = h('div', { class: 'wp-scroll' }, page);
  const pageToast = h('div', { class: 'wp-toast', role: 'status', 'aria-live': 'polite' });
  const tip = h('div', { class: 'wp-tip', 'aria-hidden': 'true' });
  const box = h('div', { class: 'wp-box', 'aria-hidden': 'true' });

  function renderPage() {
    const copy = ARTICLE[state.translated ? lang : 'fr'];
    page.lang = state.translated ? lang : 'fr';
    page.innerHTML = '';
    page.append(
      h('header', { class: 'wp-header' }, h('span', { class: 'wp-logo', text: 'Field Notes' }), h('nav', null, copy.nav.map((n) => h('a', { href: '#', tabindex: '-1', text: n, onclick: (e) => e.preventDefault() })))),
      h('div', { class: 'wp-main' },
        h('article', { class: 'wp-article' },
          h('h1', { text: copy.title }),
          h('p', { class: 'wp-byline', text: copy.byline }),
          h('figure', { class: 'wp-figure' }),
          h('p', { text: copy.p1 }),
          h('p', { text: copy.p2 }),
          h('blockquote', { text: copy.quote }),
          h('table', null, h('caption', { text: copy.caption }),
            h('thead', null, h('tr', null, copy.head.map((c) => h('th', { text: c })))),
            h('tbody', null, copy.rows.map((r) => h('tr', null, r.map((c) => h('td', { text: c })))))),
          h('p', { text: copy.p3 })),
        h('aside', { class: 'wp-aside' }, h('b', { text: copy.aside }), h('p', { text: copy.asideBody }), h('span', { class: 'wp-sub', text: copy.asideButton }))),
      h('div', { class: 'wp-cookie' }, h('span', { text: copy.cookie }), h('span', { class: 'wp-sub', text: copy.cookieOk })));
    page.querySelector('.wp-figure').innerHTML = TRAIN_ART;
    for (const sel of state.hidden) page.querySelector(sel)?.classList.add('wp-gone');
    page.querySelector('.wp-article').contentEditable = state.edit ? 'true' : 'false';
  }

  // MARK: Notch

  const notch = h('div', { class: 'ext-notch', 'data-view': 'idle' });
  const notchButton = h('button', { class: 'ext-pill', type: 'button', 'aria-label': 'SAVISUL' }, mark(14));
  const notchBody = h('div', { class: 'ext-body' });
  notch.append(notchButton, notchBody);

  const say = (text) => {
    pageToast.textContent = text;
    pageToast.classList.add('show');
    clearTimeout(say.timer);
    say.timer = setTimeout(() => pageToast.classList.remove('show'), 2400);
  };

  const names = () => t('extToolNames');
  const tile = ([id, glyph]) => h('button', {
    class: `ext-tile${isActive(id) ? ' on' : ''}${WORKING.has(id) ? '' : ' soon'}`, type: 'button', onclick: () => run(id)
  }, h('span', { class: 'ext-tile-icon' }, icon(glyph, 18)), h('span', { text: names()[id] }));
  const chip = ([id, glyph]) => h('button', {
    class: `ext-chip${isActive(id) ? ' on' : ''}${WORKING.has(id) ? '' : ' soon'}`, type: 'button', onclick: () => run(id)
  }, icon(glyph, 15), h('span', { text: names()[id] }));

  function isActive(id) {
    return (id === 'reader' && state.reader) || (id === 'dark' && state.dark) || (id === 'translate' && state.translated)
      || (id === 'edit' && state.edit) || (id === 'outlines' && state.outlines) || (id === 'hide' && state.hidden.length > 0) || state.mode === id;
  }

  function renderNotch() {
    notch.dataset.view = state.view;
    clear(notchBody);
    if (state.view === 'home') {
      notchBody.append(
        h('div', { class: 'ext-head' }, mark(16), h('b', { text: 'SAVISUL' }), h('span', { class: 'ext-host', text: t('pageHost') }),
          h('button', { class: 'ext-x', type: 'button', 'aria-label': t('extStop'), onclick: () => setView('idle') }, icon('x', 14))),
        h('div', { class: 'ext-section', text: t('tTools') }), h('div', { class: 'ext-grid' }, TOOLS.map(tile)),
        h('div', { class: 'ext-section', text: t('tThisPage') }), h('div', { class: 'ext-chips' }, PAGE.map(chip)),
        h('div', { class: 'ext-section', text: t('tBrowser') }), h('div', { class: 'ext-chips' }, BROWSER.map(chip)));
    } else if (state.view === 'mode') {
      const [glyph, hint] = {
        color: ['pipette', t('extColorHint')], ruler: ['ruler', t('extRulerHint')], css: ['inspect', t('extRulerHint')],
        fonts: ['type', t('extFontsHint')], hide: ['eyeOff', state.hidden.length ? t('extHidden', state.hidden.length) : t('extHideHint')]
      }[state.mode];
      notchBody.append(h('div', { class: 'ext-mode' }, h('span', { class: 'ext-mode-icon' }, icon(glyph, 15)),
        h('span', { class: 'grow' }, h('b', { text: names()[state.mode] }), h('small', { text: hint })),
        state.mode === 'hide' && state.hidden.length ? h('button', { class: 'ext-small', type: 'button', text: t('extRestore'), onclick: () => { state.hidden = []; renderPage(); renderNotch(); } }) : null,
        h('button', { class: 'ext-small primary', type: 'button', text: t('extStop'), onclick: stopMode })));
    } else if (state.view === 'note') {
      const area = h('textarea', { placeholder: t('extNotePlaceholder'), rows: '4' });
      area.value = state.note;
      notchBody.append(h('div', { class: 'ext-panel' },
        h('div', { class: 'ext-panel-head' }, h('button', { class: 'ext-x', type: 'button', 'aria-label': 'Back', onclick: () => setView('home') }, icon('back', 14)), h('b', { text: t('extNoteTitle') })),
        area,
        h('button', { class: 'ext-small primary', type: 'button', text: t('extStop'), onclick: () => { state.note = area.value; say(t('extNoteSaved')); setView('idle'); } })));
      setTimeout(() => area.focus(), 60);
    } else if (state.view === 'link') {
      const clean = `https://${t('pageHost')}/trains-de-nuit`;
      const canvas = h('canvas', { class: 'ext-qr', width: '120', height: '120', 'aria-label': 'QR' });
      globalThis.SV_QR?.draw(canvas, clean, { scale: 4, margin: 2, dark: '#141312', light: '#f7f3ea' });
      const copy = async (text) => { bus.emit('copy', { kind: 'link', text }); say(t('extCopied', text.length > 40 ? `${text.slice(0, 38)}…` : text)); };
      notchBody.append(h('div', { class: 'ext-panel link-panel' },
        h('div', { class: 'ext-panel-head' }, h('button', { class: 'ext-x', type: 'button', 'aria-label': 'Back', onclick: () => setView('home') }, icon('back', 14)), h('b', { text: t('extLinkTitle') })),
        h('div', { class: 'link-row' }, canvas, h('div', { class: 'grow' },
          h('code', { text: clean }), h('small', { text: t('extTrackers', 3) }),
          h('div', { class: 'link-actions' },
            h('button', { class: 'ext-small primary', type: 'button', text: t('extCopyLink'), onclick: () => copy(clean) }),
            h('button', { class: 'ext-small', type: 'button', text: t('extCopyMd'), onclick: () => copy(`[${ARTICLE[state.translated ? lang : 'fr'].title}](${clean})`) }))))));
    }
  }

  function setView(view) {
    state.view = view;
    renderNotch();
  }

  // MARK: Tools

  function stopMode() {
    state.mode = null;
    page.classList.remove('picking', 'hiding');
    tip.classList.remove('show');
    box.classList.remove('show');
    setView('idle');
  }

  function run(id) {
    if (!WORKING.has(id)) { say(t('extInExtension', names()[id])); return; }
    if (['color', 'ruler', 'css', 'fonts', 'hide'].includes(id)) {
      state.mode = id;
      page.classList.add('picking');
      page.classList.toggle('hiding', id === 'hide');
      setView('mode');
      return;
    }
    if (id === 'note' || id === 'link') { setView(id); return; }
    if (id === 'dark') { state.dark = !state.dark; page.classList.toggle('dark', state.dark); say(t(state.dark ? 'extDarkOn' : 'extDarkOff')); }
    if (id === 'reader') { state.reader = !state.reader; page.classList.toggle('reader', state.reader); if (state.reader) say(t('extReaderOn')); scroller.scrollTop = 0; }
    if (id === 'translate') { state.translated = !state.translated; renderPage(); say(t(state.translated ? 'extTranslated' : 'extOriginal')); }
    if (id === 'edit') { state.edit = !state.edit; renderPage(); say(t(state.edit ? 'extEditOn' : 'extEditOff')); }
    if (id === 'outlines') { state.outlines = !state.outlines; page.classList.toggle('outlines', state.outlines); say(t(state.outlines ? 'extOutlinesOn' : 'extOutlinesOff')); }
    setView('idle');
  }

  const selectorFor = (el) => {
    if (el.classList.contains('wp-cookie')) return '.wp-cookie';
    if (el.closest('.wp-aside')) return '.wp-aside';
    if (el.closest('.wp-header')) return '.wp-header';
    if (el.closest('.wp-figure')) return '.wp-figure';
    if (el.closest('table')) return '.wp-article table';
    if (el.closest('blockquote')) return '.wp-article blockquote';
    const p = el.closest('.wp-article > p');
    if (p) return `.wp-article > p:nth-of-type(${[...p.parentElement.querySelectorAll(':scope > p')].indexOf(p) + 1})`;
    return null;
  };

  page.addEventListener('pointermove', (event) => {
    if (!state.mode) return;
    const target = event.target.closest('.wp *');
    if (!target || target === page) return;
    const frame = scroller.getBoundingClientRect();
    const r = target.getBoundingClientRect();
    Object.assign(box.style, { left: `${r.left - frame.left}px`, top: `${r.top - frame.top}px`, width: `${r.width}px`, height: `${r.height}px` });
    box.classList.add('show');
    box.classList.toggle('danger', state.mode === 'hide');
    const cs = getComputedStyle(target);
    let text = '';
    clear(tip);
    if (state.mode === 'color') {
      const bg = cs.backgroundColor;
      const color = /rgba\(0, 0, 0, 0\)|transparent/.test(bg) ? cs.color : bg;
      text = toHex(color);
      tip.append(h('i', { class: 'sw', style: { background: color } }), h('b', { text }));
    } else if (state.mode === 'fonts') {
      text = `${cs.fontFamily.split(',')[0].replace(/"/g, '')} · ${Math.round(parseFloat(cs.fontSize))}px · ${cs.fontWeight}`;
      tip.append(h('b', { text }));
    } else if (state.mode === 'hide') {
      tip.append(h('b', { text: target.tagName.toLowerCase() }));
    } else {
      tip.append(h('b', { text: `${Math.round(r.width)} × ${Math.round(r.height)}` }),
        h('small', { text: `${target.tagName.toLowerCase()} · ${cs.paddingTop} ${cs.paddingRight}` }));
    }
    Object.assign(tip.style, { left: `${Math.min(event.clientX - frame.left + 14, frame.width - 200)}px`, top: `${event.clientY - frame.top + 18}px` });
    tip.classList.add('show');
    tip.dataset.value = text;
  });
  page.addEventListener('pointerleave', () => { tip.classList.remove('show'); box.classList.remove('show'); });
  page.addEventListener('click', (event) => {
    if (!state.mode) return;
    event.preventDefault();
    if (state.mode === 'color') {
      const value = tip.dataset.value;
      if (value) { bus.emit('copy', { kind: 'color', text: value }); say(t('extCopied', value)); }
    } else if (state.mode === 'hide') {
      const sel = selectorFor(event.target);
      if (sel && !state.hidden.includes(sel)) { state.hidden.push(sel); page.querySelector(sel)?.classList.add('wp-gone'); box.classList.remove('show'); renderNotch(); }
    } else if (state.mode === 'css' || state.mode === 'ruler') {
      const target = event.target.closest('.wp *');
      if (target) {
        const cs = getComputedStyle(target);
        const css = `${target.tagName.toLowerCase()} {\n  font: ${cs.fontWeight} ${cs.fontSize}/${cs.lineHeight} ${cs.fontFamily.split(',')[0]};\n  color: ${toHex(cs.color)};\n  padding: ${cs.padding};\n}`;
        bus.emit('copy', { kind: 'text', text: css });
        say(t('extCopied', 'CSS'));
      }
    }
  });

  notch.addEventListener('pointerenter', (event) => { if (event.pointerType !== 'touch' && state.view === 'idle') setView('home'); });
  notch.addEventListener('pointerleave', (event) => {
    if (event.pointerType === 'touch') return;
    clearTimeout(notch.leave);
    notch.leave = setTimeout(() => { if (state.view === 'home' && !notch.matches(':hover')) setView('idle'); }, 420);
  });
  notchButton.addEventListener('click', () => setView(state.view === 'idle' ? 'home' : 'idle'));

  // MARK: Window chrome

  const omnibox = h('div', { class: 'omnibox' }, icon('lock', 13), h('span', { class: 'host', text: t('pageHost') }), h('span', { class: 'path', text: t('pagePath') }));
  const extButton = h('button', { class: 'ext-button', type: 'button', 'aria-label': 'SAVISUL', onclick: () => setView(state.view === 'home' ? 'idle' : 'home') }, mark(15));
  const chrome = h('div', { class: 'browser-chrome' },
    h('div', { class: 'browser-tabs' }, h('span', { class: 'browser-tab' }, h('span', { class: 'tab-fav', text: 'F' }), h('span', { class: 'tab-title', text: t('pageTitle') }), icon('x', 12))),
    h('div', { class: 'browser-bar' }, h('span', { class: 'nav-buttons', 'aria-hidden': 'true' }, icon('back', 15), h('span', { class: 'flip' }, icon('back', 15)), icon('restore', 14)), omnibox, extButton));
  const viewport = h('div', { class: 'browser-viewport' }, scroller, notch, box, tip, pageToast);
  const root = h('div', { class: 'browser' }, chrome, viewport);

  document.addEventListener('keydown', (event) => {
    if (event.key !== 'Escape' || !root.isConnected) return;
    if (state.mode) stopMode();
    else if (state.reader) { state.reader = false; page.classList.remove('reader'); }
    else if (state.view !== 'idle') setView('idle');
  });

  onLang(() => {
    renderPage();
    renderNotch();
    omnibox.querySelector('.path').textContent = t('pagePath');
  });

  renderPage();
  renderNotch();
  return { root, chrome, openNotch: () => setView('home'), run };
}
