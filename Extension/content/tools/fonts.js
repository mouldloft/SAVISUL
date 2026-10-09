(() => {
  if ((window.top !== window && !globalThis.__savisulDemo) || !globalThis.SV) return;
  const SV = globalThis.SV;

  const { h } = SV;
  const t = (...args) => SV_I18N.t(...args);
  const WEIGHTS = { 100: 'Thin', 200: 'Extra Light', 300: 'Light', 400: 'Regular', 500: 'Medium', 600: 'Semibold', 700: 'Bold', 800: 'Extra Bold', 900: 'Black' };

  let active = false;
  let layer = null;
  let card = null;
  let target = null;
  let removeKey = null;
  const unlisten = [];

  function textTarget(el) {
    for (let node = el; node && node !== document.body; node = node.parentElement) {
      if ([...node.childNodes].some((child) => child.nodeType === 3 && child.nodeValue.trim())) return node;
    }
    return el;
  }

  function facts(el) {
    const s = getComputedStyle(el);
    const families = s.fontFamily.split(',').map((f) => f.trim().replace(/^["']|["']$/g, '')).filter(Boolean);
    const size = parseFloat(s.fontSize);
    const lineHeight = s.lineHeight === 'normal' ? 'normal' : `${Math.round(parseFloat(s.lineHeight) * 10) / 10}px`;
    const ratio = s.lineHeight === 'normal' ? '' : ` · ${(parseFloat(s.lineHeight) / size).toFixed(2)}`;
    const weight = Math.round(Number(s.fontWeight) / 100) * 100 || 400;
    const color = SV.parseColor(s.color) || { r: 0, g: 0, b: 0, a: 1 };
    return {
      families,
      size: `${Math.round(size * 10) / 10}px`,
      weight: `${s.fontWeight} · ${WEIGHTS[weight] || ''}`.trim(),
      lineHeight: lineHeight + ratio,
      letterSpacing: s.letterSpacing,
      style: s.fontStyle,
      color: SV.toHex(color).toUpperCase(),
      css: [
        `font-family: ${s.fontFamily};`,
        `font-size: ${s.fontSize};`,
        `font-weight: ${s.fontWeight};`,
        `line-height: ${s.lineHeight};`,
        s.letterSpacing !== 'normal' ? `letter-spacing: ${s.letterSpacing};` : null,
        s.fontStyle !== 'normal' ? `font-style: ${s.fontStyle};` : null,
        `color: ${SV.toHex(color).toUpperCase()};`
      ].filter(Boolean).join('\n')
    };
  }

  function render(x, y) {
    if (!layer || !target) return;
    const info = facts(target);
    SV.clear(layer);
    const r = target.getBoundingClientRect();
    const box = h('div', { class: 'box pinned' });
    box.style.cssText = `left:${r.left}px;top:${r.top}px;width:${r.width}px;height:${r.height}px;`;
    const row = (k, v, swatch) => [h('span', { class: 'k', text: k }), h('span', { class: 'v' }, swatch ? h('span', { class: 'chipcolor', style: { background: swatch } }) : null, v)];
    card = h('div', { class: 'inspector' },
      h('div', { class: 'family' }, info.families[0] || 'serif', info.families.length > 1 ? h('span', { class: 'faint', style: { 'font-size': '12px', 'font-weight': '400' }, text: `  ${info.families.slice(1, 3).join(', ')}` }) : null),
      h('div', { class: 'facts' },
        row(t('fSize'), info.size),
        row(t('fWeight'), info.weight),
        row(t('fLine'), info.lineHeight),
        info.letterSpacing !== 'normal' ? row(t('fTracking'), info.letterSpacing) : null,
        info.style !== 'normal' ? row(t('fStyle'), info.style) : null,
        row(t('fColor'), info.color, info.color)));
    layer.append(box, card);
    const cr = card.getBoundingClientRect();
    const left = x + 18 + cr.width > innerWidth - 8 ? x - cr.width - 18 : x + 18;
    const top = y + 18 + cr.height > innerHeight - 8 ? y - cr.height - 18 : y + 18;
    card.style.left = `${SV.clamp(left, 8, innerWidth - cr.width - 8)}px`;
    card.style.top = `${SV.clamp(top, 8, innerHeight - cr.height - 8)}px`;
  }

  function on(node, type, handler, options = true) {
    node.addEventListener(type, handler, options);
    unlisten.push(() => node.removeEventListener(type, handler, options));
  }

  const swallow = (event) => {
    if (SV.isOurs(event.target)) return false;
    event.preventDefault();
    event.stopImmediatePropagation();
    return true;
  };

  function start() {
    if (active) return;
    active = true;
    layer = SV.overlay('fonts-layer');
    let queued = false;
    let point = { x: 0, y: 0 };
    on(document, 'pointermove', (event) => {
      if (SV.isOurs(event.target)) return;
      point = { x: event.clientX, y: event.clientY };
      if (queued) return;
      queued = true;
      requestAnimationFrame(() => {
        queued = false;
        const el = SV.elementAt(point.x, point.y);
        if (el) target = textTarget(el);
        render(point.x, point.y);
      });
    });
    on(document, 'click', async (event) => {
      if (!swallow(event) || !target) return;
      await SV.copy(facts(target).css);
      SV.toast(t('fontsCopied'), { icon: 'type' });
    });
    for (const type of ['pointerdown', 'mousedown', 'mouseup', 'pointerup', 'dblclick', 'auxclick']) on(document, type, swallow);
    removeKey = SV.onKey((event) => {
      if (event.key !== 'Escape') return false;
      stop();
      return true;
    });
    SV.mode.enter({ id: 'fonts', icon: 'type', name: t('tFonts'), hint: t('fontsHint'), onExit: () => stop() });
  }

  function stop() {
    if (!active) return;
    active = false;
    unlisten.splice(0).forEach((off) => off());
    removeKey?.();
    removeKey = null;
    layer?.remove();
    layer = null;
    target = null;
    SV.mode.exit('fonts');
  }

  SV.tools.fonts = { label: 'tFonts', icon: 'type', kind: 'mode', active: () => active, start, stop };
})();
