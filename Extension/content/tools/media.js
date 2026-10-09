(() => {
  if ((window.top !== window && !globalThis.__savisulDemo) || !globalThis.SV) return;
  const SV = globalThis.SV;

  const { h, icon } = SV;
  const I = SV_I18N;
  const t = (...args) => I.t(...args);
  const SPEEDS = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 3];

  // MARK: Video

  const videos = () => [...document.querySelectorAll('video')].filter((v) => v.isConnected && (v.readyState > 0 || v.currentSrc || v.src));

  function mainVideo() {
    let best = null;
    let bestScore = -1;
    for (const video of videos()) {
      const r = video.getBoundingClientRect();
      const visible = Math.max(0, Math.min(r.right, innerWidth) - Math.max(r.left, 0)) * Math.max(0, Math.min(r.bottom, innerHeight) - Math.max(r.top, 0));
      const score = visible + (video.paused ? 0 : 1e7) + (document.pictureInPictureElement === video ? 2e7 : 0);
      if (score > bestScore) {
        best = video;
        bestScore = score;
      }
    }
    return best;
  }

  const rateLabel = (rate) => `${I.number(rate, 2, 0)}×`;
  let ownChange = 0;

  function setRate(video, rate) {
    rate = Math.round(SV.clamp(rate, 0.25, 4) * 100) / 100;
    ownChange = Date.now();
    video.playbackRate = rate;
    video.defaultPlaybackRate = rate;
    if (SV.settings.videoSpeed?.[SV.host]) saveSpeed(rate);
    return rate;
  }

  function saveSpeed(rate) {
    const map = { ...(SV.settings.videoSpeed || {}) };
    if (rate == null) delete map[SV.host];
    else map[SV.host] = rate;
    SV.settings.videoSpeed = map;
    SV_STORE.save({ videoSpeed: map });
  }

  function keepSpeed() {
    const enforce = (event) => {
      const kept = SV.settings?.videoSpeed?.[SV.host];
      const video = event.target;
      if (!kept || !(video instanceof HTMLVideoElement)) return;
      if (event.type === 'ratechange') {
        if (Date.now() - ownChange > 400 && video.playbackRate !== kept && video.playbackRate !== 0) saveSpeed(video.playbackRate);
        return;
      }
      if (video.playbackRate !== kept) {
        ownChange = Date.now();
        video.playbackRate = kept;
      }
    };
    for (const type of ['play', 'loadedmetadata', 'ratechange']) SV.listen(document, type, enforce, true);
  }

  function videoPanel(api) {
    const render = () => {
      SV.clear(api.body);
      const video = mainVideo();
      if (!video) {
        api.body.append(h('div', { class: 'card empty', text: t('videoNone') }));
        api.refit();
        return;
      }
      const rate = video.playbackRate;
      api.body.append(h('div', { class: 'card' },
        h('div', { class: 'row', style: { 'justify-content': 'center', gap: '14px', margin: '2px 0 12px' } },
          SV.iconButton('minus', '−0.1', () => { setRate(video, video.playbackRate - 0.1); render(); }),
          h('div', { class: 'big-rate', text: rateLabel(rate) }),
          SV.iconButton('plus', '+0.1', () => { setRate(video, video.playbackRate + 0.1); render(); })),
        h('div', { class: 'speeds' }, SPEEDS.map((speed) => h('button', {
          type: 'button', 'aria-pressed': String(Math.abs(rate - speed) < 0.001),
          onclick: () => { setRate(video, speed); render(); }
        }, rateLabel(speed))))));
      const pip = document.pictureInPictureEnabled;
      api.body.append(h('div', { class: 'row', style: { gap: '6px' } },
        pip ? h('button', {
          class: 'btn', type: 'button', onclick: async () => {
            try {
              if (document.pictureInPictureElement) await document.exitPictureInPicture();
              else {
                video.removeAttribute('disablepictureinpicture');
                video.disablePictureInPicture = false;
                await video.requestPictureInPicture();
              }
            } catch {
              SV.toast(t('shotFailed'), { icon: 'pip', tone: 'warn' });
            }
            render();
          }
        }, icon('pip', 15), t('videoPip')) : null,
        h('button', {
          class: `btn${video.loop ? ' primary' : ''}`, type: 'button', 'aria-pressed': String(video.loop),
          onclick: () => { video.loop = !video.loop; render(); }
        }, icon('loop', 15), t('videoLoop'))));
      api.body.append(h('div', { class: 'card', style: { padding: '4px 12px' } },
        h('div', { class: 'setting' },
          h('span', { class: 'name ellipsis', text: t('videoKeep', SV.host) }),
          SV.toggleSwitch(!!SV.settings.videoSpeed?.[SV.host], t('videoKeep', SV.host), (on) => saveSpeed(on ? video.playbackRate : null)))));
      const count = videos().length;
      if (count > 1) api.body.append(h('div', { class: 'hint', text: t('videoMany', I.number(count)) }));
      api.refit();
    };
    render();
    return null;
  }

  // MARK: Images

  function collectImages() {
    const found = new Map();
    const add = (raw, width, height, alt, el) => {
      if (!raw) return;
      let url;
      try { url = new URL(raw, location.href).href; } catch { return; }
      if (!/^(https?:|data:image\/|blob:)/.test(url)) return;
      if (url.startsWith('data:image/gif') && url.length < 200) return;
      const entry = found.get(url);
      if (!entry || width * height > entry.width * entry.height) found.set(url, { url, width: width || 0, height: height || 0, alt: alt || '', el });
    };
    for (const img of document.images) {
      if (SV.isOurs(img)) continue;
      add(img.currentSrc || img.src, img.naturalWidth, img.naturalHeight, img.alt, img);
    }
    for (const video of document.querySelectorAll('video[poster]')) add(video.poster, 0, 0, '', video);
    for (const image of document.querySelectorAll('svg image')) add(image.href?.baseVal || image.getAttribute('href'), 0, 0, '', image);
    const og = document.querySelector('meta[property="og:image"]')?.content;
    if (og) add(og, 0, 0, 'og:image', null);
    let count = 0;
    for (const el of document.body?.querySelectorAll('*') || []) {
      if (++count > 5000) break;
      if (SV.isOurs(el)) continue;
      const bg = getComputedStyle(el).backgroundImage;
      if (!bg || bg === 'none' || !bg.includes('url(')) continue;
      for (const match of bg.matchAll(/url\(["']?([^"')]+)["']?\)/g)) add(match[1], 0, 0, '', el);
    }
    return [...found.values()];
  }

  function fileName(item, index) {
    if (item.url.startsWith('data:')) {
      const ext = (item.url.match(/^data:image\/([a-z0-9+]+)/i)?.[1] || 'png').replace('jpeg', 'jpg').replace('svg+xml', 'svg');
      return `image-${index + 1}.${ext}`;
    }
    try {
      const path = decodeURIComponent(new URL(item.url).pathname.split('/').pop() || '');
      const clean = SV.safeName(path).replace(/\s/g, '-');
      if (clean && /\.[a-z0-9]{2,5}$/i.test(clean)) return clean;
      return `${clean || 'image'}-${index + 1}.jpg`;
    } catch {
      return `image-${index + 1}.jpg`;
    }
  }

  async function downloadable(url) {
    if (!url.startsWith('blob:')) return url;
    const blob = await (await fetch(url)).blob();
    return new Promise((resolve) => {
      const reader = new FileReader();
      reader.onload = () => resolve(reader.result);
      reader.readAsDataURL(blob);
    });
  }

  let gallery = null;
  let removeGalleryKey = null;
  let savedOverflow = '';

  function openGallery() {
    if (gallery) return;
    const all = collectImages();
    gallery = SV.overlay('gallery');
    const grid = h('div', { class: 'g-grid' });
    const title = h('span', { class: 'g-title grow' });
    const download = async (items) => {
      const prepared = [];
      for (const [index, item] of items.entries()) {
        try { prepared.push({ url: await downloadable(item.url), filename: `SAVISUL/${SV.safeName(SV.host) || 'page'}/${fileName(item, index)}` }); } catch {}
      }
      if (!prepared.length) return;
      await SV.send('download', { items: prepared });
      SV.toast(t('imagesStarted', I.plural('imagesCount', prepared.length)), { icon: 'download' });
    };
    const visibleItems = () => all.filter((item) => !SV.settings.imagesHideSmall || !item.width || (item.width >= 80 && item.height >= 80));

    const render = () => {
      const items = visibleItems();
      title.textContent = `${t('imagesTitle')} · ${I.plural('imagesCount', items.length)}`;
      SV.clear(grid);
      if (!items.length) {
        grid.append(h('div', { class: 'empty', style: { 'grid-column': '1 / -1' }, text: t('imagesNone') }));
        return;
      }
      for (const [index, item] of items.entries()) {
        const size = h('span', { class: 'grow', text: item.width ? `${item.width} × ${item.height}` : '…' });
        const img = h('img', { src: item.url, alt: item.alt, loading: 'lazy', decoding: 'async', referrerpolicy: 'no-referrer-when-downgrade' });
        img.addEventListener('load', () => {
          if (!item.width) {
            item.width = img.naturalWidth;
            item.height = img.naturalHeight;
            size.textContent = `${item.width} × ${item.height}`;
          }
        });
        const card = h('div', { class: 'g-card', title: item.alt || item.url, onclick: () => SV.send('open', { url: item.url }) },
          img,
          h('div', { class: 'g-info' }, size,
            SV.iconButton('download', t('download'), (event) => { event.stopPropagation(); download([item]); }),
            SV.iconButton('external', t('open'), (event) => { event.stopPropagation(); SV.send('open', { url: item.url }); })));
        grid.append(card);
      }
    };

    gallery.append(
      h('div', { class: 'g-head' },
        title,
        h('span', { class: 'hint', text: t('imagesSmall') }),
        SV.toggleSwitch(SV.settings.imagesHideSmall, t('imagesSmall'), (on) => {
          SV.settings.imagesHideSmall = on;
          SV_STORE.save({ imagesHideSmall: on });
          render();
        }),
        h('button', { class: 'btn primary', type: 'button', onclick: () => download(visibleItems()) }, icon('download', 15), t('imagesAll')),
        SV.iconButton('x', t('close'), () => closeGallery())),
      grid);
    render();
    savedOverflow = document.documentElement.style.getPropertyValue('overflow');
    document.documentElement.style.setProperty('overflow', 'hidden', 'important');
    removeGalleryKey = SV.onKey((event) => {
      if (event.key !== 'Escape' || SV.notch.view === 'home' || SV.notch.view === 'panel') return false;
      closeGallery();
      return true;
    });
    requestAnimationFrame(() => gallery?.classList.add('on'));
  }

  function closeGallery() {
    if (!gallery) return;
    const el = gallery;
    gallery = null;
    el.classList.remove('on');
    setTimeout(() => el.remove(), 320);
    removeGalleryKey?.();
    if (savedOverflow) document.documentElement.style.setProperty('overflow', savedOverflow);
    else document.documentElement.style.removeProperty('overflow');
  }

  // MARK: Media files

  const MEDIA_EXT = /\.(mp4|webm|mov|m4v|mkv|ogv|mp3|m4a|aac|wav|ogg|oga|flac|opus)(\?|#|$)/i;
  const AUDIO_EXT = /\.(mp3|m4a|aac|wav|ogg|oga|flac|opus)(\?|#|$)/i;

  function clock(seconds) {
    if (!Number.isFinite(seconds) || seconds <= 0) return '';
    const s = Math.round(seconds);
    const hh = Math.floor(s / 3600);
    const mm = Math.floor((s % 3600) / 60);
    const ss = String(s % 60).padStart(2, '0');
    return hh ? `${hh}:${String(mm).padStart(2, '0')}:${ss}` : `${mm}:${ss}`;
  }

  function collectMedia() {
    const found = new Map();
    let streams = 0;
    const add = (raw, kind, el, label) => {
      if (!raw) return;
      let url;
      try { url = new URL(raw, location.href).href; } catch { return; }
      if (url.startsWith('blob:') || /\.(m3u8|mpd)(\?|$)/i.test(url)) {
        streams++;
        return;
      }
      if (!/^https?:/.test(url)) return;
      const entry = found.get(url) || { url, kind, label: '', duration: '', size: '' };
      entry.kind = kind || entry.kind;
      if (label && !entry.label) entry.label = label;
      if (el instanceof HTMLMediaElement) {
        entry.duration ||= clock(el.duration);
        if (el instanceof HTMLVideoElement && el.videoWidth) entry.size = `${el.videoWidth}×${el.videoHeight}`;
      }
      found.set(url, entry);
    };
    for (const media of document.querySelectorAll('video, audio')) {
      if (SV.isOurs(media)) continue;
      const kind = media.localName;
      const title = media.getAttribute('title') || media.getAttribute('aria-label') || '';
      add(media.currentSrc || media.src, kind, media, title);
      for (const source of media.querySelectorAll('source[src]')) add(source.getAttribute('src'), kind, media, title);
    }
    for (const a of document.querySelectorAll('a[href]')) {
      const href = a.getAttribute('href');
      if (!MEDIA_EXT.test(href || '')) continue;
      add(href, AUDIO_EXT.test(href) ? 'audio' : 'video', a, (a.innerText || '').trim().slice(0, 80));
    }
    for (const [property, kind] of [['og:video', 'video'], ['og:video:url', 'video'], ['og:video:secure_url', 'video'], ['og:audio', 'audio']]) {
      const content = document.querySelector(`meta[property="${property}"]`)?.content;
      if (content && MEDIA_EXT.test(content)) add(content, kind, null, 'og');
    }
    return { items: [...found.values()], streams };
  }

  function mediaName(item, index) {
    try {
      const last = decodeURIComponent(new URL(item.url).pathname.split('/').pop() || '');
      const clean = SV.safeName(last);
      if (clean && MEDIA_EXT.test(clean)) return clean;
    } catch {}
    return `${SV.safeName(document.title) || SV.host} ${index + 1}.${item.kind === 'audio' ? 'mp3' : 'mp4'}`;
  }

  function mediaPanel(api) {
    const { items, streams } = collectMedia();
    if (!items.length) {
      api.body.append(h('div', { class: 'card empty', text: streams ? t('mediaStreamOnly') : t('mediaNone') }));
      return null;
    }
    const save = async (list) => {
      const prepared = list.map((item) => ({ url: item.url, filename: `SAVISUL/${SV.safeName(SV.host) || 'media'}/${mediaName(item, items.indexOf(item))}` }));
      const reply = await SV.send('download', { items: prepared });
      SV.toast(t('mediaStarted', I.number(reply.count || 0)), { icon: 'download' });
    };
    const list = h('div', { class: 'scroll-list compact' }, items.map((item, index) => h('div', { class: 'media-row' },
      h('span', { class: 'glyph small' }, icon(item.kind === 'audio' ? 'music' : 'film', 16)),
      h('div', { class: 'grow' },
        h('div', { class: 'ellipsis', text: item.label && item.label !== 'og' ? item.label : mediaName(item, index) }),
        h('div', { class: 'hint ellipsis', text: [item.kind === 'audio' ? t('mediaAudio') : t('mediaVideo'), item.size, item.duration, new URL(item.url).hostname].filter(Boolean).join(' · ') })),
      SV.iconButton('copy', t('mediaCopyUrl'), async () => { await SV.copy(item.url); SV.toast(t('copied'), { icon: 'copy' }); }),
      SV.iconButton('external', t('open'), () => SV.send('open', { url: item.url })),
      SV.iconButton('download', t('download'), () => save([item])))));
    api.body.append(list);
    api.body.append(h('div', { class: 'row' },
      h('span', { class: 'hint grow', text: streams ? t('mediaSomeStreams', I.number(streams)) : t('mediaRights') }),
      items.length > 1 ? h('button', { class: 'btn small primary', type: 'button', onclick: () => save(items) }, icon('download', 14), t('mediaAll', I.number(items.length))) : null));
    return null;
  }

  SV.css += `
.media-row { display: flex; align-items: center; gap: 8px; padding: 6px 4px 6px 8px; border-radius: 10px; }
.media-row:hover { background: var(--tile-hover); }
.glyph.small { width: 30px; height: 30px; border-radius: 9px; }
`;

  SV.tools.video = { label: 'tVideo', icon: 'play', kind: 'panel', title: () => t('videoTitle'), panel: videoPanel, init: keepSpeed };
  SV.tools.media = { label: 'tMedia', icon: 'film', kind: 'panel', title: () => t('mediaTitle'), panel: mediaPanel };
  SV.tools.images = { label: 'tImages', icon: 'image', kind: 'overlay', active: () => !!gallery, start: openGallery, stop: closeGallery };
})();
