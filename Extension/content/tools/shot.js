(() => {
  if ((window.top !== window && !globalThis.__savisulDemo) || !globalThis.SV) return;
  const SV = globalThis.SV;

  const { h, icon } = SV;
  const t = (...args) => SV_I18N.t(...args);
  const MAX_HEIGHT = 40000;

  let busy = false;

  function meta(kind, extra = {}) {
    return {
      kind,
      title: document.title,
      url: location.href,
      host: SV.host,
      dpr: devicePixelRatio,
      inner: { w: innerWidth, h: innerHeight },
      ...extra
    };
  }

  function findScroller() {
    const reader = SV.tools.reader?.scroller?.();
    if (reader) return reader;
    const doc = document.scrollingElement || document.documentElement;
    const rootStyle = getComputedStyle(document.documentElement);
    const bodyStyle = document.body ? getComputedStyle(document.body) : rootStyle;
    const rootScrolls = doc.scrollHeight - doc.clientHeight > 40 && rootStyle.overflowY !== 'hidden' && bodyStyle.overflowY !== 'hidden';
    if (rootScrolls) return null;
    let best = null;
    let bestArea = 0;
    let count = 0;
    for (const el of document.body?.querySelectorAll('*') || []) {
      if (++count > 6000) break;
      if (el.scrollHeight - el.clientHeight < 40 || SV.isOurs(el)) continue;
      if (!/(auto|scroll|overlay)/.test(getComputedStyle(el).overflowY)) continue;
      const r = el.getBoundingClientRect();
      const area = Math.max(0, Math.min(r.right, innerWidth) - Math.max(r.left, 0)) * Math.max(0, Math.min(r.bottom, innerHeight) - Math.max(r.top, 0));
      if (area > bestArea) {
        best = el;
        bestArea = area;
      }
    }
    return best && bestArea > innerWidth * innerHeight * 0.25 ? best : null;
  }

  function pinnedElements() {
    const fixed = [];
    const sticky = [];
    let count = 0;
    for (const el of document.body?.querySelectorAll('*') || []) {
      if (++count > 12000) break;
      if (SV.isOurs(el)) continue;
      const position = getComputedStyle(el).position;
      if (position === 'fixed') fixed.push(el);
      else if (position === 'sticky' || position === '-webkit-sticky') sticky.push(el);
    }
    return { fixed, sticky };
  }

  async function imagesSettled(timeout = 600) {
    const pending = [...document.images].filter((img) => {
      if (img.complete) return false;
      const r = img.getBoundingClientRect();
      return r.bottom > 0 && r.top < innerHeight && r.width > 0;
    });
    if (!pending.length) return;
    await Promise.race([
      Promise.all(pending.map((img) => new Promise((resolve) => {
        img.addEventListener('load', resolve, { once: true });
        img.addEventListener('error', resolve, { once: true });
      }))),
      SV.sleep(timeout)
    ]);
  }

  function badge(text) {
    SV.send('badge', { text }).catch(() => {});
  }

  async function full() {
    if (busy) {
      SV.toast(t('shotBusy'), { icon: 'camera', tone: 'warn' });
      return;
    }
    busy = true;
    SV.notch.close();
    const scroller = findScroller();
    const html = document.documentElement;
    const startX = scroller ? scroller.scrollLeft : window.scrollX;
    const startY = scroller ? scroller.scrollTop : window.scrollY;
    let id = null;
    let marked = [];
    SV.pageStyle('savisul-capture', 'html, body { scroll-behavior: auto !important; } html { scrollbar-width: none !important; } ::-webkit-scrollbar { display: none !important; }' +
      ' [data-savisul-hide] { visibility: hidden !important; animation: none !important; } [data-savisul-unstick] { position: relative !important; top: auto !important; bottom: auto !important; }');
    if (scroller) scroller.style.setProperty('scroll-behavior', 'auto', 'important');
    SV.hideUI(true);
    try {
      await SV.frames(2);
      let viewWidth;
      let viewHeight;
      let total;
      let clip = null;
      if (scroller) {
        const r = scroller.getBoundingClientRect();
        clip = {
          x: Math.max(0, r.left + scroller.clientLeft),
          y: Math.max(0, r.top + scroller.clientTop),
          w: Math.min(scroller.clientWidth, innerWidth),
          h: Math.min(scroller.clientHeight, innerHeight)
        };
        viewWidth = innerWidth;
        viewHeight = clip.h;
        total = Math.min(scroller.scrollHeight, MAX_HEIGHT);
      } else {
        viewWidth = html.clientWidth;
        viewHeight = innerHeight;
        total = Math.min(Math.max(html.scrollHeight, document.body?.scrollHeight || 0), MAX_HEIGHT);
      }
      const positions = [];
      for (let y = 0; y < total; y += viewHeight) positions.push(Math.min(y, Math.max(0, total - viewHeight)));
      const unique = [...new Set(positions)];
      id = (await SV.send('capture:begin', { meta: meta('full') })).id;

      const { fixed, sticky } = scroller ? { fixed: [], sticky: [] } : pinnedElements();
      const late = fixed.filter((el) => el.getBoundingClientRect().top > innerHeight / 2);
      for (const el of late) {
        el.setAttribute('data-savisul-hide', '');
        marked.push(el);
      }
      const frames = [];
      for (let i = 0; i < unique.length; i++) {
        if (scroller) scroller.scrollTop = unique[i];
        else window.scrollTo(0, unique[i]);
        if (i === 1) {
          for (const el of fixed) {
            el.setAttribute('data-savisul-hide', '');
            marked.push(el);
          }
          for (const el of sticky) {
            el.setAttribute('data-savisul-unstick', '');
            marked.push(el);
          }
        }
        await SV.frames(2);
        await imagesSettled(i === 0 ? 400 : 600);
        await SV.sleep(i === 0 ? 120 : 60);
        if (document.hidden) throw new Error('tab-changed');
        const actual = scroller ? scroller.scrollTop : window.scrollY;
        badge(`${Math.round(((i + 1) / unique.length) * 100)}%`);
        await SV.send('capture:frame', { id, index: i });
        frames.push({ x: 0, y: actual });
      }
      const height = scroller ? Math.min(scroller.scrollHeight, MAX_HEIGHT) : Math.min(Math.max(html.scrollHeight, document.body?.scrollHeight || 0), MAX_HEIGHT);
      await SV.send('capture:finish', {
        id,
        frames,
        meta: { viewport: { w: viewWidth, h: viewHeight }, total: { w: clip ? clip.w : viewWidth, h: Math.max(height, (frames.at(-1)?.y || 0) + viewHeight) }, clip }
      });
      id = null;
    } catch (error) {
      const message = String(error?.message || error);
      SV.hideUI(false);
      SV.toast(t(/tab-changed/.test(message) ? 'shotTabChanged' : 'shotFailed'), { icon: 'camera', tone: 'warn' });
      if (id) SV.send('capture:cancel', { id }).catch(() => {});
    } finally {
      for (const el of marked) {
        el.removeAttribute('data-savisul-hide');
        el.removeAttribute('data-savisul-unstick');
      }
      marked = [];
      SV.pageStyle('savisul-capture', null);
      if (scroller) {
        scroller.style.removeProperty('scroll-behavior');
        scroller.scrollTop = startY;
        scroller.scrollLeft = startX;
      } else {
        window.scrollTo(startX, startY);
      }
      SV.hideUI(false);
      badge('');
      busy = false;
    }
  }

  async function visible(crop) {
    if (busy) return;
    busy = true;
    SV.notch.close();
    SV.hideUI(true);
    try {
      await SV.frames(2);
      await SV.sleep(60);
      await SV.send('capture:visible', {
        meta: meta(crop ? 'region' : 'visible', { viewport: { w: document.documentElement.clientWidth, h: innerHeight }, crop: crop || null })
      });
    } catch {
      SV.toast(t('shotFailed'), { icon: 'camera', tone: 'warn' });
    } finally {
      SV.hideUI(false);
      busy = false;
    }
  }

  function region() {
    if (busy) return;
    SV.notch.close();
    const layer = SV.overlay('region');
    const sel = h('div', { class: 'sel' });
    let start = null;
    let removeKey = null;
    let label = null;
    const finish = async (rect) => {
      removeKey?.();
      layer.remove();
      SV.mode.exit('region');
      if (rect && rect.w > 4 && rect.h > 4) {
        await SV.frames(2);
        visible(rect);
      }
    };
    layer.addEventListener('pointerdown', (event) => {
      if (event.button !== 0) return;
      event.preventDefault();
      layer.setPointerCapture(event.pointerId);
      start = { x: event.clientX, y: event.clientY };
      layer.classList.add('dragging');
      layer.append(sel);
    });
    layer.addEventListener('pointermove', (event) => {
      if (!start) return;
      const x = Math.min(start.x, event.clientX);
      const y = Math.min(start.y, event.clientY);
      const w = Math.abs(event.clientX - start.x);
      const hgt = Math.abs(event.clientY - start.y);
      sel.style.cssText = `left:${x}px;top:${y}px;width:${w}px;height:${hgt}px;`;
      label?.remove();
      label = h('div', { class: 'tag size', text: `${Math.round(w)} × ${Math.round(hgt)}` });
      label.style.cssText = `left:${x + w + 8 > innerWidth - 90 ? x + w - 84 : x + w + 8}px;top:${Math.min(y + hgt + 8, innerHeight - 28)}px;`;
      layer.append(label);
    });
    layer.addEventListener('pointerup', (event) => {
      if (!start) return;
      const rect = {
        x: Math.min(start.x, event.clientX), y: Math.min(start.y, event.clientY),
        w: Math.abs(event.clientX - start.x), h: Math.abs(event.clientY - start.y)
      };
      start = null;
      finish(rect);
    });
    removeKey = SV.onKey((event) => {
      if (event.key !== 'Escape') return false;
      finish(null);
      return true;
    });
    SV.mode.enter({ id: 'region', icon: 'crop', name: t('shotRegion'), hint: t('shotRegionHint'), onExit: () => { removeKey?.(); layer.remove(); } });
  }

  function panel(api) {
    const option = (name, title, detail, run) => h('button', { class: 'option', type: 'button', onclick: run },
      h('span', { class: 'glyph' }, icon(name, 19)),
      h('span', { class: 'grow' }, h('div', { class: 't', text: title }), h('div', { class: 'd', text: detail })));
    api.body.append(h('div', { class: 'options' },
      option('page', t('shotFull'), t('shotFullDetail'), () => full()),
      option('screen', t('shotVisible'), t('shotVisibleDetail'), () => visible(null)),
      option('crop', t('shotRegion'), t('shotRegionDetail'), () => region()),
      option('inspect', t('elShot'), t('elShotDetail'), () => {
        SV.notch.close();
        requestAnimationFrame(() => SV.inspect?.start('shot'));
      })));
    api.body.firstChild.firstChild.setAttribute('data-autofocus', '');
    return null;
  }

  SV.tools.shot = { label: 'tShot', icon: 'camera', kind: 'panel', title: () => t('shotTitle'), panel, full, visible, region };
})();
