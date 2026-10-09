(() => {
  // Small Markdown → DOM renderer for model answers. Builds nodes only (no innerHTML), so text
  // from a web page or a model can never become markup; links are limited to http(s).
  const h = (tag, props, ...children) => SV.h(tag, props, ...children);

  function safeHref(href) {
    try {
      const url = new URL(href);
      return /^https?:$/.test(url.protocol) ? url.href : null;
    } catch {
      return null;
    }
  }

  const INLINE = /(`+)([\s\S]*?[^`])\1(?!`)|\*\*([^*]+?)\*\*|__([^_]+?)__|\*([^*\s][^*]*?)\*|_([^_\s][^_]*?)_|~~(.+?)~~|\[([^\]]+)\]\(([^)\s]+)\)|(https?:\/\/[^\s<>()]+[^\s<>().,;:!?'"])/g;

  function inline(text) {
    const out = [];
    let last = 0;
    for (const m of text.matchAll(INLINE)) {
      if (m.index > last) out.push(text.slice(last, m.index));
      if (m[1]) out.push(h('code', { text: m[2] }));
      else if (m[3] || m[4]) out.push(h('strong', null, inline(m[3] || m[4])));
      else if (m[5] || m[6]) out.push(h('em', null, inline(m[5] || m[6])));
      else if (m[7]) out.push(h('del', null, inline(m[7])));
      else if (m[8]) {
        const href = safeHref(m[9]);
        out.push(href ? h('a', { href, target: '_blank', rel: 'noopener noreferrer' }, inline(m[8])) : m[8]);
      } else if (m[10]) {
        const href = safeHref(m[10]);
        out.push(href ? h('a', { href, target: '_blank', rel: 'noopener noreferrer', text: m[10] }) : m[10]);
      }
      last = m.index + m[0].length;
    }
    if (last < text.length) out.push(text.slice(last));
    return out;
  }

  const isTableRow = (line) => /^\s*\|.*\|\s*$/.test(line);
  const isRule = (line) => /^\s*\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?\s*$/.test(line);
  const cells = (line) => line.trim().replace(/^\||\|$/g, '').split(/(?<!\\)\|/).map((c) => c.trim().replace(/\\\|/g, '|'));

  function render(source) {
    const root = h('div', { class: 'md' });
    const lines = String(source || '').replace(/\r\n?/g, '\n').split('\n');
    let i = 0;
    let paragraph = [];
    const flush = () => {
      if (paragraph.length) root.append(h('p', null, inline(paragraph.join(' '))));
      paragraph = [];
    };

    while (i < lines.length) {
      const line = lines[i];

      const fence = line.match(/^\s*(```|~~~)\s*([\w+-]*)/);
      if (fence) {
        flush();
        const body = [];
        i++;
        while (i < lines.length && !lines[i].trim().startsWith(fence[1])) body.push(lines[i++]);
        i++;
        root.append(h('pre', null, h('code', { text: body.join('\n') })));
        continue;
      }

      if (!line.trim()) { flush(); i++; continue; }

      const heading = line.match(/^(#{1,6})\s+(.*)$/);
      if (heading) {
        flush();
        root.append(h(`h${Math.min(4, heading[1].length)}`, null, inline(heading[2].replace(/\s+#+\s*$/, ''))));
        i++;
        continue;
      }

      if (/^\s*([-*_])(\s*\1){2,}\s*$/.test(line)) { flush(); root.append(h('hr')); i++; continue; }

      if (isTableRow(line) && i + 1 < lines.length && isRule(lines[i + 1])) {
        flush();
        const head = cells(line);
        i += 2;
        const rows = [];
        while (i < lines.length && isTableRow(lines[i])) rows.push(cells(lines[i++]));
        root.append(h('table', null,
          h('thead', null, h('tr', null, head.map((c) => h('th', null, inline(c))))),
          h('tbody', null, rows.map((row) => h('tr', null, head.map((_, k) => h('td', null, inline(row[k] || ''))))))));
        continue;
      }

      if (/^\s*>/.test(line)) {
        flush();
        const quote = [];
        while (i < lines.length && /^\s*>/.test(lines[i])) quote.push(lines[i++].replace(/^\s*>\s?/, ''));
        const node = render(quote.join('\n'));
        root.append(h('blockquote', null, ...node.childNodes));
        continue;
      }

      const listMatch = line.match(/^(\s*)([-*+]|\d+[.)])\s+(.*)$/);
      if (listMatch) {
        flush();
        const ordered = /\d/.test(listMatch[2]);
        const list = h(ordered ? 'ol' : 'ul');
        const indent = listMatch[1].length;
        while (i < lines.length) {
          const m = lines[i].match(/^(\s*)([-*+]|\d+[.)])\s+(.*)$/);
          if (!m) {
            if (lines[i].trim() && /^\s{2,}/.test(lines[i]) && list.lastChild) {
              list.lastChild.append(' ', ...inline(lines[i].trim()));
              i++;
              continue;
            }
            break;
          }
          if (m[1].length > indent && list.lastChild) {
            const nested = [];
            while (i < lines.length) {
              const n = lines[i].match(/^(\s*)([-*+]|\d+[.)])\s+(.*)$/);
              if (!n || n[1].length <= indent) break;
              nested.push(lines[i].slice(indent + 2));
              i++;
            }
            list.lastChild.append(...render(nested.join('\n')).childNodes);
            continue;
          }
          if (m[1].length < indent) break;
          const item = h('li');
          const task = m[3].match(/^\[([ xX])\]\s+(.*)$/);
          if (task) item.append(task[1].trim() ? '☑ ' : '☐ ', ...inline(task[2]));
          else item.append(...inline(m[3]));
          list.append(item);
          i++;
        }
        root.append(list);
        continue;
      }

      paragraph.push(line.trim());
      i++;
    }
    flush();
    return root;
  }

  globalThis.SV_MD = { render };
})();
