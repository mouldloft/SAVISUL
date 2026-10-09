(async () => {
  const I = SV_I18N;
  const t = (...args) => I.t(...args);
  const { h, icon } = SV;

  let settings = await Page.init();
  const app = document.getElementById('app');
  const version = chrome.runtime.getManifest().version;

  // [id, icon, label, description, command]
  const GROUPS = [
    ['groupTools', [
      ['color', 'pipette', 'tColor', 'dColor', 'color'], ['ruler', 'ruler', 'tRuler', 'dRuler', 'ruler'], ['notes', 'note', 'tNote', 'dNote', 'notes'],
      ['shot', 'camera', 'tShot', 'dShot', 'full-screenshot'], ['zapper', 'eyeOff', 'tZap', 'dZap', 'zapper'], ['fonts', 'type', 'tFonts', 'dFonts'],
      ['inspect', 'inspect', 'tInspect', 'dInspect', 'inspect'], ['link', 'link', 'tLink', 'dLink'], ['tables', 'table', 'tData', 'dData'],
      ['translate', 'translate', 'tTranslate', 'dTranslate', 'translate'], ['export', 'download', 'tExport', 'dExport'],
      ['video', 'play', 'tVideo', 'dVideo'], ['media', 'film', 'tMedia', 'dMedia'], ['images', 'image', 'tImages', 'dImages'], ['speak', 'wave', 'tSpeak', 'dSpeak']
    ]],
    ['groupPage', [
      ['reader', 'book', 'tReader', 'dReader', 'reader'], ['dark', 'moon', 'pDark', 'dDark', 'dark'], ['unlock', 'unlock', 'pUnlock', 'dUnlock'],
      ['edit', 'pencil', 'pEdit', 'dEdit'], ['outline', 'outline', 'pOutline', 'dOutline']
    ]],
    ['groupBrowser', [
      ['sidebar', 'sidebar', 'sbOpen', 'dSidebar', 'sidebar'], ['tabs', 'tabs', 'sbTabs', 'dTabs'], ['sessions', 'save', 'sbSessions', 'dSessions'],
      ['ai', 'sparkle', 'sbAi', 'dAi'], ['shelf', 'tray', 'shelfTitle', 'dShelf'], ['mac', 'laptop', 'secMac', 'dMac']
    ]]
  ];

  const DEMO_STEPS = [
    ['notch', 'sparkle', 'demoNotch', 'demoNotchD'],
    ['reader', 'book', 'demoReader', 'demoReaderD'],
    ['dark', 'moon', 'demoDark', 'demoDarkD'],
    ['inspect', 'inspect', 'demoInspect', 'demoInspectD'],
    ['data', 'table', 'demoData', 'demoDataD'],
    ['translate', 'translate', 'demoTranslate', 'demoTranslateD'],
    ['export', 'download', 'demoExport', 'demoExportD'],
    ['notes', 'note', 'demoNotes', 'demoNotesD']
  ];

  let commands = [];
  let notes = [];
  let query = '';
  let bridge = { status: 'idle', state: null };

  const kbd = (text) => h('kbd', { text });
  const keys = (shortcut) => {
    if (!shortcut) return [];
    const parts = shortcut.includes('+') ? shortcut.split('+') : shortcut.match(/[⌃⌥⇧⌘]|[^⌃⌥⇧⌘]+/g) || [shortcut];
    return parts.map((part) => kbd(part));
  };
  const shortcutOf = (name) => commands.find((c) => c.name === name)?.shortcut || '';

  function download(name, text, type) {
    const url = URL.createObjectURL(new Blob([text], { type }));
    const a = h('a', { href: url, download: name });
    document.body.append(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 4000);
  }

  async function openSidebar() {
    try {
      const win = await chrome.windows.getCurrent();
      await chrome.sidePanel.open({ windowId: win.id });
    } catch {
      Page.toast(t('sbOpenHint'), { icon: 'sidebar', tone: 'warn', duration: 4200 });
    }
  }

  // MARK: Header and hero

  function header() {
    const link = (id, label) => h('a', { href: `#${id}`, text: label });
    return h('header', { class: 'top' },
      h('a', { class: 'brand', href: '#top', 'aria-label': 'SAVISUL' }, SV.mark(22), h('span', { class: 'name', text: 'SAVISUL' })),
      h('span', { class: 'version', text: version }),
      h('nav', null,
        link('demo', t('navDemo')), link('features', t('navFeatures')), link('mac', 'Mac'),
        link('settings', t('navSettings')), link('notes', t('optNotes')), link('shortcuts', t('optShortcuts'))));
  }

  function hero() {
    const toggle = shortcutOf('toggle-notch');
    const welcome = location.hash === '#welcome';
    return h('div', { class: 'hero', id: 'top' },
      h('div', { class: 'hero-notch', 'aria-hidden': 'true' }, SV.mark(19)),
      h('h1', { text: t('heroTitle') }),
      h('p', { class: 'lead', text: t('heroBody') }),
      h('div', { class: 'cta' },
        h('a', { class: 'btn primary large', href: '#demo' }, icon('sparkle', 16), t('heroTry')),
        h('button', { class: 'btn large', type: 'button', onclick: openSidebar }, icon('sidebar', 16), t('heroSidebar'))),
      toggle ? h('div', { class: 'keys' }, ...keys(toggle), h('span', { text: t('optOpenNotch') })) : null,
      welcome ? h('div', { class: 'welcome', role: 'status' }, icon('check', 18),
        h('div', null, h('b', { text: t('optWelcomeTitle') }), ' ', h('span', { text: t('optWelcomeBody') }))) : null);
  }

  // MARK: Live demo

  // The frame outlives re-renders: detaching an iframe reloads it, so a language change only swaps the text around it.
  const Demo = { frame: null, loading: null, active: null };
  const demoControl = () => Demo.frame?.contentWindow?.SAVISUL_DEMO;
  async function demoReady() {
    for (let i = 0; i < 80; i++) {
      if (demoControl()?.ready()) return true;
      await SV.sleep(100);
    }
    return false;
  }
  const markStep = () => document.querySelectorAll('#demo .step').forEach((b) => b.setAttribute('aria-pressed', String(b.dataset.step === Demo.active)));

  function demoSide() {
    const list = h('div', { class: 'demo-steps', role: 'list' });
    for (const [id, name, title, detail] of DEMO_STEPS) {
      list.append(h('button', {
        class: 'step', type: 'button', role: 'listitem', 'aria-pressed': String(id === Demo.active), dataset: { step: id },
        onclick: async () => {
          if (!(await demoReady())) return;
          Demo.active = id;
          markStep();
          Demo.frame.focus();
          demoControl().run(id);
        }
      },
      h('span', { class: 'step-icon' }, icon(name, 17)),
      h('span', { class: 'step-text' }, h('span', { class: 'step-title', text: t(title) }), h('span', { class: 'step-detail', text: t(detail) }))));
    }
    const reset = h('button', {
      class: 'btn small ghost', type: 'button', onclick: () => {
        Demo.active = null;
        markStep();
        Demo.loading.hidden = false;
        Demo.frame.contentWindow?.location.reload();
      }
    }, icon('restore', 14), t('demoReset'));
    return h('div', { class: 'demo-side' },
      h('h2', { class: 'display', text: t('demoTitle') }),
      h('p', { class: 'muted', text: t('demoBody') }),
      list,
      reset);
  }

  function demo() {
    const frame = h('iframe', {
      class: 'demo-frame', src: 'demo.html', title: t('demoTitle'), loading: 'eager',
      allow: 'clipboard-write; clipboard-read'
    });
    const loading = h('div', { class: 'demo-loading' }, h('span', { class: 'spinner' }), h('span', { text: t('demoLoading') }));
    const stage = h('div', { class: 'demo-stage' }, frame, loading);
    Object.assign(Demo, { frame, loading, active: null });
    frame.addEventListener('load', async () => {
      if (await demoReady()) loading.hidden = true;
    });

    const browser = h('div', { class: 'browser' },
      h('div', { class: 'browser-top' },
        h('span', { class: 'lights', 'aria-hidden': 'true' }, h('i'), h('i'), h('i')),
        h('span', { class: 'tab' }, h('span', { class: 'tab-fav', 'aria-hidden': 'true', text: 'R' }), h('span', { class: 'ellipsis', text: 'The Quiet Engineering of Night Trains' }))),
      h('div', { class: 'browser-bar' },
        h('span', { class: 'nav-icons', 'aria-hidden': 'true' }, icon('back', 15), h('span', { class: 'flip' }, icon('back', 15)), icon('refresh', 14)),
        h('span', { class: 'omnibox' }, icon('unlock', 13), h('span', { class: 'host', text: 'railwayreview.example' }), h('span', { class: 'path', text: '/night-trains' })),
        h('span', { class: 'ext', title: 'SAVISUL' }, SV.mark(15))),
      stage);

    return h('section', { id: 'demo', class: 'demo' }, demoSide(), h('div', { class: 'demo-window' }, browser));
  }

  // MARK: Features

  function features() {
    return h('section', { id: 'features' },
      h('h2', { class: 'display', text: t('featTitle') }),
      h('div', { class: 'groups' }, GROUPS.map(([title, items]) => h('div', { class: 'group' },
        h('h3', { text: t(title) }),
        h('ul', { class: 'feature-list' }, items.map(([id, name, label, detail, command]) => {
          const shortcut = command ? shortcutOf(command) : '';
          return h('li', { class: 'feature', dataset: { id } },
            h('span', { class: 'feature-icon' }, icon(name, 17)),
            h('span', { class: 'feature-text' },
              h('span', { class: 'feature-name' }, t(label), shortcut ? h('span', { class: 'shortcut' }, ...keys(shortcut)) : null),
              h('span', { class: 'feature-detail', text: t(detail) })));
        }))))));
  }

  // MARK: Mac

  function languageSource() {
    const name = I.NATIVE[I.lang] || I.lang;
    if (I.LANGS.includes(settings.language)) return t('syncLangSet', I.NATIVE[settings.language]);
    if (I.LANGS.includes(Page.appLanguage)) return t('syncLangMac', name);
    return t('syncLangDefault');
  }

  function mac() {
    const dot = h('span', { class: 'status-dot' });
    const title = h('span', { class: 'status-title', text: t('macConnecting') });
    const action = h('div', { class: 'status-action' });
    const language = h('div', { class: 'status-value', text: languageSource() });
    const follow = Page.toggle(!I.LANGS.includes(settings.language), t('syncFollow'), (on) => {
      SV_STORE.save({ language: on ? 'auto' : I.lang });
    });
    const panel = h('div', { class: 'mac-panel' },
      h('div', { class: 'mac-head' },
        h('div', { class: 'mac-glyph' }, SV.mark(24)),
        h('div', { class: 'grow' }, h('div', { class: 'row' }, dot, title), h('div', { class: 'muted small', text: t('optMacDetail') })),
        action),
      h('div', { class: 'mac-row' },
        h('div', { class: 'grow' }, h('div', { class: 'label', text: t('syncLang') }), language),
        h('label', { class: 'follow' }, h('span', { text: t('syncFollow') }), follow)));

    const update = async () => {
      try { bridge = await SV.send('bridge:status'); } catch { bridge = { status: 'missing' }; }
      SV.clear(action);
      dot.className = 'status-dot';
      if (bridge.status === 'ready') {
        dot.classList.add('on');
        title.textContent = t('optMacConnected', bridge.state?.app?.version || '');
      } else if (bridge.status === 'offline') {
        dot.classList.add('warn');
        title.textContent = t('optMacOffline');
        action.append(h('button', {
          class: 'btn small primary', type: 'button', onclick: async (event) => {
            const button = event.currentTarget;
            button.disabled = true;
            button.replaceChildren(h('span', { class: 'spinner' }), t('macLaunch'));
            try { await SV.send('bridge:request', { body: { type: 'launch' }, timeout: 15000 }); } catch {}
            update();
          }
        }, t('macLaunch')));
      } else {
        title.textContent = t('optMacMissing');
      }
      language.textContent = languageSource();
    };
    update();

    return h('section', { id: 'mac', class: 'mac' },
      h('div', { class: 'mac-copy' },
        h('h2', { class: 'display', text: t('syncTitle') }),
        h('p', { class: 'muted', text: t('syncBody') }),
        h('ul', { class: 'checks' }, ['syncP1', 'syncP2', 'syncP3', 'syncP4'].map((key) => h('li', null, icon('check', 16), h('span', { text: t(key) }))))),
      panel);
  }

  // MARK: Settings and lists

  function item(label, control, detail) {
    return h('div', { class: 'item' },
      h('div', { class: 'grow' }, h('div', { class: 'label', text: label }), detail ? h('div', { class: 'detail', text: detail }) : null),
      control);
  }

  function general() {
    const save = (patch) => SV_STORE.save(patch);
    const list = h('div', { class: 'card list' },
      item(t('setLanguage'), Page.seg([['auto', t('setFollowMac')], ...I.LANGS.map((code) => [code, I.NATIVE[code]])], settings.language, (language) => save({ language })), languageSource()),
      item(t('setPosition'), Page.seg([['left', t('posLeft')], ['center', t('posCenter')], ['right', t('posRight')]], settings.position, (position) => save({ position }))),
      item(t('setIdle'), Page.seg([['notch', t('idleNotch')], ['line', t('idleLine')], ['hidden', t('idleHidden')]], settings.idle, (idle) => save({ idle }))),
      item(t('setTheme'), Page.seg([['dark', t('themeDark')], ['light', t('themeLight')], ['auto', t('setAuto')]], settings.theme, (theme) => save({ theme }))),
      item(t('setHover'), Page.toggle(settings.hover, t('setHover'), (hover) => save({ hover }))));
    for (const host of settings.hiddenSites) {
      list.append(item(t('setHideSite', host), Page.toggle(true, t('setHideSite', host), (on) => {
        if (!on) save({ hiddenSites: settings.hiddenSites.filter((h2) => h2 !== host) });
      })));
    }
    return h('section', { id: 'settings', class: 'narrow' }, h('h2', { class: 'label-head', text: t('navSettings') }), list);
  }

  function shortcuts() {
    const list = h('div', { class: 'card list' });
    for (const command of commands.filter((c) => !c.name.startsWith('_'))) {
      list.append(item(command.description || command.name,
        command.shortcut ? h('div', { class: 'row', style: { gap: '4px' } }, ...keys(command.shortcut)) : h('span', { class: 'faint', text: t('optNotSet') })));
    }
    return h('section', { id: 'shortcuts', class: 'narrow' },
      h('h2', { class: 'label-head' }, t('optShortcuts'), h('span', { class: 'spacer' }),
        h('button', { class: 'btn small', type: 'button', onclick: () => chrome.tabs.create({ url: 'chrome://extensions/shortcuts' }) }, icon('keyboard', 14), t('optShortcutsChange'))),
      list);
  }

  function noteItem(note) {
    const remove = async () => {
      await chrome.storage.local.remove(note.key);
      Page.toast(t('noteDeleted'), {
        icon: 'trash', tone: 'warn',
        action: { label: t('undo'), run: () => { const { key, ...value } = note; chrome.storage.local.set({ [key]: value }); } }
      });
    };
    return h('div', { class: 'note' },
      h('div', { class: 'head' },
        h('span', { class: 'scope', text: note.scope === 'site' ? t('optSiteWide') : t('optSitePage') }),
        h('span', { class: 'title grow ellipsis', text: note.title || note.host }),
        h('span', { class: 'when', text: Page.when(note.updated) }),
        h('div', { class: 'controls' },
          h('button', { class: 'btn small icon-only', type: 'button', title: t('open'), onclick: () => chrome.tabs.create({ url: note.url }) }, icon('external', 14)),
          h('button', { class: 'btn small icon-only', type: 'button', title: t('copy'), onclick: async () => { await SV.copy(note.text); Page.toast(t('copied'), { icon: 'copy' }); } }, icon('copy', 14)),
          h('button', { class: 'btn small icon-only danger', type: 'button', title: t('delete'), onclick: remove }, icon('trash', 14)))),
      h('div', { class: 'url ellipsis' }, h('a', { href: note.url, target: '_blank', rel: 'noopener', text: note.url })),
      h('div', { class: 'text', text: note.text }));
  }

  function notesSection() {
    const listBox = h('div', { class: 'card list' });
    const fill = () => {
      SV.clear(listBox);
      const q = query.trim().toLowerCase();
      const shown = notes.filter((n) => !q || `${n.title} ${n.url} ${n.text}`.toLowerCase().includes(q));
      if (!shown.length) listBox.append(h('div', { class: 'empty', text: notes.length ? '—' : t('optNotesEmpty') }));
      else shown.forEach((note) => listBox.append(noteItem(note)));
    };
    const search = h('input', { class: 'field', type: 'search', placeholder: t('optSearch'), value: query, 'aria-label': t('optSearch') });
    search.addEventListener('input', () => { query = search.value; fill(); });
    const exportJson = () => download('SAVISUL notes.json', JSON.stringify(notes.map(({ key, ...n }) => n), null, 2), 'application/json');
    const exportMd = () => download('SAVISUL notes.md', ['# SAVISUL', '', ...notes.flatMap((n) => [
      `## [${(n.title || n.host).replace(/([[\]])/g, '\\$1')}](${n.url})`,
      `_${n.scope === 'site' ? t('optSiteWide') : t('optSitePage')} · ${new Date(n.updated).toLocaleString(I.locale)}_`, '', n.text, ''
    ])].join('\n'), 'text/markdown');
    const clearAll = async () => {
      if (!confirm(t('optConfirmDelete'))) return;
      await chrome.storage.local.remove(notes.map((n) => n.key));
    };
    fill();
    return h('section', { id: 'notes', class: 'narrow' },
      h('h2', { class: 'label-head' }, t('optNotes'), h('span', { class: 'count', text: notes.length ? String(notes.length) : '' })),
      notes.length ? h('div', { class: 'notes-tools' }, search,
        h('button', { class: 'btn', type: 'button', onclick: exportMd }, icon('download', 15), 'Markdown'),
        h('button', { class: 'btn', type: 'button', onclick: exportJson }, 'JSON'),
        h('button', { class: 'btn danger', type: 'button', onclick: clearAll }, icon('trash', 15), t('optClearAll'))) : null,
      listBox);
  }

  function hidden() {
    const rules = Object.entries(settings.zapRules || {}).filter(([, list]) => list?.length);
    const list = h('div', { class: 'card list' });
    if (!rules.length) list.append(h('div', { class: 'empty', text: t('optHiddenEmpty') }));
    for (const [host, selectors] of rules) {
      list.append(h('div', { class: 'item', style: { 'align-items': 'flex-start' } },
        h('div', { class: 'grow' },
          h('div', { class: 'label' }, host, h('span', { class: 'faint', style: { 'font-weight': '500', 'margin-left': '8px' }, text: I.plural('optRules', selectors.length) })),
          h('div', { style: { 'margin-top': '6px' } }, selectors.slice(0, 12).map((selector) => h('div', { class: 'rule', text: selector })),
            selectors.length > 12 ? h('div', { class: 'rule', text: '…' }) : null)),
        h('button', {
          class: 'btn small danger', type: 'button', onclick: () => {
            const next = { ...settings.zapRules };
            delete next[host];
            SV_STORE.save({ zapRules: next });
          }
        }, icon('restore', 14), t('zapRestore'))));
    }
    return h('section', { id: 'hidden', class: 'narrow' }, h('h2', { class: 'label-head', text: t('optHidden') }), list);
  }

  function dark() {
    const sites = Object.entries(settings.darkSites || {})
      .filter(([host]) => !/^[a-p]{32}$/.test(host))
      .sort(([a], [b]) => a.localeCompare(b));
    const list = h('div', { class: 'card list' },
      item(t('optDarkAll'), Page.toggle(settings.darkAll, t('optDarkAll'), (darkAll) => SV_STORE.save({ darkAll })), t('optDarkAllDetail')));
    if (!sites.length) list.append(h('div', { class: 'empty', text: t('optDarkEmpty') }));
    for (const [host, value] of sites) {
      const label = value === true ? t('darkStateOn') : value === 'native' ? t('darkNative', host) : t('darkStateOff');
      list.append(h('div', { class: 'item' },
        icon(value === true ? 'moon' : 'sun', 18),
        h('div', { class: 'grow' }, h('div', { class: 'label', text: host }), h('div', { class: 'detail', text: label })),
        h('button', {
          class: 'btn small icon-only', type: 'button', title: t('delete'), onclick: () => {
            const next = { ...settings.darkSites };
            delete next[host];
            SV_STORE.save({ darkSites: next });
          }
        }, icon('x', 14))));
    }
    return h('section', { id: 'dark', class: 'narrow' }, h('h2', { class: 'label-head', text: t('optDark') }), list);
  }

  function footer() {
    return h('footer', null, SV.mark(26), h('div', { text: `SAVISUL · ${t('optVersion', version)}` }));
  }

  // MARK: Render

  const sections = { demo, features, mac, settings: general, notes: notesSection, hidden, dark, shortcuts };

  function render() {
    document.title = `SAVISUL · ${t('optTitle')}`;
    const live = document.getElementById('demo');
    if (!live) {
      SV.clear(app).append(header(), hero(), ...Object.values(sections).map((make) => make()), footer());
      return;
    }
    app.querySelector('header.top').replaceWith(header());
    document.getElementById('top').replaceWith(hero());
    live.querySelector('.demo-side').replaceWith(demoSide());
    Demo.frame.title = t('demoTitle');
    Demo.loading.lastChild.textContent = t('demoLoading');
    for (const id of Object.keys(sections)) if (id !== 'demo') refresh(id);
    app.querySelector('footer').replaceWith(footer());
  }

  function refresh(id) {
    const old = document.getElementById(id);
    if (!old) return;
    const focused = document.activeElement;
    const typing = focused?.tagName === 'INPUT' && old.contains(focused);
    const next = sections[id]();
    old.replaceWith(next);
    if (typing) {
      const input = next.querySelector('input[type="search"]');
      input?.focus();
      input?.setSelectionRange(input.value.length, input.value.length);
    }
  }

  const loadNotes = async () => { notes = await SV_STORE.allNotes(); };
  // Chrome names commands in its own UI language; the page uses the extension's, so the names come from _locales.
  const commandNames = async () => {
    try {
      const manifest = await (await fetch(chrome.runtime.getURL('manifest.json'))).json();
      const messages = await (await fetch(chrome.runtime.getURL(`_locales/${I.lang}/messages.json`))).json();
      return Object.fromEntries(Object.entries(manifest.commands || {})
        .map(([name, command]) => [name, messages[/__MSG_(\w+)__/.exec(command.description || '')?.[1]]?.message])
        .filter(([, text]) => text));
    } catch {
      return {};
    }
  };
  const loadCommands = async () => {
    try {
      const [list, names] = await Promise.all([chrome.commands.getAll(), commandNames()]);
      commands = list.map(({ name, description, shortcut }) => ({ name, description: names[name] || description, shortcut }));
    } catch {
      commands = [];
    }
  };

  await Promise.all([loadNotes(), loadCommands()]);
  render();
  if (location.hash && location.hash !== '#welcome') document.querySelector(location.hash)?.scrollIntoView();

  SV_STORE.onChange(async (changes) => {
    const keys = Object.keys(changes);
    const fresh = await SV_STORE.load();
    const before = settings;
    settings = fresh;
    Page.settings = fresh;
    if (keys.includes('language') || keys.includes('appLanguage')) {
      Page.appLanguage = (await chrome.storage.local.get('appLanguage')).appLanguage || null;
      const next = I.resolve(fresh.language, Page.appLanguage);
      const changed = next !== I.lang;
      I.lang = next;
      document.documentElement.lang = I.lang;
      // The demo frame's own notch follows the same storage change.
      if (changed) {
        await loadCommands();
        render();
      }
      else { refresh('settings'); refresh('mac'); }
      return;
    }
    if (keys.includes('theme')) Page.applyTheme();
    if (keys.some((key) => key.startsWith('note:') || key.startsWith('note@'))) {
      await loadNotes();
      refresh('notes');
    }
    if (keys.includes('zapRules')) refresh('hidden');
    if (keys.includes('darkAll') || keys.includes('darkSites')) refresh('dark');
    if (keys.includes('hiddenSites') || (keys.includes('hover') && before.hover !== fresh.hover)) refresh('settings');
  });

  addEventListener('focus', async () => {
    await loadCommands();
    refresh('shortcuts');
    refresh('features');
  });
})();
