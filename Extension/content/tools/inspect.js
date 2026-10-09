(() => {
  if ((window.top !== window && !globalThis.__savisulDemo) || !globalThis.SV) return;
  const SV = globalThis.SV;

  const { h } = SV;
  const I = SV_I18N;
  const t = (...args) => I.t(...args);

  // Properties worth copying, with the values that mean "nothing set".
  const PROPS = [
    ['display', ['inline']], ['position', ['static']], ['top', ['auto']], ['right', ['auto']], ['bottom', ['auto']], ['left', ['auto']],
    ['width', []], ['height', []], ['margin', ['0px']], ['padding', ['0px']],
    ['flex-direction', ['row']], ['flex-wrap', ['nowrap']], ['justify-content', ['normal']], ['align-items', ['normal']], ['gap', ['normal']],
    ['grid-template-columns', ['none']], ['grid-template-rows', ['none']],
    ['border', ['0px none rgb(0, 0, 0)', '0px none']], ['border-radius', ['0px']], ['box-shadow', ['none']], ['outline', ['none']],
    ['background-color', ['rgba(0, 0, 0, 0)', 'transparent']], ['background-image', ['none']],
    ['color', []], ['font-family', []], ['font-size', []], ['font-weight', ['400']], ['line-height', ['normal']],
    ['letter-spacing', ['normal']], ['text-align', ['start']], ['text-transform', ['none']], ['text-decoration', []],
    ['opacity', ['1']], ['z-index', ['auto']], ['overflow', ['visible']], ['transform', ['none']], ['filter', ['none']],
    ['backdrop-filter', ['none']], ['cursor', ['auto']]
  ];
  const POSITIONED = new Set(['top', 'right', 'bottom', 'left']);

  let active = false;
  let purpose = 'inspect';
  let layer = null;
  let target = null;
  let pinned = false;
  let removeKey = null;
  const unlisten = [];

  function selectorLabel(el) {
    let label = el.localName;
    if (el.id) label += `#${el.id}`;
    const classes = [...el.classList].filter((c) => !/^\d|[^\w-]/.test(c)).slice(0, 3);
    if (classes.length) label += `.${classes.join('.')}`;
    return label.length > 60 ? `${label.slice(0, 59)}…` : label;
  }

  function cssFor(el) {
    const s = getComputedStyle(el);
    const lines = [];
    for (const [prop, defaults] of PROPS) {
      if (POSITIONED.has(prop) && s.position === 'static') continue;
      let value = s.getPropertyValue(prop);
      if (!value || defaults.includes(value)) continue;
      if (prop === 'text-decoration' && /^none\b/.test(value)) continue;
      if (prop === 'border' && /^0px/.test(value)) continue;
      if ((prop === 'color' || prop === 'background-color') && SV.parseColor(value)?.a === 1) value = SV.toHex(SV.parseColor(value)).toUpperCase();
      if (prop === 'width' || prop === 'height') value = `${Math.round(parseFloat(value) * 10) / 10}px`;
      lines.push(`  ${prop}: ${value};`);
    }
    return `${selectorLabel(el)} {\n${lines.join('\n')}\n}`;
  }

  const px = (v) => parseFloat(v) || 0;

  function boxes(el) {
    const s = getComputedStyle(el);
    const r = el.getBoundingClientRect();
    const m = [px(s.marginTop), px(s.marginRight), px(s.marginBottom), px(s.marginLeft)];
    const b = [px(s.borderTopWidth), px(s.borderRightWidth), px(s.borderBottomWidth), px(s.borderLeftWidth)];
    const p = [px(s.paddingTop), px(s.paddingRight), px(s.paddingBottom), px(s.paddingLeft)];
    const box = (cls, x, y, w, hh) => {
      const node = h('div', { class: `box ${cls}` });
      node.style.cssText = `left:${x}px;top:${y}px;width:${Math.max(0, w)}px;height:${Math.max(0, hh)}px;`;
      return node;
    };
    return [
      box('margin', r.left - m[3], r.top - m[0], r.width + m[1] + m[3], r.height + m[0] + m[2]),
      box('border', r.left, r.top, r.width, r.height),
      box('padding', r.left + b[3], r.top + b[0], r.width - b[1] - b[3], r.height - b[0] - b[2]),
      box('content', r.left + b[3] + p[3], r.top + b[0] + p[0], r.width - b[1] - b[3] - p[1] - p[3], r.height - b[0] - b[2] - p[0] - p[2])
    ];
  }

  const shorten = (value, n = 34) => (value.length > n ? `${value.slice(0, n - 1)}…` : value);
  const sides = (s, name) => {
    const v = ['Top', 'Right', 'Bottom', 'Left'].map((side) => Math.round(px(s[`${name}${side}`])));
    if (v.every((x) => x === v[0])) return `${v[0]}`;
    if (v[0] === v[2] && v[1] === v[3]) return `${v[0]} ${v[1]}`;
    return v.join(' ');
  };

  function card(el) {
    const s = getComputedStyle(el);
    const r = el.getBoundingClientRect();
    const fg = SV.parseColor(s.color);
    const bg = SV.parseColor(s.backgroundColor);
    const row = (k, v, swatch) => v ? [h('span', { class: 'k', text: k }), h('span', { class: 'v', title: v },
      swatch ? h('span', { class: 'chipcolor', style: { background: swatch } }) : null, shorten(v))] : null;
    const font = `${s.fontFamily.split(',')[0].replace(/["']/g, '').trim()} · ${Math.round(px(s.fontSize) * 10) / 10}px · ${s.fontWeight}`;
    const layout = s.display.includes('flex')
      ? `${s.display} · ${s.flexDirection}${s.gap !== 'normal' ? ` · gap ${s.gap}` : ''}`
      : s.display.includes('grid') ? `${s.display} · ${s.gridTemplateColumns.split(' ').length} col` : s.display;
    const contrast = fg && bg && bg.a > 0.5 ? `${I.number(SV.contrast(fg, SV.backgroundOf(el)), 2, 2)}:1` : '';
    return h('div', { class: 'inspector css-card' },
      h('div', { class: 'family mono-title', text: selectorLabel(el) }),
      h('div', { class: 'dims', text: `${Math.round(r.width)} × ${Math.round(r.height)}` }),
      h('div', { class: 'facts' },
        row(t('cssLayout'), layout),
        s.position !== 'static' ? row(t('cssPosition'), s.position) : null,
        row(t('cssMargin'), sides(s, 'margin')),
        row(t('cssPadding'), sides(s, 'padding')),
        row(t('cssFont'), font),
        row(t('fColor'), fg ? SV.toHex(fg).toUpperCase() : s.color, s.color),
        bg && bg.a > 0 ? row(t('cssBackground'), SV.toHex(bg).toUpperCase(), s.backgroundColor) : null,
        s.backgroundImage !== 'none' ? row(t('cssImage'), s.backgroundImage.startsWith('url') ? 'url(…)' : s.backgroundImage) : null,
        px(s.borderTopWidth) || px(s.borderLeftWidth) ? row(t('cssBorder'), `${s.borderTopWidth} ${s.borderTopStyle}`, s.borderTopColor) : null,
        s.borderRadius !== '0px' ? row(t('cssRadius'), s.borderRadius) : null,
        s.boxShadow !== 'none' ? row(t('cssShadow'), s.boxShadow) : null,
        s.opacity !== '1' ? row(t('cssOpacity'), s.opacity) : null,
        s.zIndex !== 'auto' ? row('z-index', s.zIndex) : null,
        contrast ? row(t('cssContrast'), contrast) : null),
      h('div', { class: 'hint', style: { 'margin-top': '8px' }, text: purpose === 'shot' ? t('elShotHint') : SV.tools.shot ? t('cssKeys') : t('cssKeys').split(' · ').slice(0, -1).join(' · ') }));
  }

  function render(point) {
    if (!layer) return;
    SV.clear(layer);
    if (!target || !target.isConnected) return;
    layer.append(...boxes(target));
    if (purpose === 'shot') {
      const r = target.getBoundingClientRect();
      const tag = h('div', { class: 'tag size', text: `${selectorLabel(target)} · ${Math.round(r.width)} × ${Math.round(r.height)}` });
      tag.style.cssText = `left:${SV.clamp(r.left, 6, innerWidth - 220)}px;top:${r.top > 34 ? r.top - 28 : Math.min(r.bottom + 6, innerHeight - 28)}px;`;
      layer.append(tag);
      return;
    }
    const info = card(target);
    layer.append(info);
    const cr = info.getBoundingClientRect();
    const x = point?.x ?? target.getBoundingClientRect().right;
    const y = point?.y ?? target.getBoundingClientRect().top;
    const left = x + 18 + cr.width > innerWidth - 8 ? x - cr.width - 18 : x + 18;
    const top = y + 18 + cr.height > innerHeight - 8 ? y - cr.height - 18 : y + 18;
    info.style.left = `${SV.clamp(left, 8, innerWidth - cr.width - 8)}px`;
    info.style.top = `${SV.clamp(top, 8, innerHeight - cr.height - 8)}px`;
  }

  async function copyCss() {
    if (!target) return;
    await SV.copy(cssFor(target));
    SV.toast(t('cssCopied'), { icon: 'inspect' });
  }

  // Scrolls the element into view and hands its on-screen box to the screenshot tool.
  async function shootElement(el) {
    if (!el || !SV.tools.shot) return;
    stop();
    const before = el.getBoundingClientRect();
    if (before.top < 0 || before.bottom > innerHeight || before.left < 0 || before.right > innerWidth) {
      el.scrollIntoView({ block: before.height > innerHeight ? 'start' : 'center', inline: 'nearest' });
      await SV.sleep(260);
    }
    await SV.frames(2);
    const r = el.getBoundingClientRect();
    const rect = {
      x: Math.max(0, r.left), y: Math.max(0, r.top),
      w: Math.min(innerWidth, r.right) - Math.max(0, r.left), h: Math.min(innerHeight, r.bottom) - Math.max(0, r.top)
    };
    if (rect.w < 4 || rect.h < 4) {
      SV.toast(t('shotFailed'), { icon: 'camera', tone: 'warn' });
      return;
    }
    if (r.height > innerHeight + 2 || r.width > innerWidth + 2) SV.toast(t('elShotClipped'), { icon: 'camera', tone: 'info' });
    await SV.tools.shot.visible(rect);
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

  function enterMode() {
    if (purpose === 'shot') {
      SV.mode.enter({ id: 'inspect', icon: 'crop', name: t('elShot'), hint: t('elShotHint'), onExit: () => stop() });
      return;
    }
    SV.mode.enter({
      id: 'inspect', icon: 'inspect', name: t('tInspect'), hint: t('cssHint'),
      actions: [
        { label: t('cssParent'), icon: 'back', run: () => step('up'), title: '↑' },
        { label: t('copy'), icon: 'copy', run: () => copyCss() },
        SV.tools.shot ? { label: t('elShot'), icon: 'camera', run: () => shootElement(target) } : null
      ].filter(Boolean),
      onExit: () => stop()
    });
  }

  function step(direction) {
    if (!target) return;
    const next = direction === 'up' ? target.parentElement : target.firstElementChild;
    if (!next || next === document.documentElement || SV.isOurs(next)) return;
    target = next;
    pinned = true;
    render(null);
  }

  function start(mode = 'inspect') {
    if (active) stop();
    active = true;
    purpose = mode;
    pinned = false;
    layer = SV.overlay('fonts-layer');
    let queued = false;
    let point = { x: 0, y: 0 };
    on(document, 'pointermove', (event) => {
      if (SV.isOurs(event.target) || pinned) return;
      point = { x: event.clientX, y: event.clientY };
      if (queued) return;
      queued = true;
      requestAnimationFrame(() => {
        queued = false;
        const el = SV.elementAt(point.x, point.y);
        if (el && el !== document.documentElement && el !== document.body) target = el;
        render(point);
      });
    });
    on(document, 'click', (event) => {
      if (!swallow(event) || !target) return;
      if (purpose === 'shot') {
        shootElement(target);
        return;
      }
      pinned = !pinned;
      if (pinned) copyCss();
      render({ x: event.clientX, y: event.clientY });
    });
    on(window, 'scroll', () => requestAnimationFrame(() => render(pinned ? null : point)), { passive: true, capture: true });
    for (const type of ['pointerdown', 'mousedown', 'mouseup', 'pointerup', 'dblclick', 'auxclick', 'contextmenu']) on(document, type, swallow);
    removeKey = SV.onKey((event) => {
      if (event.key === 'Escape') {
        if (pinned && purpose === 'inspect') {
          pinned = false;
          return true;
        }
        stop();
        return true;
      }
      if (purpose !== 'inspect' || !target) return false;
      if (event.key === 'ArrowUp') { step('up'); return true; }
      if (event.key === 'ArrowDown') { step('down'); return true; }
      if (event.key.toLowerCase() === 'c' && !event.metaKey && !event.ctrlKey) { copyCss(); return true; }
      if (event.key.toLowerCase() === 's' && !event.metaKey && !event.ctrlKey) { shootElement(target); return true; }
      return false;
    });
    enterMode();
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
    pinned = false;
    SV.mode.exit('inspect');
  }

  SV.css += `
.css-card { width: 300px; pointer-events: none; }
.css-card .mono-title { font-family: var(--mono); font-size: 12.5px; font-weight: 600; color: var(--accent); margin-bottom: 2px; word-break: break-all; }
.css-card .dims { font-size: 11.5px; color: var(--ink-2); margin-bottom: 8px; font-variant-numeric: tabular-nums; }
`;

  SV.inspect = { start, stop, shootElement, cssFor };
  SV.tools.inspect = { label: 'tInspect', icon: 'inspect', kind: 'mode', active: () => active && purpose === 'inspect', start: () => start('inspect'), stop };
  SV.tools.elementShot = { label: 'elShot', icon: 'crop', kind: 'mode', active: () => active && purpose === 'shot', start: () => start('shot'), stop };
})();
