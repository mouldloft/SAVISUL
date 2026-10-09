(() => {
  if ((window.top !== window && !globalThis.__savisulDemo) || !globalThis.SV) return;
  const SV = globalThis.SV;

  const { h } = SV;
  const t = (...args) => SV_I18N.t(...args);

  let active = false;
  let layer = null;
  let target = null;
  let history = [];
  let remember = false;
  let removeKey = null;
  const unlisten = [];

  const stableId = (id) => id && !/\d{4,}|^\d|[:.[\]]|^(ember|react|radix|headlessui|mui)-?/i.test(id) && id.length < 40;
  const stableClass = (name) => name.length < 32 && !/\d{3,}|^(css|sc|jsx|tw|svelte|emotion)-|^_|__[a-z0-9]{5,}$|[A-Za-z0-9]{8,}_\w{4,}/.test(name) && !/^(hover|active|focus|open|show|visible|is-|has-)/.test(name);

  function selectorFor(el) {
    if (stableId(el.id) && document.querySelectorAll(`#${CSS.escape(el.id)}`).length === 1) return `#${CSS.escape(el.id)}`;
    const parts = [];
    for (let node = el; node && node.nodeType === 1 && node !== document.documentElement; node = node.parentElement) {
      if (node === document.body) {
        parts.unshift('body');
        break;
      }
      if (node !== el && stableId(node.id) && document.querySelectorAll(`#${CSS.escape(node.id)}`).length === 1) {
        parts.unshift(`#${CSS.escape(node.id)}`);
        break;
      }
      let part = node.localName;
      const classes = [...node.classList].filter(stableClass).slice(0, 2);
      if (classes.length) part += classes.map((name) => `.${CSS.escape(name)}`).join('');
      const parent = node.parentElement;
      if (parent) {
        const same = [...parent.children].filter((child) => child.localName === node.localName);
        if (same.length > 1) part += `:nth-of-type(${same.indexOf(node) + 1})`;
      }
      parts.unshift(part);
      const selector = parts.join(' > ');
      try {
        if (parts.length >= 2 && document.querySelectorAll(selector).length === 1) return selector;
      } catch {}
    }
    return parts.join(' > ');
  }

  function label(el) {
    let name = el.localName;
    if (el.id) name += `#${el.id}`;
    else if (el.classList.length) name += `.${[...el.classList].slice(0, 2).join('.')}`;
    return name.length > 44 ? `${name.slice(0, 43)}…` : name;
  }

  function sessionCss() {
    return history.map((entry) => `${entry.selector}{display:none!important}`).join('\n');
  }

  async function persist() {
    const rules = { ...(SV.settings.zapRules || {}) };
    const saved = new Set(rules[SV.host] || []);
    for (const entry of history) saved.add(entry.selector);
    if (saved.size) rules[SV.host] = [...saved];
    SV.settings.zapRules = rules;
    await SV_STORE.save({ zapRules: rules });
  }

  function draw() {
    if (!layer) return;
    SV.clear(layer);
    if (!target?.isConnected) return;
    const r = target.getBoundingClientRect();
    const box = h('div', { class: 'box zap' });
    box.style.cssText = `left:${r.left}px;top:${r.top}px;width:${r.width}px;height:${r.height}px;`;
    const tag = h('div', { class: 'tag' }, label(target), h('span', { class: 'faint', text: `  ${Math.round(r.width)} × ${Math.round(r.height)}` }));
    layer.append(box, tag);
    const tr = tag.getBoundingClientRect();
    tag.style.left = `${SV.clamp(r.left, 4, innerWidth - tr.width - 4)}px`;
    tag.style.top = `${r.top > 34 ? r.top - 26 : Math.min(r.bottom + 6, innerHeight - 26)}px`;
  }

  function updateMode() {
    SV.mode.update({
      hint: history.length ? t('zapCount', SV_I18N.number(history.length)) : t('zapHint'),
      actions: [
        { label: t('undo'), icon: 'restore', disabled: !history.length, run: undo },
        { node: h('label', { class: 'row', style: { gap: '6px', 'font-size': '12px', color: 'var(--ink-2)', 'padding-left': '4px' } },
          SV.toggleSwitch(remember, t('zapRemember', SV.host), (on) => { remember = on; if (on) persist(); }),
          h('span', { text: t('zapRemember', SV.host) })) }
      ]
    });
  }

  function zap(el) {
    if (!el || el === document.body || el === document.documentElement) return;
    const selector = selectorFor(el);
    history.push({ selector, el, display: el.style.getPropertyValue('display'), priority: el.style.getPropertyPriority('display') });
    el.style.setProperty('display', 'none', 'important');
    SV.pageStyle('savisul-zap', sessionCss());
    target = null;
    draw();
    updateMode();
    if (remember) persist();
  }

  function undo() {
    const entry = history.pop();
    if (!entry) return;
    if (entry.display) entry.el.style.setProperty('display', entry.display, entry.priority);
    else entry.el.style.removeProperty('display');
    SV.pageStyle('savisul-zap', history.length ? sessionCss() : null);
    if (remember) {
      const rules = { ...(SV.settings.zapRules || {}) };
      rules[SV.host] = (rules[SV.host] || []).filter((selector) => selector !== entry.selector);
      if (!rules[SV.host].length) delete rules[SV.host];
      SV.settings.zapRules = rules;
      SV_STORE.save({ zapRules: rules });
      const saved = document.getElementById('savisul-zap-saved');
      if (saved) saved.textContent = (rules[SV.host] || []).map((s) => `${s}{display:none!important}`).join('\n');
    }
    updateMode();
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
    remember = !!SV.settings.zapRules?.[SV.host]?.length;
    layer = SV.overlay('zap-layer');
    SV.pageStyle('savisul-zap-cursor', '*, *::before, *::after { cursor: crosshair !important; }');
    let queued = false;
    on(document, 'pointermove', (event) => {
      if (SV.isOurs(event.target)) return;
      const el = SV.elementAt(event.clientX, event.clientY);
      if (el && el !== target) {
        target = el;
        if (!queued) {
          queued = true;
          requestAnimationFrame(() => { queued = false; draw(); });
        }
      }
    });
    on(document, 'click', (event) => {
      if (!swallow(event)) return;
      zap(target || SV.elementAt(event.clientX, event.clientY));
    });
    for (const type of ['pointerdown', 'mousedown', 'mouseup', 'pointerup', 'dblclick', 'contextmenu', 'auxclick']) on(document, type, swallow);
    on(window, 'scroll', () => draw(), { capture: true, passive: true });
    removeKey = SV.onKey((event) => {
      if (event.key === 'Escape') {
        stop();
        return true;
      }
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'z') {
        undo();
        return true;
      }
      if (event.key === 'ArrowUp' && target?.parentElement && target.parentElement !== document.body) {
        target = target.parentElement;
        draw();
        return true;
      }
      return false;
    });
    SV.mode.enter({ id: 'zapper', icon: 'eyeOff', name: t('tZap'), hint: t('zapHint'), onExit: () => stop() });
    updateMode();
  }

  function stop() {
    if (!active) return;
    active = false;
    unlisten.splice(0).forEach((off) => off());
    removeKey?.();
    removeKey = null;
    SV.pageStyle('savisul-zap-cursor', null);
    layer?.remove();
    layer = null;
    target = null;
    if (remember && history.length) persist();
    SV.mode.exit('zapper');
  }

  SV.zapper = {
    restore() {
      for (const entry of history.splice(0)) entry.el.style.removeProperty('display');
      SV.pageStyle('savisul-zap', null);
      document.getElementById('savisul-zap-saved')?.remove();
    }
  };

  SV.tools.zapper = { label: 'tZap', icon: 'eyeOff', kind: 'mode', active: () => active, start, stop };
})();
