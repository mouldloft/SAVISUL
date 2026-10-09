(async () => {
  const I = SV_I18N;
  const t = (...args) => I.t(...args);
  const { h, icon } = SV;
  const $ = (id) => document.getElementById(id);

  const MAX_SIDE = 32000;
  const MAX_AREA = 250e6;
  const CHUNK = 3 * 1024 * 1024;

  await Page.init();
  document.title = `${t('capTitle')} · SAVISUL`;
  $('brand').append(SV.mark(22), h('span', { text: 'SAVISUL' }));
  const stage = $('stage');
  const actions = $('actions');

  const state = (content, spinner) => {
    SV.clear(stage).append(h('div', { class: 'state' }, spinner ? h('span', { class: 'spinner' }) : null, ...[].concat(content)));
  };

  state(h('div', { text: t('capLoading') }), true);

  const id = decodeURIComponent(location.hash.slice(1));
  const shot = id ? await SV_DB.get('shots', id).catch(() => null) : null;
  if (!shot?.frames?.length) {
    state([icon('camera', 28), h('div', { class: 'big', text: t('capMissing') })]);
    return;
  }

  const meta = shot.meta || {};
  let bitmaps;
  try {
    bitmaps = await Promise.all(shot.frames.map(async (_, index) => {
      const blob = await SV_DB.get('frames', `${id}:${index}`);
      if (!blob) throw new Error('frame');
      return createImageBitmap(blob);
    }));
  } catch {
    state([icon('camera', 28), h('div', { class: 'big', text: t('capMissing') })]);
    return;
  }

  // MARK: Stitch

  const inner = meta.inner || meta.viewport || { w: bitmaps[0].width, h: bitmaps[0].height };
  const scale = bitmaps[0].width / inner.w;
  let source;
  let total;
  if (meta.kind === 'full') {
    source = meta.clip || { x: 0, y: 0, w: meta.viewport?.w || inner.w, h: meta.viewport?.h || inner.h };
    total = { w: source.w, h: meta.total?.h || source.h };
  } else if (meta.kind === 'region' && meta.crop) {
    source = meta.crop;
    total = { w: source.w, h: source.h };
  } else {
    source = { x: 0, y: 0, w: bitmaps[0].width / scale, h: bitmaps[0].height / scale };
    total = { w: source.w, h: source.h };
  }

  const deviceWidth = Math.max(1, Math.round(total.w * scale));
  const deviceHeight = Math.max(1, Math.round(total.h * scale));
  const partLimit = Math.max(1000, Math.min(MAX_SIDE, Math.floor(MAX_AREA / deviceWidth)));
  const count = Math.ceil(deviceHeight / partLimit);
  const partCss = total.h / count;

  const parts = [];
  for (let p = 0; p < count; p++) {
    const top = p * partCss;
    const bottom = p === count - 1 ? total.h : (p + 1) * partCss;
    const canvas = document.createElement('canvas');
    canvas.width = deviceWidth;
    canvas.height = Math.max(1, Math.round((bottom - top) * scale));
    const ctx = canvas.getContext('2d');
    ctx.imageSmoothingQuality = 'high';
    shot.frames.forEach((frame, index) => {
      const start = frame.y || 0;
      const end = start + source.h;
      const from = Math.max(start, top);
      const to = Math.min(end, bottom);
      if (to <= from) return;
      const sx = source.x * scale;
      const sy = (source.y + (from - start)) * scale;
      const sw = Math.min(source.w * scale, bitmaps[index].width - sx);
      const sh = Math.min((to - from) * scale, bitmaps[index].height - sy);
      if (sw <= 0 || sh <= 0) return;
      ctx.drawImage(bitmaps[index], sx, sy, sw, sh, 0, (from - top) * scale, sw, sh);
    });
    parts.push({ canvas, png: null, url: '' });
  }
  bitmaps.forEach((bitmap) => bitmap.close());

  const toBlob = (canvas, type, quality) => new Promise((resolve, reject) => {
    canvas.toBlob((blob) => (blob ? resolve(blob) : reject(new Error('encode'))), type, quality);
  });

  for (const part of parts) {
    part.png = await toBlob(part.canvas, 'image/png');
    part.url = URL.createObjectURL(part.png);
  }

  // MARK: Render

  const host = meta.host || '';
  const stamp = SV.stamp(new Date(shot.created || Date.now()));
  const baseName = SV.safeName(`SAVISUL ${host} ${stamp}`.replace(/\s+/g, ' '));
  const nameFor = (index, ext) => `${baseName}${parts.length > 1 ? ` (${index + 1})` : ''}.${ext}`;

  $('title').textContent = meta.title || host || t('capTitle');
  $('sub').textContent = [host, t('capSize', I.number(deviceWidth), I.number(deviceHeight))].filter(Boolean).join(' · ');

  SV.clear(stage);
  if (parts.length > 1) stage.append(h('div', { class: 'note', text: t('capParts', I.number(parts.length)) }));
  parts.forEach((part, index) => {
    stage.append(h('div', { class: 'part' },
      parts.length > 1 ? h('div', { class: 'label', text: `${index + 1} / ${parts.length}` }) : null,
      h('img', { class: 'shot', src: part.url, alt: meta.title || '', width: String(Math.round(part.canvas.width / scale)), style: { 'animation-delay': `${index * 80}ms` } })));
  });

  // MARK: Actions

  async function download(ext) {
    try {
      for (const [index, part] of parts.entries()) {
        let url = part.url;
        if (ext === 'jpg') {
          const flat = document.createElement('canvas');
          flat.width = part.canvas.width;
          flat.height = part.canvas.height;
          const ctx = flat.getContext('2d');
          ctx.fillStyle = '#ffffff';
          ctx.fillRect(0, 0, flat.width, flat.height);
          ctx.drawImage(part.canvas, 0, 0);
          url = URL.createObjectURL(await toBlob(flat, 'image/jpeg', 0.92));
        }
        await chrome.downloads.download({ url, filename: `SAVISUL/${nameFor(index, ext)}`, conflictAction: 'uniquify', saveAs: false });
      }
      Page.toast(t('capDownloaded'), { icon: 'download' });
    } catch {
      Page.toast(t('capFailed'), { icon: 'download', tone: 'bad' });
    }
  }

  async function copy() {
    try {
      await navigator.clipboard.write([new ClipboardItem({ 'image/png': parts[0].png })]);
      Page.toast(t('capCopied'), { icon: 'copy' });
    } catch {
      Page.toast(t('capFailed'), { icon: 'copy', tone: 'bad' });
    }
  }

  const base64 = (blob) => new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result).split(',')[1] || '');
    reader.onerror = () => reject(reader.error);
    reader.readAsDataURL(blob);
  });

  const bridge = (body, timeout = 20000) => SV.send('bridge:request', { body, timeout });

  async function saveToMac(button) {
    button.disabled = true;
    const label = button.lastChild.textContent;
    button.replaceChildren(h('span', { class: 'spinner' }), label);
    let saved = null;
    try {
      for (const [index, part] of parts.entries()) {
        const token = crypto.randomUUID();
        const chunks = Math.max(1, Math.ceil(part.png.size / CHUNK));
        for (let i = 0; i < chunks; i++) {
          const data = await base64(part.png.slice(i * CHUNK, (i + 1) * CHUNK));
          const reply = await bridge({ type: 'saveChunk', token, index: i, total: chunks, name: nameFor(index, 'png'), data });
          if (reply.error || reply.ok === false) throw new Error(reply.error || 'save');
          if (i === chunks - 1) saved = reply.path || saved;
        }
      }
      Page.toast(t('capSaved'), {
        icon: 'folder',
        action: saved ? { label: t('capReveal'), run: () => bridge({ type: 'reveal', path: saved }, 6000).catch(() => {}) } : null
      });
    } catch (error) {
      const offline = /missing|not found|forbidden|offline|disconnected/i.test(String(error?.message));
      Page.toast(t(offline ? 'capMacOffline' : 'capFailed'), { icon: 'folder', tone: 'warn' });
    } finally {
      button.disabled = false;
      button.replaceChildren(icon('folder', 15), label);
    }
  }

  const button = (name, label, run, primary) => h('button', { class: `btn${primary ? ' primary' : ''}`, type: 'button', onclick: (event) => run(event.currentTarget) }, icon(name, 15), label);
  actions.append(
    button('copy', t('capCopy'), copy),
    button('download', t('capJpg'), () => download('jpg')),
    button('download', t('capPng'), () => download('png'), true));

  SV.send('bridge:status').then((bridgeState) => {
    if (!bridgeState || bridgeState.status === 'missing') return;
    actions.prepend(button('folder', t('capSave'), saveToMac));
  }).catch(() => {});

  addEventListener('keydown', (event) => {
    if (!(event.metaKey || event.ctrlKey)) return;
    const key = event.key.toLowerCase();
    if (key === 's') {
      event.preventDefault();
      download('png');
    } else if (key === 'c' && !String(getSelection())) {
      event.preventDefault();
      copy();
    }
  });
})();
