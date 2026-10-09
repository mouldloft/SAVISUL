(() => {
  if ((window.top !== window && !globalThis.__savisulDemo) || !globalThis.SV) return;
  const SV = globalThis.SV;

  const { h, icon } = SV;
  const I = SV_I18N;
  const t = (...args) => I.t(...args);

  // MARK: Tables

  const text = (el) => (el.innerText || el.textContent || '').replace(/\s+/g, ' ').trim();
  const visible = (el) => {
    const r = el.getBoundingClientRect();
    return r.width > 0 && r.height > 0 && getComputedStyle(el).visibility !== 'hidden';
  };

  function htmlMatrix(table) {
    const rows = [...table.rows].filter((row) => row.closest('table') === table);
    const matrix = [];
    const carry = [];
    rows.forEach((row, r) => {
      const out = [];
      let c = 0;
      for (const cell of row.cells) {
        while (carry[r]?.[c] !== undefined) out[c] = carry[r][c++];
        const value = text(cell);
        const colspan = Math.min(Number(cell.colSpan) || 1, 50);
        const rowspan = Math.min(Number(cell.rowSpan) || 1, 200);
        for (let k = 0; k < colspan; k++) {
          out[c] = k === 0 ? value : '';
          for (let down = 1; down < rowspan; down++) (carry[r + down] ||= [])[c] = '';
          c++;
        }
      }
      while (carry[r]?.[c] !== undefined) out[c] = carry[r][c++];
      matrix.push(out.map((v) => v ?? ''));
    });
    return matrix;
  }

  function ariaMatrix(grid) {
    return [...grid.querySelectorAll('[role="row"]')]
      .filter((row) => row.closest('[role="table"], [role="grid"], [role="treegrid"]') === grid)
      .map((row) => [...row.querySelectorAll('[role="cell"], [role="gridcell"], [role="columnheader"], [role="rowheader"]')].map(text));
  }

  function collectTables() {
    const found = [];
    for (const table of document.querySelectorAll('table')) {
      if (SV.isOurs(table) || !visible(table) || table.parentElement?.closest('table')) continue;
      const matrix = htmlMatrix(table).filter((row) => row.some(Boolean));
      if (matrix.length < 2 || Math.max(...matrix.map((row) => row.length)) < 2) continue;
      found.push({ el: table, matrix, caption: text(table.caption || document.createElement('i')) });
    }
    for (const grid of document.querySelectorAll('[role="table"], [role="grid"], [role="treegrid"]')) {
      if (grid.localName === 'table' || SV.isOurs(grid) || !visible(grid)) continue;
      const matrix = ariaMatrix(grid).filter((row) => row.some(Boolean));
      if (matrix.length < 2) continue;
      found.push({ el: grid, matrix, caption: grid.getAttribute('aria-label') || '' });
    }
    return found.map((entry) => {
      const width = Math.max(...entry.matrix.map((row) => row.length));
      entry.matrix = entry.matrix.map((row) => [...row, ...Array(width - row.length).fill('')]);
      entry.width = width;
      return entry;
    });
  }

  const csvCell = (v) => (/[",\n;]/.test(v) ? `"${v.replace(/"/g, '""')}"` : v);
  const formats = {
    csv: (m) => m.map((row) => row.map(csvCell).join(',')).join('\r\n'),
    tsv: (m) => m.map((row) => row.map((v) => v.replace(/[\t\n]/g, ' ')).join('\t')).join('\n'),
    md: (m) => {
      const esc = (v) => v.replace(/\|/g, '\\|');
      const [head, ...rest] = m;
      return [`| ${head.map(esc).join(' | ')} |`, `| ${head.map(() => '---').join(' | ')} |`, ...rest.map((row) => `| ${row.map(esc).join(' | ')} |`)].join('\n');
    },
    json: (m) => {
      const [head, ...rest] = m;
      const keys = head.map((k, i) => k || `column${i + 1}`);
      return JSON.stringify(rest.map((row) => Object.fromEntries(keys.map((k, i) => [k, row[i]]))), null, 2);
    }
  };

  function base64(textValue) {
    const bytes = new TextEncoder().encode(textValue);
    let binary = '';
    for (let i = 0; i < bytes.length; i += 0x8000) binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
    return btoa(binary);
  }

  async function download(name, content, mime) {
    await SV.send('download', { items: [{ url: `data:${mime};charset=utf-8;base64,${base64(`\ufeff${content}`)}`, filename: `SAVISUL/${name}` }] });
    SV.toast(t('dataDownloaded'), { icon: 'download' });
  }

  async function copy(content, label) {
    await SV.copy(content);
    SV.toast(t('copiedValue', label), { icon: 'copy' });
  }

  let highlight = null;
  function mark(el) {
    highlight?.remove();
    highlight = null;
    if (!el) return;
    const r = el.getBoundingClientRect();
    highlight = SV.overlay('fonts-layer');
    const box = h('div', { class: 'box pinned' });
    box.style.cssText = `left:${r.left}px;top:${r.top}px;width:${r.width}px;height:${r.height}px;`;
    highlight.append(box);
  }

  function tablesView(body) {
    const tables = collectTables();
    if (!tables.length) {
      body.append(h('div', { class: 'card empty', text: t('dataNoTables') }));
      return;
    }
    const base = SV.safeName(document.title) || SV.host || 'table';
    const list = h('div', { class: 'scroll-list' });
    tables.forEach((entry, index) => {
      const name = `${base} — ${t('dataTable')} ${index + 1}`;
      const preview = entry.matrix[0].filter(Boolean).slice(0, 4).join(' · ');
      list.append(h('div', {
        class: 'card data-card', onpointerenter: () => mark(entry.el), onpointerleave: () => mark(null)
      },
      h('div', { class: 'row' },
        icon('table', 17),
        h('div', { class: 'grow' },
          h('div', { class: 'ellipsis', style: { 'font-weight': '600' }, text: entry.caption || `${t('dataTable')} ${index + 1}` }),
          h('div', { class: 'hint ellipsis', text: `${I.plural('dataRows', entry.matrix.length)} × ${I.plural('dataCols', entry.width)}${preview ? ` · ${preview}` : ''}` })),
        SV.iconButton('search', t('dataShow'), () => entry.el.scrollIntoView({ behavior: 'smooth', block: 'center' }))),
      h('div', { class: 'row', style: { gap: '6px', 'margin-top': '10px', 'flex-wrap': 'wrap' } },
        h('button', { class: 'btn small primary', type: 'button', onclick: () => download(`${name}.csv`, formats.csv(entry.matrix), 'text/csv') }, icon('download', 14), 'CSV'),
        h('button', { class: 'btn small', type: 'button', title: t('dataSheetsHint'), onclick: () => copy(formats.tsv(entry.matrix), t('dataForSheets')) }, icon('copy', 14), t('dataForSheets')),
        h('button', { class: 'btn small', type: 'button', onclick: () => copy(formats.md(entry.matrix), 'Markdown') }, 'MD'),
        h('button', { class: 'btn small', type: 'button', onclick: () => copy(formats.json(entry.matrix), 'JSON') }, 'JSON'))));
    });
    body.append(list);
  }

  // MARK: Links and contacts

  function collectLinks() {
    const seen = new Map();
    for (const a of document.querySelectorAll('a[href]')) {
      if (SV.isOurs(a)) continue;
      let url;
      try { url = new URL(a.getAttribute('href'), location.href); } catch { continue; }
      if (!/^https?:$/.test(url.protocol)) continue;
      url.hash = '';
      const href = SV_STORE.cleanUrl(url.href).url;
      if (!seen.has(href)) seen.set(href, { url: href, text: text(a).slice(0, 140), external: url.hostname.replace(/^www\./, '') !== SV.host });
    }
    return [...seen.values()];
  }

  function linksView(body) {
    const links = collectLinks();
    if (!links.length) {
      body.append(h('div', { class: 'card empty', text: t('dataNoLinks') }));
      return;
    }
    let scope = 'all';
    const list = h('div', { class: 'scroll-list compact' });
    const count = h('span', { class: 'hint grow' });
    const current = () => links.filter((l) => scope === 'all' || (scope === 'external') === l.external);
    const render = () => {
      const items = current();
      count.textContent = I.plural('dataLinks', items.length);
      SV.clear(list).append(...items.slice(0, 400).map((l) => h('a', {
        class: 'link-row', href: l.url, target: '_blank', rel: 'noopener', title: l.url
      }, h('span', { class: 'ellipsis', text: l.text || l.url }), h('span', { class: 'hint ellipsis', text: l.url.replace(/^https?:\/\/(www\.)?/, '') }))));
    };
    body.append(
      h('div', { class: 'row' },
        SV.seg([['all', t('dataAll')], ['internal', t('dataInternal')], ['external', t('dataExternal')]], scope, (value) => {
          scope = value;
          body.querySelectorAll('.seg button').forEach((b, i) => b.setAttribute('aria-pressed', String(['all', 'internal', 'external'][i] === scope)));
          render();
        }), count),
      list,
      h('div', { class: 'row', style: { gap: '6px' } },
        h('button', { class: 'btn small primary', type: 'button', onclick: () => copy(current().map((l) => l.url).join('\n'), t('dataLinksLabel')) }, icon('copy', 14), t('dataCopyUrls')),
        h('button', { class: 'btn small', type: 'button', onclick: () => copy(current().map((l) => `- [${(l.text || l.url).replace(/([[\]])/g, '\\$1')}](${l.url})`).join('\n'), 'Markdown') }, 'MD'),
        h('button', { class: 'btn small', type: 'button', onclick: () => download(`${SV.safeName(SV.host)} links.csv`, formats.csv([['text', 'url'], ...current().map((l) => [l.text, l.url])]), 'text/csv') }, icon('download', 14), 'CSV')));
    render();
  }

  function collectContacts() {
    const emails = new Set();
    const phones = new Set();
    for (const a of document.querySelectorAll('a[href^="mailto:" i], a[href^="tel:" i]')) {
      const href = decodeURIComponent(a.getAttribute('href'));
      if (/^mailto:/i.test(href)) emails.add(href.slice(7).split('?')[0].trim().toLowerCase());
      else phones.add(href.slice(4).trim());
    }
    const body = (document.body?.innerText || '').slice(0, 400000);
    for (const match of body.matchAll(/[\w.+-]+@[\w-]+(\.[\w-]+)*\.[a-z]{2,}/gi)) emails.add(match[0].toLowerCase());
    for (const match of body.matchAll(/(?:\+|\b)\d[\d\s().-]{7,}\d\b/g)) {
      const digits = match[0].replace(/\D/g, '');
      if (digits.length >= 9 && digits.length <= 15 && !/^(19|20)\d{6}$/.test(digits)) phones.add(match[0].trim());
    }
    return { emails: [...emails].filter((e) => !/\.(png|jpe?g|gif|webp|svg)$/.test(e)), phones: [...phones] };
  }

  function contactsView(body) {
    const { emails, phones } = collectContacts();
    if (!emails.length && !phones.length) {
      body.append(h('div', { class: 'card empty', text: t('dataNoContacts') }));
      return;
    }
    const group = (title, items, iconName) => items.length ? h('div', { class: 'card' },
      h('div', { class: 'row', style: { 'margin-bottom': '8px' } }, icon(iconName, 16), h('span', { class: 'grow', style: { 'font-weight': '600' }, text: `${title} · ${I.number(items.length)}` }),
        h('button', { class: 'btn small', type: 'button', onclick: () => copy(items.join('\n'), title.toLowerCase()) }, icon('copy', 14), t('copy'))),
      h('div', { class: 'scroll-list compact' }, items.slice(0, 200).map((item) => h('button', {
        class: 'link-row', type: 'button', onclick: () => copy(item, item)
      }, h('span', { class: 'mono ellipsis', text: item }))))) : null;
    SV.append(body, [group(t('dataEmails'), emails, 'mail'), group(t('dataPhones'), phones, 'hash')]);
  }

  // MARK: Panel

  let view = 'tables';
  function panel(api) {
    const content = h('div', { class: 'panel-stack' });
    const views = { tables: tablesView, links: linksView, contacts: contactsView };
    const show = (next) => {
      view = next;
      mark(null);
      SV.clear(content);
      views[view](content);
      api.refit();
    };
    const tabs = SV.seg([['tables', t('dataTables')], ['links', t('dataLinksLabel')], ['contacts', t('dataContacts')]], view, (next) => {
      tabs.querySelectorAll('button').forEach((b, i) => b.setAttribute('aria-pressed', String(['tables', 'links', 'contacts'][i] === next)));
      show(next);
    });
    api.body.append(tabs, content);
    show(view);
    return () => mark(null);
  }

  SV.css += `
.panel-stack { display: flex; flex-direction: column; gap: 8px; }
.scroll-list { display: flex; flex-direction: column; gap: 8px; max-height: min(52vh, 460px); overflow-y: auto; overscroll-behavior: contain; margin: 0 -4px; padding: 0 4px; }
.scroll-list.compact { gap: 1px; max-height: min(38vh, 300px); }
.data-card { transition: box-shadow 0.15s ease; }
.data-card:hover { box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--accent) 60%, transparent); }
.link-row { display: flex; flex-direction: column; gap: 1px; padding: 6px 8px; border-radius: 9px; border: 0; background: transparent; color: var(--ink); text-decoration: none; text-align: left; cursor: pointer; min-width: 0; width: 100%; font: inherit; }
.link-row:hover { background: var(--tile-hover); }
.link-row .hint { font-size: 11px; }
`;

  SV.tools.tables = { label: 'tData', icon: 'table', kind: 'panel', title: () => t('dataTitle'), panel };
})();
