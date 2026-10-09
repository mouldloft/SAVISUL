(() => {
  if ((window.top !== window && !globalThis.__savisulDemo) || !globalThis.SV) return;
  const SV = globalThis.SV;

  const { h, icon } = SV;
  const I = SV_I18N;
  const t = (...args) => I.t(...args);

  const NEGATIVE = /(^|[\s_-])(comments?|meta|footer|footnotes?|share|sharing|social|related|recommend\w*|sidebar|side-bar|aside|promo\w*|sponsor\w*|advert\w*|ads?|adv|banner|breadcrumbs?|newsletter|subscribe|subscription|signup|cookies?|consent|popup|modal|navbar|nav|menu|masthead|toolbar|tags?|author-bio|widget|outbrain|taboola|disqus|rating|pagination|pager|print|login|more-stories|read-more|trending|most-popular)([\s_-]|$)/i;
  const POSITIVE = /(article|body|content|entry|hentry|main|page|post|text|blog|story|prose|markdown|rich-?text)/i;
  // The reader header already shows author, date and reading time.
  const BYLINE = /(^|[\s_-])(byline|dateline|author|authors|posted-on|published|timestamp|article-meta|entry-meta|post-meta)([\s_-]|$)/i;
  const DROP = new Set(['script', 'style', 'noscript', 'template', 'link', 'meta', 'form', 'input', 'button', 'select', 'textarea', 'nav', 'footer', 'aside', 'dialog', 'svg', 'canvas', 'object', 'embed', 'audio', 'map', 'header']);
  const KEEP = new Set(['p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'ul', 'ol', 'li', 'blockquote', 'pre', 'code', 'em', 'strong', 'b', 'i', 'u', 's',
    'a', 'figure', 'figcaption', 'table', 'thead', 'tbody', 'tfoot', 'tr', 'td', 'th', 'caption', 'hr', 'br', 'sup', 'sub', 'small', 'mark',
    'dl', 'dt', 'dd', 'kbd', 'abbr', 'time', 'del', 'ins', 'q', 'cite', 'details', 'summary', 'var', 'samp']);
  const EMBEDS = /(youtube(-nocookie)?\.com\/embed|player\.vimeo\.com|rutube\.ru\/play\/embed|vk\.com\/video_ext|dailymotion\.com\/embed|codepen\.io|platform\.twitter\.com)/;

  const textOf = (el) => (el.textContent || '').replace(/\s+/g, ' ').trim();

  function linkDensity(el) {
    const total = textOf(el).length || 1;
    let links = 0;
    el.querySelectorAll('a').forEach((a) => { links += textOf(a).length; });
    return links / total;
  }

  function classWeight(el) {
    const name = `${typeof el.className === 'string' ? el.className : ''} ${el.id || ''}`;
    let weight = 0;
    if (NEGATIVE.test(name)) weight -= 25;
    if (POSITIVE.test(name)) weight += 25;
    return weight;
  }

  function score() {
    const scores = new Map();
    const base = (el) => {
      if (scores.has(el)) return;
      let value = classWeight(el);
      switch (el.localName) {
        case 'article': value += 12; break;
        case 'main': value += 8; break;
        case 'div': case 'section': value += 5; break;
        case 'pre': case 'td': case 'blockquote': value += 3; break;
        case 'form': case 'ol': case 'ul': case 'dl': value -= 3; break;
        case 'h1': case 'h2': case 'h3': case 'th': value -= 5; break;
      }
      scores.set(el, value);
    };
    const add = (el, value) => {
      if (!el || el === document.documentElement) return;
      base(el);
      scores.set(el, scores.get(el) + value);
    };
    for (const node of document.body.querySelectorAll('p, pre, blockquote, td, div, section')) {
      if (SV.isOurs(node)) continue;
      if (node.localName === 'div' || node.localName === 'section') {
        const own = [...node.childNodes].filter((c) => c.nodeType === 3).map((c) => c.nodeValue).join(' ').trim();
        if (own.length < 100) continue;
      }
      const text = textOf(node);
      if (text.length < 25) continue;
      const value = 1 + text.split(/[,，、;]/).length + Math.min(Math.floor(text.length / 100), 3);
      const parent = node.parentElement;
      add(parent, value);
      add(parent?.parentElement, value / 2);
      add(parent?.parentElement?.parentElement, value / 3);
    }
    let top = null;
    let best = 0;
    for (const [el, value] of scores) {
      const final = value * (1 - linkDensity(el));
      scores.set(el, final);
      if (final > best) {
        best = final;
        top = el;
      }
    }
    const articles = [...document.querySelectorAll('article')].filter((a) => !SV.isOurs(a) && textOf(a).length > 600);
    if (articles.length === 1 && top && !articles[0].contains(top)) top = articles[0];
    return { top, best, scores };
  }

  function image(img) {
    let src = img.currentSrc || img.src;
    const lazy = img.dataset.src || img.dataset.lazySrc || img.dataset.original || img.dataset.url || img.getAttribute('data-lazy');
    if ((!src || src.startsWith('data:')) && lazy) {
      try { src = new URL(lazy, location.href).href; } catch {}
    }
    if (!src) return null;
    const width = img.naturalWidth || img.width;
    const height = img.naturalHeight || img.height;
    if (width && height && width < 48 && height < 48) return null;
    const out = h('img', { src, alt: img.alt || '', loading: 'lazy', decoding: 'async' });
    const srcset = img.getAttribute('srcset') || img.dataset.srcset;
    if (srcset && !srcset.startsWith('data:')) out.setAttribute('srcset', srcset);
    if (img.sizes) out.setAttribute('sizes', img.sizes);
    if (width && height) {
      out.setAttribute('width', width);
      out.setAttribute('height', height);
    }
    return out;
  }

  function clean(node, depth = 0) {
    if (node.nodeType === Node.TEXT_NODE) return document.createTextNode(node.nodeValue);
    if (node.nodeType !== Node.ELEMENT_NODE || SV.isOurs(node)) return null;
    const el = node;
    const tag = el.localName;
    if (DROP.has(tag) && !(tag === 'header' && depth === 0)) return null;
    if (tag === 'iframe') {
      return EMBEDS.test(el.src) ? h('iframe', { src: el.src, allowfullscreen: true, loading: 'lazy', allow: 'autoplay; encrypted-media; picture-in-picture; fullscreen', style: { width: '100%', 'aspect-ratio': '16 / 9' } }) : null;
    }
    if (el.hidden || (el.getAttribute('aria-hidden') === 'true' && !el.querySelector('img'))) return null;
    if (el.checkVisibility && !el.checkVisibility({ checkVisibilityCSS: true }) && tag !== 'img') return null;
    if (depth > 0) {
      const weight = classWeight(el);
      if (weight < 0 && (textOf(el).length < 300 || linkDensity(el) > 0.3)) return null;
      if (BYLINE.test(`${el.className} ${el.id}`) && textOf(el).length < 160) return null;
      if (['div', 'section', 'ul', 'ol', 'table'].includes(tag)) {
        const text = textOf(el);
        if (text.length < 140 && linkDensity(el) > 0.5 && !el.querySelector('img')) return null;
      }
    }
    if (tag === 'img') return image(el);
    if (tag === 'picture') {
      const img = el.querySelector('img');
      return img ? image(img) : null;
    }
    if (tag === 'video') {
      const src = el.currentSrc || el.src || el.querySelector('source')?.src;
      if (src && !src.startsWith('blob:')) return h('video', { src, controls: true, preload: 'metadata', poster: el.poster || null });
      return el.poster ? h('img', { src: el.poster, alt: '' }) : null;
    }
    let out;
    if (KEEP.has(tag)) out = document.createElement(tag);
    else out = document.createElement(getComputedStyle(el).display.startsWith('inline') ? 'span' : 'div');
    if (tag === 'a') {
      const href = el.href;
      if (href && !/^javascript:/i.test(href)) {
        out.setAttribute('href', href);
        out.setAttribute('target', '_blank');
        out.setAttribute('rel', 'noopener noreferrer');
      }
    }
    if (tag === 'td' || tag === 'th') {
      if (el.colSpan > 1) out.setAttribute('colspan', el.colSpan);
      if (el.rowSpan > 1) out.setAttribute('rowspan', el.rowSpan);
    }
    if (tag === 'ol' && el.getAttribute('start')) out.setAttribute('start', el.getAttribute('start'));
    if (tag === 'details' && el.open) out.setAttribute('open', '');
    for (const child of el.childNodes) {
      const copy = clean(child, depth + 1);
      if (copy) out.append(copy);
    }
    if (!['br', 'hr', 'td', 'th'].includes(tag) && !out.textContent.trim() && !out.querySelector('img, video, iframe')) return null;
    return out;
  }

  const meta = (name) => document.querySelector(`meta[property="${name}"], meta[name="${name}"]`)?.content?.trim() || '';

  function extract() {
    if (!document.body) return null;
    const { top, best, scores } = score();
    if (!top) return null;
    const threshold = Math.max(10, best * 0.2);
    const parts = [];
    const parent = top.parentElement;
    if (parent && top.localName !== 'article' && top.localName !== 'main') {
      for (const sibling of parent.children) {
        if (sibling === top) { parts.push(sibling); continue; }
        if ((scores.get(sibling) || 0) >= threshold) { parts.push(sibling); continue; }
        if (sibling.localName === 'p') {
          const text = textOf(sibling);
          const density = linkDensity(sibling);
          if ((text.length > 80 && density < 0.25) || (text.length > 0 && density === 0 && /\.( |$)/.test(text))) parts.push(sibling);
        }
      }
    } else {
      parts.push(top);
    }

    const body = h('div', { class: 'r-body' });
    for (const part of parts) {
      const copy = clean(part, 0);
      if (copy) body.append(copy);
    }

    const h1 = top.querySelector('h1') || document.querySelector('h1');
    const title = meta('og:title') || meta('twitter:title') || (h1 ? textOf(h1) : '') || document.title;
    for (const heading of body.querySelectorAll('h1, h2')) {
      if (textOf(heading).toLowerCase() === title.toLowerCase()) {
        heading.remove();
        break;
      }
    }
    const text = textOf(body);
    if (text.length < 250) return null;

    let author = meta('author') || meta('article:author') || textOf(document.querySelector('[rel="author"], [itemprop="author"], .byline, .author') || document.createElement('i'));
    if (author.length > 80 || /^https?:/.test(author)) author = '';
    let published = '';
    const stamp = meta('article:published_time') || document.querySelector('time[datetime]')?.getAttribute('datetime');
    if (stamp) {
      const date = new Date(stamp);
      if (!Number.isNaN(date.getTime())) published = new Intl.DateTimeFormat(I.locale, { dateStyle: 'long' }).format(date);
    }
    const cjk = (text.match(/[\u3040-\u30ff\u3400-\u9fff]/g) || []).length;
    const minutes = Math.max(1, Math.round(cjk > text.length / 3 ? text.length / 500 : text.split(/\s+/).length / 220));
    return { title, site: meta('og:site_name') || SV.host, author, published, minutes, body };
  }

  // MARK: Overlay

  let overlay = null;
  let removeKey = null;
  let savedOverflow = null;

  function themeFor(choice) {
    if (choice !== 'auto') return choice;
    return matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
  }

  function applyPrefs() {
    const prefs = SV.settings.reader;
    overlay.dataset.theme = themeFor(prefs.theme);
    overlay.dataset.font = prefs.font;
    overlay.style.setProperty('--r-size', `${prefs.size}px`);
    overlay.style.setProperty('--r-width', `${prefs.width}px`);
    overlay.querySelectorAll('[data-pref]').forEach((button) => {
      const [key, value] = button.dataset.pref.split(':');
      button.setAttribute('aria-pressed', String(String(prefs[key]) === value || (key === 'theme' && themeFor(prefs.theme) === value)));
    });
  }

  function setPref(patch) {
    SV.settings.reader = { ...SV.settings.reader, ...patch };
    SV_STORE.save({ reader: SV.settings.reader });
    applyPrefs();
  }

  function open() {
    if (overlay) return;
    const article = extract();
    if (!article) {
      SV.toast(t('readerNone'), { icon: 'book', tone: 'warn' });
      return;
    }
    overlay = SV.overlay('reader');
    overlay.tabIndex = -1;
    const progress = h('div', { class: 'r-progress' });
    const metaLine = h('div', { class: 'r-meta' },
      article.author ? h('span', { text: article.author }) : null,
      article.published ? h('span', { text: article.published }) : null,
      h('span', { text: t('readerMinutes', I.number(article.minutes)) }));
    const page = h('article', null,
      h('div', { class: 'r-site', text: article.site }),
      h('h1', { class: 'r-title', text: article.title }),
      metaLine,
      article.body);

    const button = (content, title, onClick, pref) => h('button', {
      class: 'tbtn', type: 'button', title, 'aria-label': title, onclick: onClick, 'data-pref': pref || null
    }, content);
    const dot = (color) => h('span', { class: 'theme-dot', style: { background: color } });
    const bar = h('div', { class: 'r-bar' },
      button(h('span', { text: 'A', style: { 'font-size': '12px' } }), t('readerSmaller'), () => setPref({ size: Math.max(15, SV.settings.reader.size - 1) })),
      button(h('span', { text: 'A', style: { 'font-size': '17px' } }), t('readerLarger'), () => setPref({ size: Math.min(30, SV.settings.reader.size + 1) })),
      h('span', { class: 'sep' }),
      button(h('span', { text: 'Aa', style: { 'font-family': 'Georgia, serif' } }), t('readerSerif'), () => setPref({ font: 'serif' }), 'font:serif'),
      button(h('span', { text: 'Aa' }), t('readerSans'), () => setPref({ font: 'sans' }), 'font:sans'),
      h('span', { class: 'sep' }),
      button(dot('#f8f5ef'), t('readerLight'), () => setPref({ theme: 'light' }), 'theme:light'),
      button(dot('#f3ead6'), t('readerSepia'), () => setPref({ theme: 'sepia' }), 'theme:sepia'),
      button(dot('#161514'), t('readerDark'), () => setPref({ theme: 'dark' }), 'theme:dark'),
      h('span', { class: 'sep' }),
      button(icon('width', 17), t('readerWidth'), () => {
        const widths = [620, 700, 820];
        const next = widths[(widths.indexOf(SV.settings.reader.width) + 1) % widths.length] || 700;
        setPref({ width: next });
      }),
      button(icon('x', 17), t('readerExit'), () => close()));
    overlay.append(progress, page, bar);
    applyPrefs();

    let lastTop = 0;
    overlay.addEventListener('scroll', () => {
      const max = overlay.scrollHeight - overlay.clientHeight;
      overlay.style.setProperty('--progress', max > 0 ? String(overlay.scrollTop / max) : '0');
      const down = overlay.scrollTop > lastTop + 4;
      const up = overlay.scrollTop < lastTop - 4;
      if (down && overlay.scrollTop > 200) bar.classList.add('away');
      if (up) bar.classList.remove('away');
      lastTop = overlay.scrollTop;
    }, { passive: true });
    overlay.addEventListener('mousemove', (event) => {
      if (event.clientY > innerHeight - 120) bar.classList.remove('away');
    }, { passive: true });

    savedOverflow = document.documentElement.style.getPropertyValue('overflow');
    document.documentElement.style.setProperty('overflow', 'hidden', 'important');
    removeKey = SV.onKey((event) => {
      if (event.key === 'Escape' && SV.notch.view !== 'panel' && SV.notch.view !== 'home') {
        close();
        return true;
      }
      return false;
    });
    requestAnimationFrame(() => {
      overlay.classList.add('on');
      overlay.focus({ preventScroll: true });
    });
    SV.notch.indicate('live', true);
  }

  function close() {
    if (!overlay) return;
    const el = overlay;
    overlay = null;
    el.classList.remove('on');
    setTimeout(() => el.remove(), 360);
    removeKey?.();
    removeKey = null;
    if (savedOverflow) document.documentElement.style.setProperty('overflow', savedOverflow);
    else document.documentElement.style.removeProperty('overflow');
    SV.notch.indicate('live', !!SV.notch.mode);
  }

  SV.reader = { extract, text: () => {
    const article = extract();
    return article ? `${article.title}. ${article.body.innerText || article.body.textContent}` : '';
  } };

  SV.tools.reader = {
    label: 'tReader',
    icon: 'book',
    kind: 'overlay',
    active: () => !!overlay,
    start: open,
    stop: close,
    scroller: () => overlay
  };
})();
