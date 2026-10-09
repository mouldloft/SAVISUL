(() => {
  const { h, icon } = SV;
  const I = SV_I18N;
  const t = (...args) => I.t(...args);
  const ORDER = ['tabs', 'sessions', 'bookmarks', 'notes', 'ai'];

  const app = document.getElementById('app');
  let head, nav, body, footer;
  let cleanup = null;
  const tabListeners = new Set();

  const Sidebar = {
    views: {},
    current: null,
    tab: null,
    windowId: null,
    settings: null,

    register(id, view) {
      Sidebar.views[id] = view;
      if (Sidebar.ready && Sidebar.current === id) Sidebar.show(id);
      if (Sidebar.ready) renderNav();
    },

    show(id) {
      if (!Sidebar.views[id]) {
        // The AI view is an ES module and may register a moment later; register() shows it then.
        if (ORDER.includes(id)) {
          Sidebar.current = id;
          renderNav();
          return;
        }
        id = 'tabs';
      }
      if (cleanup) {
        try { cleanup(); } catch {}
      }
      cleanup = null;
      Sidebar.current = id;
      chrome.storage.local.set({ sidebarLast: id }).catch(() => {});
      renderNav();
      SV.clear(body);
      SV.clear(footer);
      footer.hidden = true;
      body.scrollTop = 0;
      const view = Sidebar.views[id];
      cleanup = view.render({ body, footer, refresh: () => Sidebar.show(id) }) || null;
    },

    // Re-run the current view's own refresh hook (keeps scroll and inputs) or re-render it.
    refresh() {
      const view = Sidebar.views[Sidebar.current];
      if (view?.update) view.update();
      else if (Sidebar.current) Sidebar.show(Sidebar.current);
    },

    onTabs(listener) {
      tabListeners.add(listener);
      return () => tabListeners.delete(listener);
    },

    favicon(url, size = 32) {
      if (!url || !/^(https?|file):/.test(url)) return chrome.runtime.getURL('icons/icon32.png');
      return chrome.runtime.getURL(`/_favicon/?pageUrl=${encodeURIComponent(url)}&size=${size}`);
    },

    hostOf: (url) => SV_STORE.hostOf(url || '') || (url || '').replace(/^([a-z-]+:)\/*/, '$1'),

    iconButton(name, label, onClick, { pressed, danger } = {}) {
      return h('button', {
        class: `iconbtn${danger ? ' danger' : ''}`, type: 'button', title: label, 'aria-label': label,
        'aria-pressed': pressed == null ? null : String(pressed),
        onclick: (event) => { event.stopPropagation(); onClick(event); }
      }, icon(name, 16));
    },

    empty(iconName, text) {
      return h('div', { class: 'empty' }, icon(iconName, 28), h('div', { text }));
    },

    search(placeholder, onInput, value = '') {
      const input = h('input', { type: 'search', placeholder, value, spellcheck: 'false', autocomplete: 'off' });
      input.addEventListener('input', () => onInput(input.value));
      return { el: h('label', { class: 'search' }, icon('search', 16), input), input };
    },

    async focusTab(tab) {
      await chrome.tabs.update(tab.id, { active: true });
      await chrome.windows.update(tab.windowId, { focused: true });
    },

    // Page text for the AI view. Uses the content script's digest when it is there, injects it when not.
    async readTab(tab, max = 60000) {
      const base = { title: tab.title || '', url: tab.url || '', host: Sidebar.hostOf(tab.url), text: '', selection: '' };
      if (!/^(https?|file):/.test(tab.url || '') || /^https:\/\/(chromewebstore\.google\.com|chrome\.google\.com\/webstore)/.test(tab.url)) {
        return { ...base, error: 'restricted' };
      }
      if (tab.discarded) return { ...base, error: 'suspended' };
      const ask = async () => {
        const [result] = await chrome.scripting.executeScript({
          target: { tabId: tab.id },
          func: (limit) => globalThis.SV?.digest?.({ max: limit }) ?? null,
          args: [max]
        });
        return result?.result || null;
      };
      try {
        let digest = await ask();
        if (!digest) {
          const files = chrome.runtime.getManifest().content_scripts.flatMap((entry) => entry.js);
          await chrome.scripting.executeScript({ target: { tabId: tab.id }, files });
          digest = await ask();
        }
        if (digest) return { ...base, ...digest };
        const [plain] = await chrome.scripting.executeScript({
          target: { tabId: tab.id },
          func: (limit) => ({ title: document.title, url: location.href, text: (document.body?.innerText || '').slice(0, limit), selection: String(getSelection() || '') }),
          args: [max]
        });
        return { ...base, ...(plain?.result || {}) };
      } catch {
        return { ...base, error: 'restricted' };
      }
    },

    toast: (...args) => Page.toast(...args),
    when: (...args) => Page.when(...args)
  };
  globalThis.Sidebar = Sidebar;

  // MARK: Shell

  function renderHead() {
    const tab = Sidebar.tab;
    SV.clear(head).append(
      SV.mark(18),
      h('span', { class: 'brand', text: 'SAVISUL' }),
      h('span', { class: 'site grow ellipsis', text: /^(https?|file):/.test(tab?.url || '') ? Sidebar.hostOf(tab.url) : '' }),
      Sidebar.iconButton('sliders', t('allSettings'), () => chrome.runtime.openOptionsPage()));
  }

  function renderNav() {
    const labels = { tabs: t('sbTabs'), sessions: t('sbSessions'), bookmarks: t('sbBookmarks'), notes: t('sbNotes'), ai: t('sbAi') };
    const icons = { tabs: 'tabs', sessions: 'save', bookmarks: 'star', notes: 'note', ai: 'sparkle' };
    SV.clear(nav).append(...ORDER.map((id) => h('button', {
      type: 'button', 'aria-pressed': String(Sidebar.current === id), title: labels[id],
      onclick: () => Sidebar.show(id)
    }, icon(icons[id], 18), h('span', { text: labels[id] }))));
  }

  // MARK: Live state

  let tabTimer = 0;
  function tabsChanged(kind) {
    clearTimeout(tabTimer);
    tabTimer = setTimeout(() => {
      for (const listener of tabListeners) {
        try { listener(kind); } catch (error) { console.error('SAVISUL sidebar', error); }
      }
    }, 120);
  }

  async function trackActive() {
    const [tab] = await chrome.tabs.query({ active: true, windowId: Sidebar.windowId });
    const changed = tab?.id !== Sidebar.tab?.id || tab?.url !== Sidebar.tab?.url;
    Sidebar.tab = tab || null;
    renderHead();
    if (changed) tabsChanged('active');
  }

  function listen() {
    for (const event of ['onCreated', 'onRemoved', 'onMoved', 'onAttached', 'onDetached', 'onReplaced']) {
      chrome.tabs[event].addListener(() => tabsChanged('tabs'));
    }
    chrome.tabs.onUpdated.addListener((tabId, info) => {
      if (!('title' in info || 'url' in info || 'status' in info || 'discarded' in info || 'pinned' in info || 'audible' in info || 'groupId' in info || 'favIconUrl' in info)) return;
      if (tabId === Sidebar.tab?.id) trackActive();
      else tabsChanged('tabs');
    });
    chrome.tabs.onActivated.addListener((info) => {
      if (info.windowId === Sidebar.windowId) trackActive();
      else tabsChanged('tabs');
    });
    for (const event of ['onCreated', 'onRemoved', 'onUpdated', 'onMoved']) chrome.tabGroups?.[event]?.addListener(() => tabsChanged('groups'));
    chrome.storage.onChanged.addListener((changes, area) => {
      if (area === 'session' && changes.sidebarStamp) {
        chrome.storage.session.get('sidebarView').then(({ sidebarView }) => {
          if (sidebarView && sidebarView !== Sidebar.current) Sidebar.show(sidebarView);
          Sidebar.views[Sidebar.current]?.onRequest?.();
        });
      }
      if (area === 'local' && (changes.theme || changes.language || changes.appLanguage)) {
        for (const key of ['theme', 'language']) if (changes[key]) Page.settings[key] = changes[key].newValue ?? SV_STORE.DEFAULTS[key];
        if (changes.appLanguage) Page.appLanguage = changes.appLanguage.newValue || null;
        I.lang = I.resolve(Page.settings.language, Page.appLanguage);
        Page.applyTheme();
        renderHead();
        Sidebar.show(Sidebar.current);
      }
    });
  }

  async function boot() {
    Sidebar.settings = await Page.init();
    const win = await chrome.windows.getCurrent();
    Sidebar.windowId = win.id;
    head = h('div', { class: 'sb-head' });
    nav = h('nav', { class: 'sb-nav' });
    body = h('main', { class: 'sb-body' });
    footer = h('div', { class: 'composer', hidden: true });
    app.append(head, nav, body, footer);
    listen();
    await trackActive();
    const { sidebarView } = await chrome.storage.session.get('sidebarView');
    const { sidebarLast } = await chrome.storage.local.get('sidebarLast');
    Sidebar.ready = true;
    Sidebar.show(sidebarView || sidebarLast || 'tabs');
    chrome.storage.session.remove('sidebarView').catch(() => {});
  }

  Sidebar.booted = boot();
})();
