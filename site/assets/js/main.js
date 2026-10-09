// Home page: the live desktop on top, the field guide below, both in English or Russian.
import { h, clear, createBus, coarsePointer, copyText } from './dom.js';
import { hydrateIcons, icon } from './icons.js';
import { t, lang, apply, onLang, setLang } from './i18n.js';
import { CONFIG } from './config.js';
import { createDesktop } from './desktop.js';
import { renderPlates } from './plates.js';

const bus = createBus();
const desktopRoot = document.querySelector('.desktop');

function keycaps(text) {
  if (text.startsWith('icon:')) return h('span', { class: 'keys glyph', 'aria-hidden': 'true' }, icon(text.slice(5), 16));
  return h('span', { class: 'keys' }, text.split(' ').map((part) => (part === '+' ? h('span', { class: 'key-plus', text: '+' }) : h('kbd', { text: part }))));
}

function rows(list) {
  return h('dl', { class: 'spec' }, list.map(([glyph, name, text]) => h('div', { class: 'spec-row' },
    h('dt', null, h('span', { class: 'spec-icon' }, icon(glyph, 18)), name), h('dd', { text }))));
}

function keyRows(list) {
  return h('dl', { class: 'spec keyed' }, list.map(([combo, text]) => h('div', { class: 'spec-row' }, h('dt', null, keycaps(combo)), h('dd', { text }))));
}

function renderGuide() {
  const fill = (id, node) => { const slot = document.getElementById(id); if (slot) clear(slot).append(node); };
  fill('island-rows', rows(t('islandRows')));
  fill('sound-keys', keyRows(t('soundKeys')));
  fill('windows-keys', keyRows(t('windowsKeys')));
  fill('clip-keys', keyRows(t('clipKeys')));
  fill('actions-keys', keyRows(t('actionsKeys')));
  fill('auto-rows', rows(t('autoRows')));
  fill('chrome-rows', rows(t('chromeRows')));
  fill('panel-rows', rows(t('panelRows')));

  const table = h('table', { class: 'net' },
    h('thead', null, h('tr', null, t('privacyHead').map((c) => h('th', { scope: 'col', text: c })))),
    h('tbody', null, t('privacyRows').map(([when, what, where]) => h('tr', null, h('td', { text: when }), h('td', { text: what }), h('td', null, h('code', { text: where }))))));
  fill('privacy-table', table);

  fill('install-steps', h('ol', { class: 'steps' }, t('installSteps').map(([title, body], i) => h('li', null,
    h('span', { class: 'step-num', 'aria-hidden': 'true', text: String(i + 1) }),
    h('div', null, h('h3', { text: title }), h('p', { text: body }),
      i === 1 ? h('a', { class: 'text-link', href: CONFIG.help[lang] || CONFIG.help.en, download: '' }, icon('page', 15), t('installHelp')) : null,
      i === 2 ? h('ul', { class: 'perms' }, t('permissions').map(([name, why]) => h('li', null, h('b', { text: name }), h('span', { text: why })))) : null)))));

  fill('open-may', h('ul', { class: 'terms may' }, t('openMay').map((x) => h('li', null, icon('check', 16), h('span', { text: x })))));
  fill('open-must', h('ul', { class: 'terms must' }, t('openMust').map((x) => h('li', null, icon('arrowRight', 16), h('span', { text: x })))));

  const touch = coarsePointer();
  document.querySelector('.hero-live').textContent = t(touch ? 'heroLiveTouch' : 'heroLive');
  document.querySelector('[data-meta]').textContent = t('heroMeta', CONFIG.version, CONFIG.minOS, CONFIG.size[lang] || CONFIG.size.en);
  document.querySelector('[data-final-meta]').textContent = t('heroMeta', CONFIG.version, CONFIG.minOS, CONFIG.size[lang] || CONFIG.size.en);
  const question = document.querySelector('[data-questions]');
  clear(question).append(...t('finalQuestions', '\u0000').split('\u0000').flatMap((part, i) => i === 0 ? [part] : [h('a', { href: `mailto:${CONFIG.email}`, text: CONFIG.email }), part]));
  document.querySelector('[data-rights]').textContent = t('footerRights', CONFIG.year);
  for (const link of document.querySelectorAll('[data-help]')) link.href = CONFIG.help[lang] || CONFIG.help.en;
}

function wire(desktop) {
  for (const a of document.querySelectorAll('[data-dmg]')) a.href = CONFIG.dmg;
  for (const a of document.querySelectorAll('[data-zip]')) a.href = CONFIG.zip;
  for (const a of document.querySelectorAll('[data-mail]')) { a.href = `mailto:${CONFIG.email}`; if (a.dataset.mail === 'text') a.textContent = CONFIG.email; }
  for (const a of document.querySelectorAll('[data-github]')) {
    if (CONFIG.github) { a.href = CONFIG.github; a.hidden = false; } else a.hidden = true;
  }
  for (const a of document.querySelectorAll('[data-dmg]')) a.addEventListener('click', () => bus.emit('peek', 'download', CONFIG.version));

  // “Show me” scrolls back to the desktop and performs the action there.
  const actions = {
    island: () => desktop.island.expand('home'),
    sound: () => desktop.openPanel('sound'),
    snap: () => { desktop.openWindow('note'); setTimeout(() => desktop.snap('note', 'left'), 120); },
    command: () => desktop.overlays.openCommand(),
    chrome: () => desktop.openBrowser(),
    panel: () => desktop.openPanel('system'),
    automations: () => desktop.openPanel('automations')
  };
  for (const button of document.querySelectorAll('[data-show]')) {
    button.addEventListener('click', () => {
      const run = actions[button.dataset.show];
      if (button.dataset.show === 'command') { run(); return; }
      desktopRoot.scrollIntoView({ behavior: matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth' });
      setTimeout(run, 520);
    });
  }

  const credit = document.querySelector('[data-copy-credit]');
  credit?.addEventListener('click', async () => {
    const ok = await copyText(t('creditLine'));
    if (!ok) return;
    credit.querySelector('span').textContent = t('copied');
    bus.emit('copy', { kind: 'text', text: t('creditLine') });
    setTimeout(() => { credit.querySelector('span').textContent = t('copyCredit'); }, 1800);
  });

  for (const button of document.querySelectorAll('[data-set-lang]')) button.addEventListener('click', () => setLang(button.dataset.setLang));
  const markLang = () => { for (const button of document.querySelectorAll('[data-set-lang]')) button.setAttribute('aria-pressed', String(button.dataset.setLang === lang)); };
  markLang();
  onLang(markLang);
}

function meta() {
  const title = t('metaTitle');
  const description = t('metaDescription');
  document.title = title;
  document.querySelector('meta[name="description"]')?.setAttribute('content', description);
  document.querySelector('meta[property="og:title"]')?.setAttribute('content', title);
  document.querySelector('meta[property="og:description"]')?.setAttribute('content', description);
  document.querySelector('meta[name="twitter:title"]')?.setAttribute('content', title);
  document.querySelector('meta[name="twitter:description"]')?.setAttribute('content', description);
}

apply();
hydrateIcons();
meta();
const desktop = createDesktop(desktopRoot, bus);
renderGuide();
renderPlates(bus);
wire(desktop);
onLang(() => { meta(); renderGuide(); renderPlates(bus); });
document.documentElement.classList.add('ready');
