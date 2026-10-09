(() => {
  if ((window.top !== window && !globalThis.__savisulDemo) || !globalThis.SV) return;
  const SV = globalThis.SV;

  const I = SV_I18N;
  const N = SV.notch;
  const VISUAL = ['language', 'position', 'idle', 'theme', 'hover', 'hiddenSites'];
  let appLanguage = null;

  function run(command) {
    switch (command) {
      case 'toggle-notch': N.toggle(); break;
      case 'reader': SV.runTool('reader'); break;
      case 'full-screenshot': SV.tools.shot.full(); break;
      case 'dark': SV.tools.dark.toggle(); break;
      case 'color': N.openPanel('color', { direct: true }); break;
      case 'notes': N.openPanel('notes', { direct: true }); break;
      case 'ruler': SV.runTool('ruler'); break;
      case 'zapper': SV.runTool('zapper'); break;
      case 'inspect': SV.runTool('inspect'); break;
      case 'translate': N.openPanel('translate', { direct: true }); break;
      case 'export': N.openPanel('export', { direct: true }); break;
    }
  }

  function onMessage(message, _sender, respond) {
    if (!SV.alive || !message?.type) return;
    if (message.type === 'ping') {
      respond({ ok: true });
    } else if (message.type === 'command') {
      run(message.command);
      respond({ ok: true });
    } else if (message.type === 'toast') {
      SV.toast(I.t(message.key), { icon: message.icon || 'check', tone: message.tone || 'ok', duration: message.tone === 'warn' ? 4200 : 2300 });
      respond({ ok: true });
    } else if (message.type === 'copy') {
      SV.copy(message.text).then((ok) => {
        SV.toast(I.t(ok ? message.key || 'copied' : 'shotFailed'), { icon: ok ? 'copy' : 'x', tone: ok ? 'ok' : 'warn' });
        respond({ ok });
      });
      return true;
    } else if (message.type === 'digest') {
      respond(SV.digest?.(message.options) || null);
    } else if (message.type === 'dark:apply') {
      SV.tools.dark.apply(message.on);
      if (N.view === 'home') N.openHome();
      respond({ ok: true });
    }
  }

  function onStorage(changes) {
    if (!SV.alive || !SV.settings) return;
    let language = false;
    for (const key of SV_STORE.KEYS) {
      if (!(key in changes)) continue;
      const value = changes[key].newValue;
      SV.settings[key] = value === undefined ? structuredClone(SV_STORE.DEFAULTS[key]) : value;
    }
    if ('reader' in changes) SV.settings.reader = { ...SV_STORE.DEFAULTS.reader, ...(changes.reader.newValue || {}) };
    if ('appLanguage' in changes) {
      appLanguage = changes.appLanguage.newValue || null;
      language = true;
    }
    if (language || 'language' in changes) I.lang = I.resolve(SV.settings.language, appLanguage);
    if (language || VISUAL.some((key) => key in changes)) N.applySettings();
  }

  async function boot() {
    let settings;
    try {
      settings = await SV_STORE.load();
      appLanguage = (await chrome.storage.local.get('appLanguage')).appLanguage || null;
    } catch {
      return;
    }
    if (!SV.alive) return;
    SV.settings = settings;
    // Older copies sat on the right edge, where a closed notch is easy to miss.
    if (!(await chrome.storage.local.get('notchCentered')).notchCentered) {
      settings.position = 'center';
      chrome.storage.local.set({ position: 'center', notchCentered: true }).catch(() => {});
    }
    I.lang = I.resolve(settings.language, appLanguage);
    N.mount();
    N.applySettings();
    for (const [id, tool] of Object.entries(SV.tools)) {
      try { tool.init?.(settings); } catch (error) { console.error('SAVISUL', id, error); }
    }

    chrome.runtime.onMessage.addListener(onMessage);
    SV.cleanups.push(() => chrome.runtime.onMessage.removeListener(onMessage));
    SV.cleanups.push(SV_STORE.onChange(onStorage));

    const scheme = matchMedia('(prefers-color-scheme: light)');
    const onScheme = () => { if (SV.settings.theme === 'auto') N.applySettings(); };
    scheme.addEventListener('change', onScheme);
    SV.cleanups.push(() => scheme.removeEventListener('change', onScheme));
  }

  boot();
})();
