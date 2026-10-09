(() => {
  if ((window.top !== window && !globalThis.__savisulDemo) || !globalThis.SV) return;
  const SV = globalThis.SV;

  const { h, icon } = SV;
  const I = SV_I18N;
  const t = (...args) => I.t(...args);

  const TOOL_ORDER = ['color', 'ruler', 'notes', 'shot', 'zapper', 'fonts', 'inspect', 'link', 'tables', 'translate', 'export', 'video', 'media', 'images', 'speak'];
  const PAGE_ORDER = ['reader', 'dark', 'unlock', 'edit', 'outline'];

  const N = {
    view: 'idle',
    panel: null,
    panelCleanup: null,
    mode: null,
    pinned: false,
    slim: false,
    awake: false,
    hovering: false,
    bridge: { status: 'idle', state: null },
    indicators: {},
    commands: null
  };
  SV.notch = N;

  let host, shadow, root, notchEl, overlays, floatToast;
  const layers = {};
  let openTimer, closeTimer, toastTimer, floatTimer, wakeTimer, raiseTimer;
  let toastReturn = null;
  let bridgePort = null;
  let volumeHold = 0;
  let resizeObserver;

  // MARK: Mount

  function hostStyle(el) {
    const s = el.style;
    s.setProperty('all', 'initial', 'important');
    const props = {
      position: 'fixed', top: '0', left: '0', right: '0', bottom: '0', width: '100%', height: '100%',
      'max-width': 'none', 'max-height': 'none', margin: '0', padding: '0', border: '0', background: 'transparent',
      overflow: 'visible', 'z-index': '2147483647', 'pointer-events': 'none', display: 'block', 'color-scheme': 'normal'
    };
    for (const [key, value] of Object.entries(props)) s.setProperty(key, value, 'important');
  }

  function raise() {
    if (!SV.alive || !host?.isConnected) return;
    if (typeof host.showPopover !== 'function' || !host.hasAttribute('popover')) {
      host.removeAttribute('popover');
      document.documentElement.append(host);
      return;
    }
    try {
      if (!host.matches(':popover-open')) host.showPopover();
    } catch {
      host.removeAttribute('popover');
      document.documentElement.append(host);
    }
    // If the popover stays closed, the browser forces display:none and the notch never appears.
    requestAnimationFrame(() => {
      if (!SV.alive || !host?.isConnected || !host.hasAttribute('popover')) return;
      let open = false;
      try { open = host.matches(':popover-open'); } catch { open = false; }
      if (open) return;
      host.removeAttribute('popover');
      hostStyle(host);
      document.documentElement.append(host);
    });
  }

  // A modal dialog or fullscreen element stays above a popover that is not inside it.
  // Move the notch into that element, then show it again so it is the top layer there.
  let restacking = false;
  function restack() {
    if (!SV.alive || !host || restacking) return;
    restacking = true;
    try {
      if (!host.isConnected) document.documentElement.append(host);
      const dialog = [...document.querySelectorAll('dialog[open]')].at(-1);
      const fullscreen = document.fullscreenElement;
      const parent = dialog || (fullscreen && fullscreen !== host && !host.contains(fullscreen) ? fullscreen : document.documentElement);
      const open = host.matches(':popover-open');
      if (host.parentElement !== parent) {
        if (open) try { host.hidePopover(); } catch {}
        parent.append(host);
      }
      if (typeof host.showPopover === 'function' && host.hasAttribute('popover')) {
        try {
          if (host.matches(':popover-open')) host.hidePopover();
          host.showPopover();
        } catch {
          host.removeAttribute('popover');
        }
      }
    } finally {
      restacking = false;
    }
  }

  N.mount = () => {
    host = document.createElement('savisul-notch');
    host.setAttribute('popover', 'manual');
    host.setAttribute('contenteditable', 'false');
    hostStyle(host);
    shadow = host.attachShadow({ mode: 'closed' });
    root = h('div', { class: 'sv', 'data-pos': 'center', 'data-theme': 'dark', 'data-view': 'idle' });
    overlays = h('div', { class: 'overlays' });
    notchEl = h('div', { class: 'notch', role: 'region', tabindex: '-1' });
    layers.idle = h('div', { class: 'layer idle on' });
    layers.home = h('div', { class: 'layer home' });
    layers.panel = h('div', { class: 'layer panel' });
    layers.mode = h('div', { class: 'layer mode' });
    layers.toast = h('div', { class: 'layer toast' });
    notchEl.append(layers.idle, layers.home, layers.panel, layers.mode, layers.toast);
    floatToast = h('div', { class: 'float-toast', role: 'status', 'aria-live': 'polite' });
    root.append(overlays, h('div', { class: 'ears' }), notchEl, floatToast);
    shadow.append(h('style', { text: SV.css }), root);
    SV.root = shadow;
    SV.overlays = overlays;
    SV.uiRoot = root;
    document.documentElement.append(host);
    raise();

    for (const type of ['pointerdown', 'mousedown', 'mouseup', 'click', 'dblclick', 'contextmenu', 'wheel', 'touchstart']) {
      root.addEventListener(type, (event) => event.stopPropagation(), { passive: type === 'wheel' || type === 'touchstart' });
    }
    notchEl.addEventListener('pointerenter', onEnter);
    notchEl.addEventListener('pointerleave', onLeave);
    layers.idle.addEventListener('click', () => N.openHome());

    resizeObserver = new ResizeObserver(() => fit());
    Object.values(layers).forEach((layer) => resizeObserver.observe(layer));

    SV.listen(document, 'pointerdown', (event) => {
      if (!isOpen() || N.pinned) return;
      if (event.composedPath().includes(host)) return;
      N.close();
    }, true);
    SV.listen(window, 'scroll', onScroll, { passive: true });
    SV.listen(document, 'mousemove', onMove, { passive: true });
    let topStamp = '';
    const topStampNow = () => {
      const dialogs = document.querySelectorAll('dialog[open]').length;
      const fullscreen = document.fullscreenElement ? 1 : 0;
      const others = [...document.querySelectorAll(':popover-open')].filter((node) => node !== host).length;
      return `${fullscreen}.${dialogs}.${others}`;
    };
    const queueRestack = () => {
      clearTimeout(raiseTimer);
      raiseTimer = setTimeout(() => {
        restack();
        topStamp = topStampNow();
      }, 40);
    };
    SV.listen(document, 'toggle', (event) => {
      if (event.target === host) return;
      queueRestack();
    }, true);
    SV.listen(document, 'fullscreenchange', queueRestack, true);
    const topTimer = setInterval(() => {
      const next = topStampNow();
      if (next === topStamp) return;
      topStamp = next;
      if (next !== '0.0.0') restack();
    }, 700);
    topStamp = topStampNow();
    const observer = new MutationObserver(() => {
      if (!host.isConnected && SV.alive) {
        document.documentElement.append(host);
        raise();
      }
    });
    observer.observe(document.documentElement, { childList: true, subtree: true });
    SV.cleanups.push(
      () => observer.disconnect(),
      () => resizeObserver.disconnect(),
      () => clearInterval(topTimer),
      () => clearTimeout(raiseTimer),
      unsubscribeBridge
    );

    SV.onKey(onKey);
    renderIdle();
    fit();
  };

  N.host = () => host;

  // MARK: Layout

  const isOpen = () => N.view === 'home' || N.view === 'panel';

  function fit() {
    const layer = layers[N.view];
    if (!layer || !root) return;
    const width = Math.ceil(layer.offsetWidth);
    const height = Math.ceil(layer.offsetHeight);
    const radius = N.view === 'home' || N.view === 'panel' ? 26 : N.view === 'idle' ? 15 : Math.round(height / 2);
    root.style.setProperty('--w', `${width}px`);
    root.style.setProperty('--h', `${height}px`);
    root.style.setProperty('--r', `${radius}px`);
  }

  function show(view) {
    N.view = view;
    root.dataset.view = view;
    for (const [name, el] of Object.entries(layers)) el.classList.toggle('on', name === view);
    updateRest();
    fit();
  }

  function updateRest() {
    const style = SV.settings?.idle || 'notch';
    const hiddenHere = SV.settings?.hiddenSites?.includes(SV.host);
    const resting = N.view === 'idle';
    const gone = resting && (hiddenHere || (style === 'hidden' && !N.awake));
    const slim = resting && !gone && (style === 'line' ? !N.awake : N.slim && !N.awake);
    root.toggleAttribute('data-gone', gone);
    root.toggleAttribute('data-slim', slim);
  }

  N.applySettings = () => {
    const settings = SV.settings;
    let theme = settings.theme;
    if (theme === 'auto') theme = matchMedia('(prefers-color-scheme: light)').matches ? 'light' : 'dark';
    root.dataset.theme = theme;
    root.dataset.pos = settings.position;
    notchEl.setAttribute('aria-label', t('notchLabel'));
    renderIdle();
    if (N.view === 'home') renderHome();
    if (N.view === 'panel' && N.panel) N.openPanel(N.panel, { keep: true });
    if (N.view === 'mode') renderMode();
    updateRest();
    fit();
  };

  // MARK: Pointer

  function onEnter() {
    N.hovering = true;
    clearTimeout(closeTimer);
    wake(true);
    const resting = () => N.view === 'idle' || N.view === 'toast';
    if (resting() && SV.settings?.hover !== false) {
      clearTimeout(openTimer);
      openTimer = setTimeout(() => {
        if (N.hovering && resting()) N.openHome();
      }, 130);
    }
  }

  function onLeave() {
    N.hovering = false;
    clearTimeout(openTimer);
    scheduleClose();
    scheduleSleep();
  }

  function scheduleClose(delay = 480) {
    clearTimeout(closeTimer);
    if (!isOpen() || N.pinned) return;
    closeTimer = setTimeout(() => {
      if (N.hovering || N.pinned || typingInside()) return;
      N.close();
    }, delay);
  }

  function typingInside() {
    const active = shadow.activeElement;
    return !!active && (active.tagName === 'TEXTAREA' || (active.tagName === 'INPUT' && active.type !== 'range'));
  }

  function wake(on) {
    clearTimeout(wakeTimer);
    if (N.awake === on) return;
    N.awake = on;
    updateRest();
    fit();
  }

  function scheduleSleep() {
    clearTimeout(wakeTimer);
    wakeTimer = setTimeout(() => {
      if (!N.hovering && N.view === 'idle') {
        N.awake = false;
        updateRest();
        fit();
      }
    }, 1400);
  }

  let lastY = window.scrollY;
  let scrollQueued = false;
  function onScroll() {
    if (scrollQueued) return;
    scrollQueued = true;
    requestAnimationFrame(() => {
      scrollQueued = false;
      const y = window.scrollY;
      if (N.view === 'idle' && !N.hovering) {
        if (y > 140 && y > lastY + 3) setSlim(true);
        else if (y < lastY - 24 || y < 80) setSlim(false);
      }
      lastY = y;
    });
  }

  function setSlim(on) {
    if (N.slim === on) return;
    N.slim = on;
    updateRest();
    fit();
  }

  let moveQueued = false;
  function onMove(event) {
    if (event.clientY > 14 || moveQueued || N.view !== 'idle') return;
    moveQueued = true;
    requestAnimationFrame(() => {
      moveQueued = false;
      const rect = notchEl.getBoundingClientRect();
      const center = rect.left + rect.width / 2;
      if (Math.abs(event.clientX - center) < Math.max(150, rect.width / 2 + 40)) {
        wake(true);
        scheduleSleep();
      }
    });
  }

  // MARK: Keys

  function onKey(event) {
    if (event.key !== 'Escape') return false;
    if (N.view === 'panel') {
      if (N.panelDirect) N.close();
      else N.openHome({ focus: true });
      return true;
    }
    if (N.view === 'home') {
      N.close();
      return true;
    }
    return false;
  }

  // MARK: Open and close

  N.openHome = ({ focus = false } = {}) => {
    clearTimeout(openTimer);
    clearTimeout(closeTimer);
    if (!host?.isConnected) return;
    cleanupPanel();
    N.panelDirect = false;
    raise();
    renderHome();
    show('home');
    subscribeBridge();
    loadCommands();
    if (focus) requestAnimationFrame(() => layers.home.querySelector('.tile')?.focus({ preventScroll: true }));
  };

  N.close = () => {
    clearTimeout(openTimer);
    clearTimeout(closeTimer);
    cleanupPanel();
    const active = shadow?.activeElement;
    if (active) active.blur();
    unsubscribeBridge();
    show(N.mode ? 'mode' : 'idle');
    if (!N.hovering) scheduleSleep();
  };

  N.toggle = () => {
    if (isOpen()) N.close();
    else N.openHome({ focus: true });
  };

  N.openSidebar = async (view) => {
    try {
      await SV.send('sidebar:open', { view: view || null });
      N.close();
    } catch {
      SV.toast(t('sbOpenHint'), { icon: 'sidebar', tone: 'info', duration: 4200 });
    }
  };

  N.togglePin = () => {
    N.pinned = !N.pinned;
    if (N.view === 'home') renderHome();
    if (!N.pinned) scheduleClose(900);
  };

  function cleanupPanel() {
    if (N.panelCleanup) {
      try { N.panelCleanup(); } catch {}
    }
    N.panelCleanup = null;
    if (N.view !== 'panel') N.panel = null;
  }

  N.openPanel = (id, { keep = false, direct = false } = {}) => {
    const tool = id === 'settings' ? settingsPanel : SV.tools[id];
    if (!tool?.panel) return;
    clearTimeout(closeTimer);
    raise();
    cleanupPanel();
    N.panel = id;
    if (!keep) N.panelDirect = direct;
    const el = SV.clear(layers.panel);
    const title = h('div', { class: 'title ellipsis' });
    const actions = h('div', { class: 'row', style: { gap: '2px' } });
    const back = iconButton('back', t('back'), () => (N.panelDirect ? N.close() : N.openHome()));
    const head = h('div', { class: 'panel-head' }, back, title, actions, iconButton('x', t('close'), () => N.close()));
    const body = h('div', { class: 'panel-body' });
    el.append(head, body);
    const api = {
      body,
      setTitle: (text) => { title.textContent = text; },
      actions,
      refit: () => fit(),
      close: () => N.close(),
      back: () => N.openHome()
    };
    api.setTitle(tool.title ? tool.title() : t(tool.label));
    N.panelCleanup = tool.panel(api) || null;
    show('panel');
    subscribeBridge();
    requestAnimationFrame(() => {
      const target = body.querySelector('[data-autofocus]');
      if (target) target.focus({ preventScroll: true });
    });
  };

  // MARK: Tools

  SV.runTool = (id) => {
    const tool = SV.tools[id];
    if (!tool) return;
    if (tool.kind === 'panel') {
      N.openPanel(id);
      return;
    }
    if (tool.kind === 'mode' || tool.kind === 'overlay') {
      if (tool.active?.()) {
        tool.stop();
        if (N.view === 'home') renderHome();
        return;
      }
      N.close();
      requestAnimationFrame(() => tool.start());
      return;
    }
    if (tool.kind === 'toggle') {
      tool.toggle();
      if (N.view === 'home') renderHome();
    }
  };

  // MARK: Rendering

  function iconButton(name, label, onClick, { pressed } = {}) {
    return h('button', {
      class: 'iconbtn', type: 'button', title: label, 'aria-label': label,
      'aria-pressed': pressed == null ? null : String(pressed), onclick: onClick
    }, icon(name, 17));
  }
  SV.iconButton = iconButton;

  function renderIdle() {
    const dots = h('div', { class: 'dots' });
    if (N.indicators.live) dots.append(h('span', { class: 'dot live' }));
    if (N.indicators.dark) dots.append(h('span', { class: 'dot dark' }));
    if (N.indicators.note) dots.append(h('span', { class: 'dot note', title: t('noteHas') }));
    SV.clear(layers.idle).append(SV.mark(19), dots);
    layers.idle.setAttribute('title', 'SAVISUL');
    if (N.view === 'idle') fit();
  }

  N.indicate = (name, on) => {
    if (!!N.indicators[name] === !!on) return;
    N.indicators[name] = !!on;
    renderIdle();
    if (N.view === 'home') renderHome();
  };

  function section(title, content, aside) {
    return h('div', { class: 'section' },
      h('div', { class: 'section-title' }, h('span', { text: title }), aside ? h('span', { class: 'aside' }, aside) : null),
      content);
  }

  function renderHome() {
    const el = SV.clear(layers.home);
    el.append(h('div', { class: 'head' },
      SV.mark(18),
      h('span', { class: 'brand', text: 'SAVISUL' }),
      h('span', { class: 'site grow ellipsis', text: SV.site || location.protocol.replace(':', '') }),
      iconButton('sidebar', t('sbOpen'), () => N.openSidebar()),
      iconButton('pin', t('keepOpen'), () => N.togglePin(), { pressed: N.pinned }),
      iconButton('sliders', t('settings'), () => N.openPanel('settings')),
      iconButton('x', t('close'), () => N.close())
    ));

    const grid = h('div', { class: 'grid' });
    for (const id of TOOL_ORDER) {
      const tool = SV.tools[id];
      if (!tool) continue;
      const on = !!tool.active?.();
      grid.append(h('button', {
        class: `tile${on ? ' on' : ''}`, type: 'button', title: t(tool.label), onclick: () => SV.runTool(id)
      },
      h('span', { class: 'glyph' }, icon(tool.icon, 19)),
      h('span', { class: 'label', text: t(tool.label) }),
      tool.badge?.() ? h('span', { class: 'badge' }) : null));
    }
    el.append(section(t('secTools'), grid));

    const chips = h('div', { class: 'chips' });
    for (const id of PAGE_ORDER) {
      const tool = SV.tools[id];
      if (!tool) continue;
      const on = !!tool.active?.();
      chips.append(h('button', {
        class: `chip${on ? ' on' : ''}`, type: 'button', title: t(tool.label), 'aria-pressed': String(on), onclick: () => SV.runTool(id)
      }, icon(tool.icon, 15), h('span', { text: t(tool.label) })));
    }
    el.append(section(t('secPage'), chips));

    const browser = h('div', { class: 'chips' },
      [['tabs', 'tabs', t('sbTabs')], ['sessions', 'save', t('sbSessions')], ['ai', 'sparkle', t('sbAi')]].map(([view, name, label]) => h('button', {
        class: 'chip', type: 'button', title: label, onclick: () => N.openSidebar(view)
      }, icon(name, 15), h('span', { text: label }))),
      h('button', { class: 'chip', type: 'button', title: t('shelfTitle'), onclick: () => SV.shelf?.('link') }, icon('tray', 15), h('span', { text: t('shelfShort') })),
      h('button', { class: 'chip', type: 'button', title: t('sbBookmarks'), onclick: () => N.openSidebar('bookmarks') }, icon('star', 15), h('span', { text: t('sbBookmarks') })),
      h('button', { class: 'chip', type: 'button', title: t('sbNotes'), onclick: () => N.openSidebar('notes') }, icon('note', 15), h('span', { text: t('sbNotes') })));
    el.append(section(t('secBrowser'), browser));

    const mac = h('div', { class: 'mac' });
    const aside = h('span', { class: 'aside' });
    el.append(section(t('secMac'), mac, aside));
    renderMac(mac, aside);

    el.append(renderFoot());
    if (N.view === 'home') fit();
  }

  function renderFoot() {
    const foot = h('div', { class: 'foot' });
    const labels = { 'toggle-notch': 'SAVISUL', reader: t('tReader'), 'full-screenshot': t('tShot'), dark: t('pDark') };
    const list = (N.commands || []).filter((command) => labels[command.name] && command.shortcut);
    if (!list.length) return foot;
    for (const command of list.slice(0, 4)) {
      foot.append(h('span', null, h('kbd', { text: command.shortcut }), labels[command.name]));
    }
    return foot;
  }

  async function loadCommands() {
    if (N.commands) return;
    try {
      N.commands = (await SV.send('commands')).commands;
      if (N.view === 'home') {
        const old = layers.home.querySelector('.foot');
        old?.replaceWith(renderFoot());
        fit();
      }
    } catch {}
  }

  // MARK: Mac

  function subscribeBridge() {
    if (bridgePort || !SV.contextOK()) return;
    try {
      bridgePort = chrome.runtime.connect({ name: 'bridge' });
    } catch {
      return;
    }
    bridgePort.onMessage.addListener((message) => {
      if (message.type !== 'bridge') return;
      N.bridge = message;
      SV.emit('bridge', message);
      refreshMac();
    });
    bridgePort.onDisconnect.addListener(() => { bridgePort = null; });
  }

  function unsubscribeBridge() {
    if (!bridgePort) return;
    try { bridgePort.disconnect(); } catch {}
    bridgePort = null;
  }

  SV.bridge = async (body, timeout) => {
    const reply = await SV.send('bridge:request', { body, timeout });
    if (reply.bridge) {
      N.bridge = reply.bridge;
      SV.emit('bridge', reply.bridge);
      refreshMac();
    }
    return reply;
  };

  let macTimer = 0;
  function refreshMac() {
    clearTimeout(macTimer);
    if (N.view !== 'home') return;
    const mac = layers.home.querySelector('.mac');
    if (!mac) return;
    if (Date.now() < volumeHold || mac.querySelector('.volume input:active')) {
      macTimer = setTimeout(refreshMac, 450);
      return;
    }
    renderMac(mac, mac.parentElement.querySelector('.aside'));
    fit();
  }

  function macButton(name, label, on, onClick, busy) {
    return h('button', {
      class: `mac-btn${on ? ' on' : ''}${busy ? ' busy' : ''}`, type: 'button', title: label, 'aria-pressed': String(!!on), onclick: onClick
    }, busy ? h('span', { class: 'spinner' }) : icon(name, 18), h('span', { text: label }));
  }

  function renderMac(mac, aside) {
    const { status, state } = N.bridge;
    SV.clear(mac);
    if (aside) SV.clear(aside);
    if (status !== 'ready' || !state) {
      if (status === 'offline') {
        mac.append(h('div', { class: 'mac-note' },
          icon('laptop', 18),
          h('span', { class: 'grow', text: t('macOffline') }),
          h('button', {
            class: 'btn small primary', type: 'button', onclick: async (event) => {
              const button = event.currentTarget;
              SV.clear(button).append(h('span', { class: 'spinner' }));
              try { await SV.bridge({ type: 'launch' }, 15000); } catch { SV.toast(t('macError'), { icon: 'laptop', tone: 'warn' }); }
              refreshMac();
            }
          }, t('macLaunch'))));
      } else if (status === 'missing') {
        mac.append(h('div', { class: 'mac-note' }, icon('laptop', 18), h('span', { class: 'grow muted', text: t('macMissing') })));
      } else {
        mac.append(h('div', { class: 'mac-note' }, h('span', { class: 'spinner' }), h('span', { class: 'grow muted', text: t('macConnecting') })));
      }
      return;
    }

    const lid = state.lid || {};
    const audio = state.audio || {};
    const row = h('div', { class: 'mac-row' },
      macButton('laptop', t('macLid'), lid.on, async () => {
        if (!lid.on) SV.toast(t('macLidPassword'), { icon: 'laptop', tone: 'info' });
        try { await SV.bridge({ type: 'set', key: 'lid', value: !lid.on }, 120000); } catch {}
      }, lid.busy),
      macButton('coffee', t('macAwake'), state.idle?.on, () => SV.bridge({ type: 'set', key: 'idle', value: !state.idle?.on }).catch(() => {})),
      macButton('displayOff', t('macDisplay'), false, async () => {
        SV.toast(t('macDisplayDone'), { icon: 'displayOff', tone: 'info' });
        await SV.sleep(700);
        SV.bridge({ type: 'displayOff' }).catch(() => {});
      }),
      macButton(audio.muted ? 'speakerOff' : 'speaker', t('macMute'), audio.muted, () => SV.bridge({ type: 'set', key: 'mute', value: !audio.muted }).catch(() => {}))
    );
    mac.append(row);

    if (lid.confirm) {
      mac.append(h('div', { class: 'confirm' },
        h('span', { class: 'grow', text: t('macLidBattery') }),
        h('button', { class: 'btn small', type: 'button', onclick: () => SV.bridge({ type: 'lidCancel' }).catch(() => {}) }, t('macCancel')),
        h('button', { class: 'btn small primary', type: 'button', onclick: () => SV.bridge({ type: 'lidConfirm' }, 120000).catch(() => {}) }, t('macTurnOn'))));
    }

    if (audio.hasVolume) {
      const value = Math.round((audio.volume ?? 0) * 100);
      const label = h('span', { class: 'value', text: I.percent(value) });
      const slider = h('input', { type: 'range', min: '0', max: '100', step: '1', value: String(value), 'aria-label': t('macVolume') });
      slider.style.setProperty('--p', `${value}%`);
      let pending = null;
      let sending = false;
      const push = async () => {
        if (sending || pending == null) return;
        sending = true;
        const next = pending;
        pending = null;
        try { await SV.bridge({ type: 'set', key: 'volume', value: next / 100 }); } catch {}
        sending = false;
        if (pending != null) push();
      };
      slider.addEventListener('input', () => {
        const v = Number(slider.value);
        slider.style.setProperty('--p', `${v}%`);
        label.textContent = I.percent(v);
        volumeHold = Date.now() + 900;
        pending = v;
        push();
      });
      mac.append(h('div', { class: 'volume', title: audio.device || '' }, icon(audio.muted ? 'speakerOff' : 'speaker', 16), slider, label));
    }

    if (aside) {
      const battery = state.battery;
      if (battery?.present) {
        aside.append(h('span', { text: battery.charging ? t('macCharging', I.percent(battery.percent)) : t('macBattery', I.percent(battery.percent)) }));
      } else if (battery && !battery.present) {
        aside.append(h('span', { text: t('macAdapter') }));
      }
      if (typeof state.cpu === 'number') aside.append(h('span', { text: t('macCpu', I.percent(state.cpu)) }));
    }
  }

  // MARK: Settings panel

  function seg(items, selected, onSelect) {
    return h('div', { class: 'seg', role: 'group' }, items.map(([value, label]) => h('button', {
      type: 'button', 'aria-pressed': String(value === selected), onclick: () => onSelect(value)
    }, label)));
  }

  function toggle(on, label, onChange) {
    return h('button', {
      class: 'switch', type: 'button', role: 'switch', 'aria-checked': String(!!on), 'aria-label': label,
      onclick: (event) => {
        const next = event.currentTarget.getAttribute('aria-checked') !== 'true';
        event.currentTarget.setAttribute('aria-checked', String(next));
        onChange(next);
      }
    });
  }
  SV.toggleSwitch = toggle;
  SV.seg = seg;

  const settingsPanel = {
    title: () => t('settings'),
    panel(api) {
      const s = SV.settings;
      const save = (patch) => SV_STORE.save(patch);
      const hidden = s.hiddenSites.includes(SV.host);
      const card = h('div', { class: 'card', style: { padding: '4px 12px' } },
        h('div', { class: 'setting' }, h('span', { class: 'name', text: t('setLanguage') }),
          seg([['auto', t('setLangMac')], ['en', 'EN'], ['ru', 'RU'], ['uk', 'UK'], ['fr', 'FR']], s.language, (language) => save({ language }))),
        h('div', { class: 'setting' }, h('span', { class: 'name', text: t('setPosition') }),
          seg([['left', t('posLeft')], ['center', t('posCenter')], ['right', t('posRight')]], s.position, (position) => save({ position }))),
        h('div', { class: 'setting' }, h('span', { class: 'name', text: t('setIdle') }),
          seg([['notch', t('idleNotch')], ['line', t('idleLine')], ['hidden', t('idleHidden')]], s.idle, (idle) => save({ idle }))),
        h('div', { class: 'setting' }, h('span', { class: 'name', text: t('setTheme') }),
          seg([['dark', t('themeDark')], ['light', t('themeLight')], ['auto', t('setAuto')]], s.theme, (theme) => save({ theme }))),
        h('div', { class: 'setting' }, h('span', { class: 'name', text: t('setHover') }),
          toggle(s.hover, t('setHover'), (hover) => save({ hover }))),
        SV.host ? h('div', { class: 'setting' }, h('span', { class: 'name ellipsis', text: t('setHideSite', SV.site) }),
          toggle(hidden, t('setHideSite', SV.site), (on) => {
            const sites = new Set(SV.settings.hiddenSites);
            if (on) sites.add(SV.host);
            else sites.delete(SV.host);
            save({ hiddenSites: [...sites] });
            if (on) SV.toast(t('setHidden', SV.host), { icon: 'eyeOff', tone: 'info', duration: 3600 });
          })) : null
      );
      const links = h('div', { class: 'row', style: { 'justify-content': 'flex-end', gap: '6px' } },
        h('button', { class: 'btn small', type: 'button', onclick: () => SV.send('open', { url: 'chrome://extensions/shortcuts' }) }, icon('keyboard', 15), t('shortcuts')),
        h('button', { class: 'btn small', type: 'button', onclick: () => SV.send('open', { url: 'options' }) }, icon('external', 15), t('allSettings')));
      api.body.append(card, links);
      return null;
    }
  };

  // MARK: Modes

  function renderMode() {
    const mode = N.mode;
    const el = SV.clear(layers.mode);
    if (!mode) return;
    el.append(h('span', { class: 'live' }), icon(mode.icon, 16), h('span', { class: 'name', text: mode.name }));
    if (mode.hint) el.append(h('span', { class: 'what', text: mode.hint }));
    const actions = h('div', { class: 'actions' });
    for (const action of mode.actions || []) {
      if (action === '|') {
        actions.append(h('span', { class: 'sep' }));
        continue;
      }
      if (action.node) {
        actions.append(action.node);
        continue;
      }
      actions.append(h('button', {
        class: `btn small${action.primary ? ' primary' : ''}`, type: 'button', title: action.title || action.label,
        onclick: action.run, disabled: action.disabled
      }, action.icon ? icon(action.icon, 14) : null, action.label));
    }
    actions.append(iconButton('x', `${t('done')} · Esc`, () => SV.mode.exit()));
    el.append(actions);
    if (N.view === 'mode') fit();
  }

  SV.mode = {
    enter(mode) {
      if (N.mode && N.mode.id !== mode.id) SV.mode.exit();
      N.mode = mode;
      N.indicate('live', true);
      renderMode();
      if (!isOpen()) show('mode');
    },
    update(patch) {
      if (!N.mode) return;
      Object.assign(N.mode, patch);
      renderMode();
    },
    exit(id) {
      if (!N.mode || (id && N.mode.id !== id)) return;
      const mode = N.mode;
      N.mode = null;
      N.indicate('live', false);
      try { mode.onExit?.(); } catch (error) { console.error(error); }
      if (N.view === 'mode' || (N.view === 'toast' && toastReturn === 'mode')) {
        if (N.view === 'toast') toastReturn = 'idle';
        else show('idle');
      }
    },
    active: (id) => !!N.mode && (id === undefined || N.mode.id === id)
  };

  // MARK: Toast

  SV.toast = (text, { icon: name = 'check', tone = 'ok', duration = 2300 } = {}) => {
    if (!root) return;
    if (isOpen()) {
      clearTimeout(floatTimer);
      SV.clear(floatToast).append(icon(name, 16), h('span', { text }));
      floatToast.dataset.tone = tone;
      floatToast.classList.add('on');
      floatTimer = setTimeout(() => floatToast.classList.remove('on'), duration);
      return;
    }
    clearTimeout(toastTimer);
    if (N.view !== 'toast') toastReturn = N.view;
    SV.clear(layers.toast).append(icon(name, 16), h('span', { text }));
    layers.toast.dataset.tone = tone;
    show('toast');
    toastTimer = setTimeout(() => {
      if (N.view !== 'toast') return;
      show(N.mode ? 'mode' : 'idle');
    }, duration);
  };

  // MARK: Overlay helpers

  SV.overlay = (className) => {
    const el = h('div', { class: className });
    overlays.append(el);
    raise();
    return el;
  };

  SV.hideUI = (hidden) => {
    root?.toggleAttribute('data-hidden', hidden);
  };
})();
