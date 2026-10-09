(() => {
  if ((window.top !== window && !globalThis.__savisulDemo) || !globalThis.SV) return;
  const SV = globalThis.SV;

  const { h, icon } = SV;
  const I = SV_I18N;
  const t = (...args) => I.t(...args);

  function highlighted(original, clean) {
    const node = h('div', { class: 'url' });
    let url;
    try { url = new URL(original); } catch {
      node.textContent = original;
      return node;
    }
    const kept = new URL(clean);
    const base = `${url.origin}${url.pathname}`;
    node.append(base.length > 140 ? `${base.slice(0, 139)}…` : base);
    let first = true;
    for (const [key, value] of url.searchParams) {
      const text = `${first ? '?' : '&'}${key}=${value}`;
      first = false;
      if (kept.searchParams.has(key)) node.append(text.length > 80 ? `${text.slice(0, 79)}…` : text);
      else node.append(h('mark', { text: text.length > 60 ? `${text.slice(0, 59)}…` : text }));
    }
    if (url.hash) node.append(url.hash.length > 40 ? `${url.hash.slice(0, 39)}…` : url.hash);
    return node;
  }

  function panel(api) {
    const { url: clean, removed } = SV_STORE.cleanUrl(location.href);
    const title = document.title.trim() || SV.host;
    const markdown = `[${title.replace(/([\\[\]])/g, '\\$1')}](${clean})`;
    const copy = async (text, label) => {
      await SV.copy(text);
      SV.toast(t('copiedValue', label), { icon: 'copy' });
    };

    api.body.append(h('div', { class: 'card' },
      h('div', { style: { 'font-weight': '600', 'margin-bottom': '6px', 'line-height': '1.35' }, text: title.length > 140 ? `${title.slice(0, 139)}…` : title }),
      highlighted(location.href, clean),
      h('div', { class: 'hint', style: { 'margin-top': '6px' }, text: removed ? t('linkRemoved', I.number(removed)) : t('linkNoTrackers') })));

    api.body.append(h('div', { class: 'row', style: { gap: '6px', 'flex-wrap': 'wrap' } },
      h('button', { class: 'btn primary', type: 'button', 'data-autofocus': '', onclick: () => copy(clean, t('linkClean').toLowerCase()) }, icon('link', 15), t('linkClean')),
      h('button', { class: 'btn', type: 'button', onclick: () => copy(markdown, 'Markdown') }, icon('lines', 15), t('linkMarkdown')),
      h('button', { class: 'btn', type: 'button', onclick: () => copy(title, t('linkTitleCopy').toLowerCase()) }, icon('type', 15), t('linkTitleCopy'))));

    const canvas = h('canvas', { class: 'qr', width: '132', height: '132' });
    const code = SV_QR.draw(canvas, clean, { scale: 8, margin: 3 });
    if (code) {
      api.body.append(h('div', { class: 'card qr-wrap' },
        canvas,
        h('div', { class: 'grow' },
          h('div', { style: { 'font-weight': '600', 'margin-bottom': '4px' }, text: t('linkQr') }),
          h('div', { class: 'hint', text: SV.host }),
          h('div', { class: 'row', style: { gap: '6px', 'margin-top': '12px' } },
            h('button', {
              class: 'btn small', type: 'button', onclick: () => SV.send('download', {
                items: [{ url: canvas.toDataURL('image/png'), filename: `SAVISUL/QR ${SV.safeName(SV.host)} ${SV.stamp()}.png` }]
              })
            }, icon('download', 14), t('linkSaveQr')),
            h('button', {
              class: 'btn small', type: 'button', onclick: () => canvas.toBlob(async (blob) => {
                try {
                  await navigator.clipboard.write([new ClipboardItem({ 'image/png': blob })]);
                  SV.toast(t('copied'), { icon: 'qr' });
                } catch {
                  SV.toast(t('shotFailed'), { icon: 'qr', tone: 'warn' });
                }
              })
            }, icon('copy', 14), t('copy'))))));
    } else {
      api.body.append(h('div', { class: 'card hint', text: t('linkTooLong') }));
    }
    return null;
  }

  SV.tools.link = { label: 'tLink', icon: 'link', kind: 'panel', title: () => t('linkTitle'), panel };
})();
