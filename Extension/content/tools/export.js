(() => {
  if ((window.top !== window && !globalThis.__savisulDemo) || !globalThis.SV) return;
  const SV = globalThis.SV;

  const { h, icon } = SV;
  const I = SV_I18N;
  const t = (...args) => I.t(...args);

  // MARK: HTML → Markdown

  const SKIP = new Set(['script', 'style', 'noscript', 'template', 'svg', 'canvas', 'iframe', 'object', 'embed',
    'button', 'input', 'select', 'textarea', 'form', 'nav', 'dialog', 'savisul-notch']);
  const BLOCK = new Set(['p', 'div', 'section', 'article', 'main', 'header', 'footer', 'aside', 'figure', 'figcaption',
    'ul', 'ol', 'li', 'blockquote', 'pre', 'table', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'hr', 'dl', 'dt', 'dd', 'details', 'summary']);

  const absolute = (value) => {
    try { return new URL(value, location.href).href; } catch { return value || ''; }
  };
  const escapeText = (text) => text.replace(/([\\`*_[\]])/g, '\\$1');
  const squash = (text) => text.replace(/[ \t\r\n ]+/g, ' ');

  function inline(node) {
    let out = '';
    for (const child of node.childNodes) out += inlineOf(child);
    return out;
  }

  function inlineOf(node) {
    if (node.nodeType === 3) return escapeText(squash(node.nodeValue));
    if (node.nodeType !== 1) return '';
    const tag = node.localName;
    if (SKIP.has(tag) || node.hidden || node.getAttribute('aria-hidden') === 'true') return '';
    if (BLOCK.has(tag)) return ` ${block(node).trim()} `;
    switch (tag) {
      case 'br': return '  \n';
      case 'strong': case 'b': { const text = inline(node).trim(); return text ? `**${text}**` : ''; }
      case 'em': case 'i': case 'cite': { const text = inline(node).trim(); return text ? `*${text}*` : ''; }
      case 'del': case 's': case 'strike': { const text = inline(node).trim(); return text ? `~~${text}~~` : ''; }
      case 'code': case 'kbd': case 'samp': {
        const text = node.textContent;
        const fence = text.includes('`') ? '``' : '`';
        return text ? `${fence}${text}${fence}` : '';
      }
      case 'a': {
        const text = inline(node).trim();
        const href = node.getAttribute('href');
        if (!href || href.startsWith('javascript:')) return text;
        if (href.startsWith('#')) return text;
        return text ? `[${text}](${absolute(href)})` : '';
      }
      case 'img': {
        const src = node.currentSrc || node.getAttribute('src');
        if (!src || src.startsWith('data:image/gif')) return '';
        return `![${squash(node.alt || '').trim()}](${absolute(src)})`;
      }
      case 'sup': return `^${inline(node)}`;
      default: return inline(node);
    }
  }

  function list(node, depth) {
    const ordered = node.localName === 'ol';
    let index = Number(node.getAttribute('start')) || 1;
    const lines = [];
    for (const li of node.children) {
      if (li.localName !== 'li') continue;
      const marker = ordered ? `${index++}.` : '-';
      const nested = [];
      const clone = li.cloneNode(true);
      for (const sub of [...clone.querySelectorAll(':scope > ul, :scope > ol')]) sub.remove();
      for (const sub of li.querySelectorAll(':scope > ul, :scope > ol')) nested.push(list(sub, depth + 1));
      const text = block(clone).trim().replace(/\n+/g, ' ');
      lines.push(`${'   '.repeat(depth)}${marker} ${text}`, ...nested);
    }
    return lines.join('\n');
  }

  function cell(node) {
    return inline(node).trim().replace(/\|/g, '\\|').replace(/\n+/g, ' ');
  }

  function table(node) {
    const rows = [...node.querySelectorAll('tr')].filter((tr) => tr.closest('table') === node);
    if (!rows.length) return '';
    const matrix = rows.map((tr) => [...tr.children].filter((c) => c.localName === 'td' || c.localName === 'th').map(cell));
    const width = Math.max(...matrix.map((row) => row.length));
    if (!width) return '';
    const pad = (row) => [...row, ...Array(width - row.length).fill('')];
    const head = pad(matrix[0]);
    const out = [`| ${head.join(' | ')} |`, `| ${head.map(() => '---').join(' | ')} |`];
    for (const row of matrix.slice(1)) out.push(`| ${pad(row).join(' | ')} |`);
    return out.join('\n');
  }

  function block(node) {
    let out = '';
    let buffer = '';
    const flush = () => {
      const text = buffer.replace(/ +\n/g, '\n').replace(/[ \t]+/g, ' ').trim();
      if (text) out += `${text}\n\n`;
      buffer = '';
    };
    for (const child of node.childNodes) {
      if (child.nodeType === 3) { buffer += escapeText(squash(child.nodeValue)); continue; }
      if (child.nodeType !== 1) continue;
      const tag = child.localName;
      if (SKIP.has(tag) || child.hidden || child.getAttribute('aria-hidden') === 'true') continue;
      if (!BLOCK.has(tag)) { buffer += inlineOf(child); continue; }
      flush();
      if (/^h[1-6]$/.test(tag)) {
        const text = inline(child).trim();
        if (text) out += `${'#'.repeat(Number(tag[1]))} ${text}\n\n`;
      } else if (tag === 'ul' || tag === 'ol') {
        const text = list(child, 0);
        if (text.trim()) out += `${text}\n\n`;
      } else if (tag === 'pre') {
        const code = child.querySelector('code');
        const lang = (code?.className.match(/language-([\w-]+)/) || [])[1] || '';
        out += `\`\`\`${lang}\n${child.textContent.replace(/\n$/, '')}\n\`\`\`\n\n`;
      } else if (tag === 'blockquote') {
        const text = block(child).trim();
        if (text) out += `${text.split('\n').map((line) => `> ${line}`).join('\n')}\n\n`;
      } else if (tag === 'table') {
        const text = table(child);
        if (text) out += `${text}\n\n`;
      } else if (tag === 'hr') {
        out += '---\n\n';
      } else if (tag === 'figcaption') {
        const text = inline(child).trim();
        if (text) out += `*${text}*\n\n`;
      } else {
        out += block(child);
      }
    }
    flush();
    return out;
  }

  SV.markdown = (node) => block(node).replace(/\n{3,}/g, '\n\n').trim();

  // MARK: Page digest — what the sidebar's AI reads

  function article() {
    try { return SV.reader?.extract?.() || null; } catch { return null; }
  }

  SV.digest = ({ max = 60000 } = {}) => {
    const found = article();
    let text = found ? (found.body.innerText || found.body.textContent || '') : '';
    if (text.length < 600) text = document.body?.innerText || '';
    text = text.replace(/\n{3,}/g, '\n\n').trim();
    const selection = String(getSelection() || '').trim().slice(0, 8000);
    return {
      title: (found?.title || document.title || '').trim(),
      url: location.href,
      host: SV.host,
      lang: document.documentElement.lang || '',
      description: document.querySelector('meta[name="description"], meta[property="og:description"]')?.content?.trim() || '',
      selection,
      truncated: text.length > max,
      text: text.slice(0, max)
    };
  };

  function pageMarkdown() {
    const found = article();
    const title = (found?.title || document.title || SV.host).trim();
    let body;
    if (found) {
      body = SV.markdown(found.body);
    } else {
      const root = document.querySelector('main, article, [role="main"]') || document.body;
      body = SV.markdown(root);
    }
    const front = [`# ${title}`, '', `<${SV_STORE.cleanUrl(location.href).url}>`];
    if (found?.author) front.push('', `*${found.author}${found.published ? ` · ${found.published}` : ''}*`);
    return { title, text: `${front.join('\n')}\n\n${body}\n` };
  }
  SV.pageMarkdown = pageMarkdown;

  // MARK: Actions

  const fileBase = () => SV.safeName(document.title) || SV.host || 'page';

  function base64(text) {
    const bytes = new TextEncoder().encode(text);
    let binary = '';
    for (let i = 0; i < bytes.length; i += 0x8000) binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
    return btoa(binary);
  }

  async function downloadMarkdown() {
    const { text } = pageMarkdown();
    await SV.send('download', { items: [{ url: `data:text/markdown;charset=utf-8;base64,${base64(text)}`, filename: `SAVISUL/${fileBase()}.md` }] });
    SV.toast(t('exportMdSaved'), { icon: 'markdown' });
  }

  async function copyMarkdown() {
    const { text } = pageMarkdown();
    await SV.copy(text);
    SV.toast(t('exportMdCopied'), { icon: 'copy' });
  }

  function printable() {
    const found = article();
    if (!found) return null;
    const body = found.body.cloneNode(true);
    for (const el of body.querySelectorAll('[src]')) el.setAttribute('src', absolute(el.getAttribute('src')));
    for (const el of body.querySelectorAll('a[href]')) el.setAttribute('href', absolute(el.getAttribute('href')));
    for (const el of body.querySelectorAll('[srcset]')) el.removeAttribute('srcset');
    return {
      title: found.title,
      site: found.site,
      author: found.author,
      published: found.published,
      url: SV_STORE.cleanUrl(location.href).url,
      lang: document.documentElement.lang || I.lang,
      html: body.innerHTML
    };
  }

  async function savePdf() {
    const doc = printable();
    if (doc) {
      await SV.send('print:open', { doc });
      return;
    }
    // No article to clean up: print the page itself.
    SV.notch.close();
    SV.hideUI(true);
    await SV.frames(2);
    window.print();
    SV.hideUI(false);
  }

  async function archive(target) {
    SV.toast(t('exportWorking'), { icon: 'archive', tone: 'info', duration: 6000 });
    try {
      const reply = await SV.send('archive:save', { target, name: fileBase() });
      if (target === 'shelf') SV.toast(t('shelfAdded'), { icon: 'tray' });
      else SV.toast(t('exportArchiveSaved', I.number(Math.max(1, Math.round((reply.bytes || 0) / 1024)))), { icon: 'archive' });
    } catch (error) {
      shelfError(error, 'archive');
    }
  }

  function shelfError(error, iconName = 'tray') {
    const reason = String(error?.message || error);
    const key = reason === 'update' ? 'shelfUpdate' : reason === 'missing' ? 'shelfMissing' : reason === 'offline' ? 'shelfOffline' : 'shelfFailed';
    SV.toast(t(key), { icon: iconName, tone: 'warn', duration: 4200 });
  }

  async function shelf(kind) {
    try {
      if (kind === 'link') {
        await SV.send('shelf:add', { kind: 'link', url: SV_STORE.cleanUrl(location.href).url, title: document.title });
      } else if (kind === 'markdown') {
        const { text } = pageMarkdown();
        await SV.send('shelf:add', { kind: 'file', name: `${fileBase()}.md`, data: base64(text) });
      } else if (kind === 'selection') {
        const text = String(getSelection() || '').trim();
        if (!text) {
          SV.toast(t('shelfNoSelection'), { icon: 'tray', tone: 'warn' });
          return;
        }
        await SV.send('shelf:add', { kind: 'text', text });
      }
      SV.toast(t('shelfAdded'), { icon: 'tray' });
    } catch (error) {
      shelfError(error);
    }
  }
  SV.shelf = shelf;

  function panel(api) {
    const option = (name, title, detail, run, extra) => h('div', { class: 'option-row' },
      h('button', { class: 'option', type: 'button', onclick: run },
        h('span', { class: 'glyph' }, icon(name, 19)),
        h('span', { class: 'grow' }, h('div', { class: 't', text: title }), h('div', { class: 'd', text: detail }))),
      extra || null);

    api.body.append(h('div', { class: 'options' },
      option('markdown', t('exportMd'), t('exportMdDetail'), () => downloadMarkdown(),
        SV.iconButton('copy', t('exportMdCopy'), () => copyMarkdown())),
      option('printer', t('exportPdf'), t('exportPdfDetail'), () => savePdf()),
      option('archive', t('exportArchive'), t('exportArchiveDetail'), () => archive('download'))));

    api.body.append(h('div', { class: 'card' },
      h('div', { class: 'row', style: { 'margin-bottom': '10px' } },
        icon('tray', 17),
        h('span', { class: 'grow', style: { 'font-weight': '600' }, text: t('shelfTitle') }),
        h('span', { class: 'hint', text: t('shelfMac') })),
      h('div', { class: 'row', style: { gap: '6px', 'flex-wrap': 'wrap' } },
        h('button', { class: 'btn small', type: 'button', onclick: () => shelf('link') }, icon('link', 14), t('shelfLink')),
        h('button', { class: 'btn small', type: 'button', onclick: () => shelf('markdown') }, icon('markdown', 14), 'Markdown'),
        h('button', { class: 'btn small', type: 'button', onclick: () => archive('shelf') }, icon('archive', 14), t('shelfArchive')),
        h('button', { class: 'btn small', type: 'button', onclick: () => shelf('selection') }, icon('type', 14), t('shelfSelection')))));
    api.body.querySelector('.option')?.setAttribute('data-autofocus', '');
    return null;
  }

  SV.css += `
.option-row { display: flex; align-items: center; gap: 6px; }
.option-row .option { flex: 1; min-width: 0; }
`;

  SV.tools.export = { label: 'tExport', icon: 'download', kind: 'panel', title: () => t('exportTitle'), panel };
})();
