(() => {
  if ((window.top !== window && !globalThis.__savisulDemo) || !globalThis.SV) return;
  const SV = globalThis.SV;

  const { h } = SV;
  const t = (...args) => SV_I18N.t(...args);

  let active = false;
  let layer = null;
  let hovered = null;
  let pinned = null;
  let drag = null;
  let last = { x: 0, y: 0 };
  let removeKey = null;
  const unlisten = [];

  const px = (value) => {
    const rounded = Math.round(value * 10) / 10;
    return Number.isInteger(rounded) ? String(rounded) : rounded.toFixed(1);
  };

  function describe(el) {
    let name = el.localName;
    if (el.id) name += `#${el.id}`;
    else if (el.classList.length) name += `.${[...el.classList].slice(0, 2).join('.')}`;
    return name.length > 38 ? `${name.slice(0, 37)}…` : name;
  }

  function frame(x, y, w, hgt, widths, color) {
    const el = h('div', { class: 'box' });
    el.style.cssText = `left:${x}px;top:${y}px;width:${Math.max(0, w)}px;height:${Math.max(0, hgt)}px;` +
      `border-style:solid;border-color:${color};border-width:${widths.map((v) => `${Math.max(0, v)}px`).join(' ')};`;
    return el;
  }

  function tag(text, x, y, red, faint) {
    const el = h('div', { class: `tag${red ? ' red' : ''}` }, text, faint ? h('span', { class: 'faint', text: `  ${faint}` }) : null);
    layer.append(el);
    const rect = el.getBoundingClientRect();
    const left = SV.clamp(x - rect.width / 2, 4, innerWidth - rect.width - 4);
    const top = SV.clamp(y, 4, innerHeight - rect.height - 4);
    el.style.left = `${left}px`;
    el.style.top = `${top}px`;
    return el;
  }

  function line(x1, y1, x2, y2, dashed) {
    const horizontal = y1 === y2;
    const el = h('div', { class: `guide ${horizontal ? 'h' : 'v'}${dashed ? ' dash' : ''}` });
    if (horizontal) el.style.cssText = `left:${Math.min(x1, x2)}px;top:${y1}px;width:${Math.abs(x2 - x1)}px;`;
    else el.style.cssText = `left:${x1}px;top:${Math.min(y1, y2)}px;height:${Math.abs(y2 - y1)}px;`;
    layer.append(el);
  }

  function boxModel(el) {
    const r = el.getBoundingClientRect();
    const s = getComputedStyle(el);
    const n = (v) => parseFloat(v) || 0;
    const m = [n(s.marginTop), n(s.marginRight), n(s.marginBottom), n(s.marginLeft)].map((v) => Math.max(0, v));
    const b = [n(s.borderTopWidth), n(s.borderRightWidth), n(s.borderBottomWidth), n(s.borderLeftWidth)];
    const p = [n(s.paddingTop), n(s.paddingRight), n(s.paddingBottom), n(s.paddingLeft)];
    layer.append(
      frame(r.left - m[3], r.top - m[0], r.width + m[1] + m[3], r.height + m[0] + m[2], m, 'rgba(246, 178, 107, 0.45)'),
      frame(r.left, r.top, r.width, r.height, b, 'rgba(255, 229, 153, 0.6)'),
      frame(r.left + b[3], r.top + b[0], r.width - b[1] - b[3], r.height - b[0] - b[2], p, 'rgba(147, 196, 125, 0.5)'));
    const content = h('div', { class: 'box content' });
    content.style.cssText = `left:${r.left + b[3] + p[3]}px;top:${r.top + b[0] + p[0]}px;width:${Math.max(0, r.width - b[1] - b[3] - p[1] - p[3])}px;height:${Math.max(0, r.height - b[0] - b[2] - p[0] - p[2])}px;`;
    layer.append(content);
    const extra = [];
    if (p.some(Boolean)) extra.push(`p ${p.map(px).join(' ')}`);
    if (m.some(Boolean)) extra.push(`m ${m.map(px).join(' ')}`);
    const above = r.top - m[0] > 30;
    tag(`${describe(el)}  ${px(r.width)} × ${px(r.height)}`, r.left + r.width / 2, above ? r.top - m[0] - 26 : r.bottom + m[2] + 6, false, extra.join(' · '));
    return r;
  }

  function distances(a, b) {
    const inside = b.left >= a.left && b.right <= a.right && b.top >= a.top && b.bottom <= a.bottom;
    const outside = a.left >= b.left && a.right <= b.right && a.top >= b.top && a.bottom <= b.bottom;
    if (inside || outside) {
      const [outer, inner] = inside ? [a, b] : [b, a];
      const cx = inner.left + inner.width / 2;
      const cy = inner.top + inner.height / 2;
      const gaps = [
        [cx, outer.top, cx, inner.top, inner.top - outer.top],
        [cx, inner.bottom, cx, outer.bottom, outer.bottom - inner.bottom],
        [outer.left, cy, inner.left, cy, inner.left - outer.left],
        [inner.right, cy, outer.right, cy, outer.right - inner.right]
      ];
      for (const [x1, y1, x2, y2, value] of gaps) {
        if (value < 0.5) continue;
        line(x1, y1, x2, y2);
        tag(px(value), (x1 + x2) / 2, (y1 + y2) / 2 - 9, true);
      }
      return;
    }
    const overlapY = [Math.max(a.top, b.top), Math.min(a.bottom, b.bottom)];
    const overlapX = [Math.max(a.left, b.left), Math.min(a.right, b.right)];
    if (b.left >= a.right || a.left >= b.right) {
      const [left, right] = b.left >= a.right ? [a, b] : [b, a];
      const y = overlapY[0] < overlapY[1] ? (overlapY[0] + overlapY[1]) / 2 : right.top + right.height / 2;
      line(left.right, y, right.left, y);
      tag(px(right.left - left.right), (left.right + right.left) / 2, y - 22, true);
      if (overlapY[0] >= overlapY[1]) line(left.right, Math.min(left.top + left.height / 2, y), left.right, Math.max(left.top + left.height / 2, y), true);
    }
    if (b.top >= a.bottom || a.top >= b.bottom) {
      const [upper, lower] = b.top >= a.bottom ? [a, b] : [b, a];
      const x = overlapX[0] < overlapX[1] ? (overlapX[0] + overlapX[1]) / 2 : lower.left + lower.width / 2;
      line(x, upper.bottom, x, lower.top);
      tag(px(lower.top - upper.bottom), x + 26, (upper.bottom + lower.top) / 2 - 9, true);
      if (overlapX[0] >= overlapX[1]) line(Math.min(upper.left + upper.width / 2, x), upper.bottom, Math.max(upper.left + upper.width / 2, x), upper.bottom, true);
    }
  }

  function draw() {
    if (!layer) return;
    SV.clear(layer);
    if (drag?.moved) {
      const x = Math.min(drag.x, last.x);
      const y = Math.min(drag.y, last.y);
      const w = Math.abs(last.x - drag.x);
      const hgt = Math.abs(last.y - drag.y);
      const box = h('div', { class: 'measure' });
      box.style.cssText = `left:${x}px;top:${y}px;width:${w}px;height:${hgt}px;`;
      layer.append(box);
      tag(`${px(w)} × ${px(hgt)}`, x + w / 2, y + hgt + 8, true);
      return;
    }
    let pinnedRect = null;
    if (pinned?.isConnected) {
      pinnedRect = pinned.getBoundingClientRect();
      const box = h('div', { class: 'box pinned' });
      box.style.cssText = `left:${pinnedRect.left}px;top:${pinnedRect.top}px;width:${pinnedRect.width}px;height:${pinnedRect.height}px;`;
      layer.append(box);
    }
    if (hovered?.isConnected && hovered !== pinned) {
      const rect = boxModel(hovered);
      if (pinnedRect) distances(pinnedRect, rect);
    } else if (pinnedRect && pinned) {
      tag(`${describe(pinned)}  ${px(pinnedRect.width)} × ${px(pinnedRect.height)}`, pinnedRect.left + pinnedRect.width / 2, pinnedRect.top > 30 ? pinnedRect.top - 26 : pinnedRect.bottom + 6, true);
    }
  }

  let queued = false;
  const schedule = () => {
    if (queued) return;
    queued = true;
    requestAnimationFrame(() => {
      queued = false;
      draw();
    });
  };

  function on(target, type, handler, options = true) {
    target.addEventListener(type, handler, options);
    unlisten.push(() => target.removeEventListener(type, handler, options));
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
    layer = SV.overlay('ruler-layer');
    SV.pageStyle('savisul-ruler-cursor', '*, *::before, *::after { cursor: crosshair !important; user-select: none !important; }');
    on(document, 'pointermove', (event) => {
      if (SV.isOurs(event.target)) return;
      last = { x: event.clientX, y: event.clientY };
      if (drag && !drag.moved && Math.hypot(last.x - drag.x, last.y - drag.y) > 4) drag.moved = true;
      if (!drag?.moved) {
        const el = SV.elementAt(event.clientX, event.clientY);
        if (el && el !== document.documentElement && el !== document.body) hovered = el;
      }
      schedule();
    });
    on(document, 'pointerdown', (event) => {
      if (event.button !== 0 || !swallow(event)) return;
      drag = { x: event.clientX, y: event.clientY, moved: false };
    });
    on(document, 'pointerup', (event) => {
      if (!drag) return;
      swallow(event);
      if (!drag.moved) pinned = pinned === hovered ? null : hovered;
      drag = null;
      schedule();
    });
    for (const type of ['mousedown', 'mouseup', 'click', 'dblclick', 'contextmenu', 'auxclick']) on(document, type, swallow);
    on(window, 'scroll', schedule, { capture: true, passive: true });
    on(window, 'resize', schedule, { passive: true });
    removeKey = SV.onKey((event) => {
      if (event.key === 'Escape') {
        stop();
        return true;
      }
      if (event.key === 'ArrowUp' && hovered?.parentElement && hovered.parentElement !== document.body) {
        hovered = hovered.parentElement;
        schedule();
        return true;
      }
      return false;
    });
    SV.mode.enter({
      id: 'ruler', icon: 'ruler', name: t('tRuler'), hint: t('rulerHint'),
      actions: [{ label: t('rulerClear'), run: () => { pinned = null; hovered = null; schedule(); } }],
      onExit: () => stop()
    });
  }

  function stop() {
    if (!active) return;
    active = false;
    unlisten.splice(0).forEach((off) => off());
    removeKey?.();
    removeKey = null;
    SV.pageStyle('savisul-ruler-cursor', null);
    layer?.remove();
    layer = null;
    hovered = null;
    pinned = null;
    drag = null;
    SV.mode.exit('ruler');
  }

  SV.tools.ruler = { label: 'tRuler', icon: 'ruler', kind: 'mode', active: () => active, start, stop };
})();
