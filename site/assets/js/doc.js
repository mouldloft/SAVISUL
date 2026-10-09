// Privacy, license and 404 pages: language switch, icons, contents list for the visible language.
import { h, clear } from './dom.js';
import { hydrateIcons } from './icons.js';
import { lang, apply, setLang, onLang } from './i18n.js';
import { CONFIG } from './config.js';

function contents() {
  const toc = document.querySelector('[data-toc]');
  if (!toc) return;
  const article = document.querySelector(`.doc-lang[lang="${lang}"]`) || document.querySelector('.doc-lang');
  const list = h('ol');
  for (const heading of article.querySelectorAll('h2[id]')) list.append(h('li', null, h('a', { href: `#${heading.id}`, text: heading.textContent })));
  clear(toc).append(list);
}

function markLang() {
  for (const button of document.querySelectorAll('[data-set-lang]')) button.setAttribute('aria-pressed', String(button.dataset.setLang === lang));
  const title = document.querySelector(`.doc-lang[lang="${lang}"] h1`);
  if (title) document.title = `${title.textContent} · SAVISUL`;
}

apply();
hydrateIcons();
for (const a of document.querySelectorAll('[data-mail]')) { a.href = `mailto:${CONFIG.email}`; if (a.dataset.mail === 'text') a.textContent = CONFIG.email; }
for (const a of document.querySelectorAll('[data-github]')) { if (CONFIG.github) { a.href = CONFIG.github; a.hidden = false; } }
for (const el of document.querySelectorAll('[data-rights]')) el.textContent = `© ${CONFIG.year} The SAVISUL Authors`;
for (const button of document.querySelectorAll('[data-set-lang]')) button.addEventListener('click', () => setLang(button.dataset.setLang));
contents();
markLang();
onLang(() => { contents(); markLang(); });
