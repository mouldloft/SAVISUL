importScripts('shared/i18n.js', 'shared/i18n-browser.js', 'shared/urlclean.js', 'shared/store.js', 'shared/idb.js');

const HOST = 'com.savisul.bridge';
const DARK_ID = 'savisul-dark';
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

const contentFiles = () => chrome.runtime.getManifest().content_scripts.flatMap((entry) => entry.js);

function injectable(url = '') {
  if (!/^(https?|file):/.test(url)) return false;
  return !/^https:\/\/(chromewebstore\.google\.com|chrome\.google\.com\/webstore|microsoftedge\.microsoft\.com\/addons)/.test(url);
}

async function inject(tabId) {
  await chrome.scripting.executeScript({ target: { tabId }, files: contentFiles() });
}

async function deliver(tab, message) {
  if (!tab?.id) return undefined;
  try {
    return await chrome.tabs.sendMessage(tab.id, message);
  } catch {
    if (!injectable(tab.url)) {
      flashBadge(tab.id, '–');
      return undefined;
    }
    try {
      await inject(tab.id);
      await sleep(80);
      return await chrome.tabs.sendMessage(tab.id, message);
    } catch {
      flashBadge(tab.id, '!');
      return undefined;
    }
  }
}

function flashBadge(tabId, text) {
  chrome.action.setBadgeBackgroundColor({ tabId, color: '#dbc7a3' }).catch(() => {});
  chrome.action.setBadgeText({ tabId, text }).catch(() => {});
  setTimeout(() => chrome.action.setBadgeText({ tabId, text: '' }).catch(() => {}), 1800);
}

// MARK: Install and startup

chrome.runtime.onInstalled.addListener(async (details) => {
  await syncDark();
  SV_DB.sweep().catch(() => {});
  if (details.reason === 'install') {
    chrome.tabs.create({ url: chrome.runtime.getURL('pages/options.html#welcome') });
  }
  const tabs = await chrome.tabs.query({});
  for (const tab of tabs) {
    if (injectable(tab.url) && !tab.discarded) inject(tab.id).catch(() => {});
  }
});

chrome.runtime.onStartup.addListener(async () => {
  syncDark();
  SV_DB.sweep().catch(() => {});
  const tabs = await chrome.tabs.query({});
  for (const tab of tabs) {
    if (injectable(tab.url) && !tab.discarded) inject(tab.id).catch(() => {});
  }
});

chrome.action.onClicked.addListener(async (tab) => {
  if (!injectable(tab.url)) {
    chrome.runtime.openOptionsPage();
    return;
  }
  deliver(tab, { type: 'command', command: 'toggle-notch' });
});

chrome.commands.onCommand.addListener(async (command, tab) => {
  if (command === 'sidebar') return;
  tab ||= (await chrome.tabs.query({ active: true, lastFocusedWindow: true }))[0];
  deliver(tab, { type: 'command', command });
});

// MARK: Dark theme

let darkSync = Promise.resolve();

// One invalid pattern makes Chrome reject the whole registration, so file pages (no host),
// IP addresses and odd hosts never get a www. twin or an entry they can't have.
function patterns(host) {
  if (!host || !/^([a-z0-9-]+\.)*[a-z0-9-]+$|^\[[0-9a-f:.]+\]$/i.test(host)) return [];
  const literal = host.startsWith('[') || /^\d{1,3}(\.\d{1,3}){3}$/.test(host);
  return literal || !host.includes('.') ? [`*://${host}/*`] : [`*://${host}/*`, `*://www.${host}/*`];
}

function syncDark() {
  darkSync = darkSync.then(async () => {
    const settings = await SV_STORE.load();
    const entries = Object.entries(settings.darkSites || {});
    let matches;
    let excludeMatches = [];
    if (settings.darkAll) {
      matches = ['<all_urls>'];
      excludeMatches = entries.filter(([, value]) => value !== true).flatMap(([host]) => patterns(host));
    } else {
      matches = entries.filter(([, value]) => value === true).flatMap(([host]) => patterns(host));
    }
    await chrome.scripting.unregisterContentScripts({ ids: [DARK_ID] }).catch(() => {});
    if (!matches.length) return;
    await chrome.scripting.registerContentScripts([{
      id: DARK_ID,
      matches,
      excludeMatches,
      css: ['content/dark.css'],
      runAt: 'document_start',
      persistAcrossSessions: true
    }]).catch((error) => console.warn('SAVISUL dark registration', error));
  }).catch(() => {});
  return darkSync;
}

// Quick repeated toggles must apply in order, or an older "on" can land after a newer "off".
let darkChanges = Promise.resolve();

function setDark(host, mode, sourceTab) {
  const change = darkChanges.then(async () => {
    const settings = await SV_STORE.load();
    const sites = { ...settings.darkSites };
    if (mode === 'native') sites[host] = 'native';
    else if (settings.darkAll) {
      if (mode) delete sites[host];
      else sites[host] = false;
    } else if (mode) sites[host] = true;
    else delete sites[host];
    await SV_STORE.save({ darkSites: sites });
    await syncDark();
    if (mode === 'native') return;
    const tabs = await chrome.tabs.query({});
    for (const tab of tabs) {
      if (tab.id === sourceTab || SV_STORE.hostOf(tab.url || '') !== host) continue;
      chrome.tabs.sendMessage(tab.id, { type: 'dark:apply', on: !!mode }).catch(() => {});
    }
  });
  darkChanges = change.catch(() => {});
  return change;
}

chrome.storage.onChanged.addListener((changes, area) => {
  if (area === 'local' && (changes.darkAll || changes.darkSites)) syncDark();
});

// MARK: Capture

const Capture = {
  last: 0,
  async grab(windowId) {
    for (let attempt = 0; attempt < 3; attempt++) {
      const wait = this.last + 560 - Date.now();
      if (wait > 0) await sleep(wait);
      this.last = Date.now();
      try {
        return await chrome.tabs.captureVisibleTab(windowId, { format: 'png' });
      } catch (error) {
        if (!/MAX_CAPTURE|per second/i.test(String(error?.message))) throw error;
        await sleep(700);
      }
    }
    throw new Error('capture-rate');
  },
  async frame(tab, id, index) {
    const current = await chrome.tabs.get(tab.id);
    if (!current.active) throw new Error('tab-changed');
    const url = await this.grab(tab.windowId);
    const blob = await (await fetch(url)).blob();
    await SV_DB.put('frames', `${id}:${index}`, blob);
  },
  async open(tab, id) {
    await chrome.tabs.create({
      url: chrome.runtime.getURL(`pages/capture.html#${id}`),
      index: tab.index + 1,
      openerTabId: tab.id
    });
  }
};

// MARK: Bridge to SAVISUL for Mac

const Bridge = {
  port: null,
  status: 'idle',
  state: null,
  error: '',
  seq: 0,
  pending: new Map(),
  subscribers: new Set(),
  poll: null,
  idleTimer: null,

  connect() {
    if (this.port) return;
    let port;
    try {
      port = chrome.runtime.connectNative(HOST);
    } catch (error) {
      this.fail('missing', String(error?.message || error));
      return;
    }
    this.port = port;
    this.status = 'connecting';
    port.onMessage.addListener((message) => this.receive(message));
    port.onDisconnect.addListener(() => {
      const error = chrome.runtime.lastError?.message || '';
      if (this.port !== port) return;
      this.port = null;
      for (const entry of this.pending.values()) {
        clearTimeout(entry.timer);
        entry.reject(new Error(error || 'disconnected'));
      }
      this.pending.clear();
      this.fail(/not found|forbidden|not allowed/i.test(error) ? 'missing' : 'offline', error);
    });
    this.request({ type: 'hello', version: chrome.runtime.getManifest().version }).catch(() => {});
  },

  fail(status, error) {
    this.status = status;
    this.error = error;
    this.state = null;
    this.broadcast();
  },

  receive(message) {
    if (message.id != null && this.pending.has(message.id)) {
      const entry = this.pending.get(message.id);
      this.pending.delete(message.id);
      clearTimeout(entry.timer);
      entry.resolve(message);
    }
    if (message.state) {
      this.state = message.state;
      syncAppLanguage(message.state);
      this.status = message.state.app?.running ? 'ready' : 'offline';
      this.error = '';
      this.broadcast();
    }
  },

  request(body, timeout = 6000) {
    this.connect();
    if (!this.port) return Promise.reject(new Error(this.status));
    const id = ++this.seq;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error('timeout'));
      }, timeout);
      this.pending.set(id, { resolve, reject, timer });
      try {
        this.port.postMessage({ ...body, id });
      } catch (error) {
        clearTimeout(timer);
        this.pending.delete(id);
        reject(error);
      }
    });
  },

  snapshot() {
    return { status: this.status, state: this.state, error: this.error };
  },

  broadcast() {
    const message = { type: 'bridge', ...this.snapshot() };
    for (const port of this.subscribers) {
      try { port.postMessage(message); } catch { this.subscribers.delete(port); }
    }
  },

  subscribe(port) {
    this.subscribers.add(port);
    clearTimeout(this.idleTimer);
    if (this.status === 'missing' && !this.port) this.status = 'idle';
    this.connect();
    port.postMessage({ type: 'bridge', ...this.snapshot() });
    if (this.port) this.request({ type: 'state' }).catch(() => {});
    if (!this.poll) {
      this.poll = setInterval(() => {
        if (!this.subscribers.size) return;
        if (this.port) this.request({ type: 'state' }).catch(() => {});
      }, 3000);
    }
    port.onDisconnect.addListener(() => {
      this.subscribers.delete(port);
      if (this.subscribers.size) return;
      clearInterval(this.poll);
      this.poll = null;
      this.idleTimer = setTimeout(() => this.close(), 30000);
    });
  },

  close() {
    if (!this.port || this.subscribers.size || this.pending.size) return;
    const port = this.port;
    this.port = null;
    this.status = 'idle';
    try { port.disconnect(); } catch {}
  }
};

chrome.runtime.onConnect.addListener((port) => {
  if (port.name === 'bridge') Bridge.subscribe(port);
});

// MARK: Messages

const handlers = {
  async 'dark:set'(message, sender) {
    await setDark(message.host, message.mode, sender.tab?.id);
    return { ok: true };
  },
  async 'dark:inject'(message, sender) {
    await chrome.scripting.insertCSS({ target: { tabId: sender.tab.id }, files: ['content/dark.css'] });
    return { ok: true };
  },

  async 'capture:begin'(message) {
    const id = crypto.randomUUID();
    await SV_DB.put('shots', id, { created: Date.now(), frames: [], meta: message.meta || {} });
    return { id };
  },
  async 'capture:frame'(message, sender) {
    await Capture.frame(sender.tab, message.id, message.index);
    return { ok: true };
  },
  async 'capture:finish'(message, sender) {
    const shot = await SV_DB.get('shots', message.id);
    if (!shot) throw new Error('missing');
    shot.frames = message.frames;
    shot.meta = { ...shot.meta, ...message.meta };
    await SV_DB.put('shots', message.id, shot);
    await Capture.open(sender.tab, message.id);
    return { ok: true };
  },
  async 'capture:cancel'(message) {
    if (message.id) await SV_DB.dropShot(message.id);
    return { ok: true };
  },
  async 'capture:visible'(message, sender) {
    const id = crypto.randomUUID();
    await SV_DB.put('shots', id, { created: Date.now(), frames: [], meta: message.meta || {} });
    await Capture.frame(sender.tab, id, 0);
    const shot = await SV_DB.get('shots', id);
    shot.frames = [{ x: 0, y: 0 }];
    await SV_DB.put('shots', id, shot);
    await Capture.open(sender.tab, id);
    return { ok: true };
  },

  async badge(message, sender) {
    const tabId = sender.tab.id;
    await chrome.action.setBadgeBackgroundColor({ tabId, color: '#dbc7a3' });
    if (chrome.action.setBadgeTextColor) await chrome.action.setBadgeTextColor({ tabId, color: '#141416' });
    await chrome.action.setBadgeText({ tabId, text: message.text || '' });
    return { ok: true };
  },

  async download(message) {
    const ids = [];
    for (const item of message.items) {
      try {
        ids.push(await chrome.downloads.download({ url: item.url, filename: item.filename, conflictAction: 'uniquify', saveAs: false }));
      } catch {}
    }
    return { count: ids.length };
  },

  async open(message, sender) {
    const tab = sender.tab;
    if (message.url === 'options') {
      await chrome.runtime.openOptionsPage();
      return { ok: true };
    }
    await chrome.tabs.create({ url: message.url, ...(tab ? { index: tab.index + 1, openerTabId: tab.id } : {}) });
    return { ok: true };
  },

  async commands() {
    const list = await chrome.commands.getAll();
    return { commands: list.map(({ name, shortcut }) => ({ name, shortcut })) };
  },

  async 'bridge:status'() {
    if (!Bridge.port && Bridge.status !== 'missing') Bridge.connect();
    if (Bridge.port && !Bridge.state) {
      try { await Bridge.request({ type: 'state' }, 3000); } catch {}
    }
    return Bridge.snapshot();
  },
  async 'bridge:request'(message) {
    if (!Bridge.port && Bridge.status === 'missing') Bridge.status = 'idle';
    const reply = await Bridge.request(message.body, message.timeout || 8000);
    return { ...reply, bridge: Bridge.snapshot() };
  }
};

chrome.runtime.onMessage.addListener((message, sender, respond) => {
  const handler = handlers[message?.type];
  if (!handler) return false;
  handler(message, sender)
    .then((result) => respond(result ?? { ok: true }))
    .catch((error) => respond({ error: String(error?.message || error) }));
  return true;
});

importScripts('background-browser.js');
