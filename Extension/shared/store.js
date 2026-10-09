(() => {
  const DEFAULTS = {
    language: 'auto',
    position: 'center',
    idle: 'notch',
    theme: 'dark',
    hover: true,
    hiddenSites: [],
    colorFormat: 'hex',
    colorAutoCopy: true,
    colors: [],
    darkAll: false,
    darkSites: {},
    reader: { font: 'serif', size: 20, width: 700, theme: 'auto' },
    zapRules: {},
    videoSpeed: {},
    imagesHideSmall: true,
    suspendAfter: 0,
    suspendExcept: [],
    aiModel: 'claude-opus-5-5',
    translateTo: 'auto'
  };
  const KEYS = Object.keys(DEFAULTS);

  const clone = (value) => (typeof structuredClone === 'function' ? structuredClone(value) : JSON.parse(JSON.stringify(value)));

  async function load() {
    const stored = await chrome.storage.local.get(KEYS);
    const settings = clone(DEFAULTS);
    for (const key of KEYS) if (stored[key] !== undefined) settings[key] = stored[key];
    settings.reader = { ...DEFAULTS.reader, ...(stored.reader || {}) };
    return settings;
  }

  function save(patch) {
    return chrome.storage.local.set(patch);
  }

  function onChange(callback) {
    const listener = (changes, area) => {
      if (area === 'local') callback(changes);
    };
    chrome.storage.onChanged.addListener(listener);
    return () => chrome.storage.onChanged.removeListener(listener);
  }

  const { cleanUrl, normalizeUrl, hostOf } = globalThis.SV_URL;

  const pageKey = (href) => 'note:' + normalizeUrl(href);
  const siteKey = (href) => 'note@' + hostOf(href);

  async function getNotes(href) {
    const keys = [pageKey(href), siteKey(href)];
    const stored = await chrome.storage.local.get(keys);
    return { page: stored[keys[0]] || null, site: stored[keys[1]] || null };
  }

  async function saveNote(scope, href, text, title) {
    const key = scope === 'site' ? siteKey(href) : pageKey(href);
    if (!text.trim()) {
      await chrome.storage.local.remove(key);
      return null;
    }
    const existing = (await chrome.storage.local.get(key))[key];
    const note = {
      scope,
      text,
      url: scope === 'site' ? `${new URL(href).origin}/` : normalizeUrl(href),
      host: hostOf(href),
      title: scope === 'site' ? hostOf(href) : (title || hostOf(href)),
      created: existing?.created || Date.now(),
      updated: Date.now()
    };
    await chrome.storage.local.set({ [key]: note });
    return note;
  }

  async function allNotes() {
    const everything = await chrome.storage.local.get(null);
    return Object.entries(everything)
      .filter(([key, value]) => (key.startsWith('note:') || key.startsWith('note@')) && !String(value?.url || '').startsWith('chrome-extension:'))
      .map(([key, value]) => ({ key, ...value }))
      .sort((a, b) => b.updated - a.updated);
  }

  globalThis.SV_STORE = { DEFAULTS, KEYS, load, save, onChange, cleanUrl, normalizeUrl, hostOf, getNotes, saveNote, allNotes, pageKey, siteKey };
})();
