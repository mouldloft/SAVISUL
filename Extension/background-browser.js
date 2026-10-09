// Browser platform pieces of the service worker: side panel, context menus, tab suspension,
// web archives, Shelf hand-off and blob downloads. Loaded by background.js after its own setup,
// so it can use `handlers`, `Bridge`, `deliver`, `injectable` and `inject` from there.

const I18N = globalThis.SV_I18N;
const OFFSCREEN = 'pages/offscreen.html';

async function languageReady() {
  const settings = await SV_STORE.load();
  const { appLanguage } = await chrome.storage.local.get('appLanguage');
  I18N.lang = I18N.resolve(settings.language, appLanguage);
  return settings;
}

function toBase64(bytes) {
  let binary = '';
  for (let i = 0; i < bytes.length; i += 0x8000) binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(binary);
}

// MARK: Side panel

async function openSidebar(windowId, view, prompt) {
  // open() must run while the click or shortcut still counts as a user gesture, so it goes first.
  const opening = chrome.sidePanel.open({ windowId });
  const patch = { sidebarStamp: Date.now() };
  if (view) patch.sidebarView = view;
  if (prompt) patch.sidebarPrompt = prompt;
  await chrome.storage.session.set(patch);
  await opening;
}

chrome.commands.onCommand.addListener(async (command, tab) => {
  if (command !== 'sidebar') return;
  tab ||= (await chrome.tabs.query({ active: true, lastFocusedWindow: true }))[0];
  if (tab) openSidebar(tab.windowId).catch(() => {});
});

// MARK: Blob downloads through an offscreen document
// Data URLs past ~2 MB never reach the download manager, and a service worker has no
// URL.createObjectURL, so large files are parked in IndexedDB and turned into a blob URL offscreen.

let offscreenReady = null;
async function ensureOffscreen() {
  if (await chrome.offscreen.hasDocument?.()) return;
  offscreenReady ||= chrome.offscreen.createDocument({
    url: OFFSCREEN,
    reasons: ['BLOBS'],
    justification: 'Turn saved pages and exports into downloadable files'
  }).finally(() => { offscreenReady = null; });
  await offscreenReady;
}

async function downloadBlob(blob, filename) {
  const key = crypto.randomUUID();
  await SV_DB.put('frames', `blob:${key}`, blob);
  await ensureOffscreen();
  const reply = await chrome.runtime.sendMessage({ target: 'offscreen', type: 'blob:url', key });
  if (!reply?.url) throw new Error('blob');
  try {
    return await chrome.downloads.download({ url: reply.url, filename, conflictAction: 'uniquify', saveAs: false });
  } finally {
    setTimeout(() => {
      chrome.runtime.sendMessage({ target: 'offscreen', type: 'blob:revoke', url: reply.url, key }).catch(() => {});
    }, 60000);
  }
}

// MARK: Shelf (SAVISUL for Mac)

const Shelf = {
  CHUNK: 384 * 1024,

  async ready() {
    if (Bridge.status === 'missing' && !Bridge.port) Bridge.status = 'idle';
    let reply;
    try {
      reply = await Bridge.request({ type: 'state' }, 4000);
    } catch (error) {
      throw new Error(Bridge.status === 'missing' ? 'missing' : 'offline');
    }
    if (reply?.state?.app?.running) return;
    try {
      const launched = await Bridge.request({ type: 'launch' }, 16000);
      if (launched?.state?.app?.running) return;
    } catch {}
    throw new Error('offline');
  },

  check(reply) {
    if (reply?.error === 'unknown') throw new Error('update');
    if (reply?.error) throw new Error(reply.error === 'offline' ? 'offline' : 'failed');
    return reply;
  },

  async text(text, title = '') {
    await this.ready();
    return this.check(await Bridge.request({ type: 'shelfAdd', text, title }, 8000));
  },

  async file(name, base64) {
    await this.ready();
    const token = crypto.randomUUID();
    const total = Math.max(1, Math.ceil(base64.length / this.CHUNK));
    let reply = null;
    for (let index = 0; index < total; index++) {
      const data = base64.slice(index * this.CHUNK, (index + 1) * this.CHUNK);
      reply = this.check(await Bridge.request({ type: 'shelfChunk', token, index, total, name, data }, 20000));
    }
    return reply;
  },

  async url(href) {
    const response = await fetch(href, { credentials: 'include' });
    if (!response.ok) throw new Error('failed');
    const bytes = new Uint8Array(await response.arrayBuffer());
    let name = '';
    try { name = decodeURIComponent(new URL(href).pathname.split('/').pop() || ''); } catch {}
    const type = response.headers.get('content-type') || '';
    if (!/\.[a-z0-9]{2,5}$/i.test(name)) name = `${name || 'image'}.${(type.split('/')[1] || 'png').split(';')[0].replace('jpeg', 'jpg').replace('svg+xml', 'svg')}`;
    return this.file(name.slice(0, 120), toBase64(bytes));
  }
};

// MARK: Handlers

Object.assign(handlers, {
  async 'sidebar:open'(message, sender) {
    await openSidebar(sender.tab?.windowId ?? (await chrome.windows.getLastFocused()).id, message.view, message.prompt);
    return { ok: true };
  },

  async 'archive:save'(message, sender) {
    const blob = await chrome.pageCapture.saveAsMHTML({ tabId: sender.tab.id });
    const name = SV_STORE.hostOf(sender.tab.url) ? `${message.name || 'page'}.mhtml` : 'page.mhtml';
    if (message.target === 'shelf') {
      await Shelf.file(name, toBase64(new Uint8Array(await blob.arrayBuffer())));
    } else {
      // pageCapture hands back an untyped blob; without the MHTML type Chrome renames it to .txt.
      await downloadBlob(new Blob([blob], { type: 'application/x-mimearchive' }), `SAVISUL/${name}`);
    }
    return { ok: true, bytes: blob.size };
  },

  async 'shelf:add'(message) {
    if (message.kind === 'link') await Shelf.text(message.url, message.title || '');
    else if (message.kind === 'text') await Shelf.text(message.text);
    else if (message.kind === 'file') await Shelf.file(message.name, message.data);
    else if (message.kind === 'url') await Shelf.url(message.url);
    return { ok: true };
  },

  async 'blob:download'(message) {
    const bytes = Uint8Array.from(atob(message.data), (c) => c.charCodeAt(0));
    await downloadBlob(new Blob([bytes], { type: message.mime || 'application/octet-stream' }), message.filename);
    return { ok: true };
  },

  async 'print:open'(message, sender) {
    const id = crypto.randomUUID();
    await chrome.storage.session.set({ [`print:${id}`]: message.doc });
    await chrome.tabs.create({
      url: chrome.runtime.getURL(`pages/print.html#${id}`),
      ...(sender.tab ? { index: sender.tab.index + 1, openerTabId: sender.tab.id } : {})
    });
    return { ok: true };
  }
});

// MARK: Context menus

async function buildMenus() {
  await languageReady();
  const t = (key) => I18N.t(key);
  await chrome.contextMenus.removeAll();
  const add = (props) => chrome.contextMenus.create(props, () => void chrome.runtime.lastError);
  add({ id: 'sv-sidebar', title: t('sbOpen'), contexts: ['action', 'page'] });
  add({ id: 'sv-ai-selection', title: t('menuAskAi'), contexts: ['selection'] });
  add({ id: 'sv-clean-link', title: t('menuCleanLink'), contexts: ['link'] });
  add({ id: 'sv-shelf', title: t('menuShelf'), contexts: ['page', 'link', 'image', 'selection'] });
  add({ id: 'sv-shelf-page', parentId: 'sv-shelf', title: t('menuShelfPage'), contexts: ['page'] });
  add({ id: 'sv-shelf-link', parentId: 'sv-shelf', title: t('menuShelfLink'), contexts: ['link'] });
  add({ id: 'sv-shelf-image', parentId: 'sv-shelf', title: t('menuShelfImage'), contexts: ['image'] });
  add({ id: 'sv-shelf-selection', parentId: 'sv-shelf', title: t('menuShelfSelection'), contexts: ['selection'] });
}

async function menuToast(tab, key, tone = 'ok', icon = 'tray') {
  if (!tab?.id) return;
  await deliver(tab, { type: 'toast', key, tone, icon });
}

chrome.contextMenus.onClicked.addListener(async (info, tab) => {
  try {
    switch (info.menuItemId) {
      case 'sv-sidebar':
        await openSidebar(tab.windowId);
        break;
      case 'sv-ai-selection':
        await openSidebar(tab.windowId, 'ai', info.selectionText || '');
        break;
      case 'sv-clean-link': {
        const { url } = SV_STORE.cleanUrl(info.linkUrl);
        await deliver(tab, { type: 'copy', text: url, key: 'menuCopied' });
        break;
      }
      case 'sv-shelf-page':
        await Shelf.text(SV_STORE.cleanUrl(info.pageUrl).url, tab?.title || '');
        await menuToast(tab, 'shelfAdded');
        break;
      case 'sv-shelf-link':
        await Shelf.text(SV_STORE.cleanUrl(info.linkUrl).url);
        await menuToast(tab, 'shelfAdded');
        break;
      case 'sv-shelf-image':
        await Shelf.url(info.srcUrl);
        await menuToast(tab, 'shelfAdded');
        break;
      case 'sv-shelf-selection':
        await Shelf.text(info.selectionText || '');
        await menuToast(tab, 'shelfAdded');
        break;
    }
  } catch (error) {
    const reason = String(error?.message || error);
    const key = { update: 'shelfUpdate', missing: 'shelfMissing', offline: 'shelfOffline' }[reason] || 'shelfFailed';
    await menuToast(tab, key, 'warn');
  }
});

// MARK: Tab suspension

const SUSPEND_ALARM = 'savisul-suspend';

async function suspendIdle() {
  const settings = await SV_STORE.load();
  const minutes = Number(settings.suspendAfter) || 0;
  if (minutes <= 0) return;
  const except = new Set(settings.suspendExcept || []);
  const now = Date.now();
  const tabs = await chrome.tabs.query({ active: false, discarded: false, pinned: false, audible: false });
  for (const tab of tabs) {
    if (!/^https?:/.test(tab.url || '') || tab.status === 'loading') continue;
    if (except.has(SV_STORE.hostOf(tab.url))) continue;
    if (!tab.lastAccessed || now - tab.lastAccessed < minutes * 60000) continue;
    chrome.tabs.discard(tab.id).catch(() => {});
  }
}

function scheduleSuspend() {
  chrome.alarms.get(SUSPEND_ALARM).then((alarm) => {
    if (!alarm) chrome.alarms.create(SUSPEND_ALARM, { periodInMinutes: 1 });
  }).catch(() => {});
}

chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === SUSPEND_ALARM) suspendIdle().catch(() => {});
});

// MARK: Sync with SAVISUL for Mac
// The extension follows the Mac app: its language is read from every bridge state and stored as
// appLanguage, which every page resolves against (an explicit language choice still wins).

const SYNC_ALARM = 'savisul-app-sync';

function syncAppLanguage(state) {
  const language = state?.app?.language;
  if (!I18N.LANGS.includes(language)) return;
  chrome.storage.local.get('appLanguage').then(({ appLanguage }) => {
    if (appLanguage !== language) chrome.storage.local.set({ appLanguage: language });
  }).catch(() => {});
}

async function pullAppState() {
  if (Bridge.status === 'missing' && !Bridge.port) Bridge.status = 'idle';
  try { await Bridge.request({ type: 'state' }, 4000); } catch {}
  setTimeout(() => Bridge.close(), 20000);
}

// Older versions defaulted to an explicit language; from 1.4 the default is "like on Mac".
async function adoptMacLanguage() {
  const { languageFollowsMac } = await chrome.storage.local.get('languageFollowsMac');
  if (languageFollowsMac) return;
  await chrome.storage.local.set({ language: 'auto', languageFollowsMac: true });
}

chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === SYNC_ALARM) pullAppState().catch(() => {});
});

function scheduleSync() {
  chrome.alarms.get(SYNC_ALARM).then((alarm) => {
    if (!alarm) chrome.alarms.create(SYNC_ALARM, { periodInMinutes: 10 });
  }).catch(() => {});
}

// MARK: Setup

chrome.runtime.onInstalled.addListener(async () => {
  await adoptMacLanguage().catch(() => {});
  buildMenus().catch(() => {});
  scheduleSuspend();
  scheduleSync();
  pullAppState().catch(() => {});
});
chrome.runtime.onStartup.addListener(() => {
  buildMenus().catch(() => {});
  scheduleSuspend();
  scheduleSync();
  pullAppState().catch(() => {});
});
chrome.storage.onChanged.addListener((changes, area) => {
  if (area === 'local' && (changes.language || changes.appLanguage)) buildMenus().catch(() => {});
});
