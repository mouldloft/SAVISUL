(() => {
  const { h, icon } = SV;
  const I = SV_I18N;
  const t = (...args) => I.t(...args);
  const S = Sidebar;

  const GROUP_COLORS = { grey: '#9aa0a6', blue: '#8ab4f8', red: '#f28b82', yellow: '#fdd663', green: '#81c995', pink: '#ff8bcb', purple: '#c58af9', cyan: '#78d9ec', orange: '#fcad70' };
  const COLOR_ORDER = Object.keys(GROUP_COLORS);
  const SUSPEND_STEPS = [0, 15, 30, 60, 180, 720];

  const normal = (url) => SV_STORE.normalizeUrl(url || '');
  const hashColor = (text) => COLOR_ORDER[[...text].reduce((a, c) => (a * 31 + c.charCodeAt(0)) >>> 0, 7) % COLOR_ORDER.length];

  // MARK: Tab operations

  async function allTabs() {
    return chrome.tabs.query({});
  }

  function duplicatesOf(tabs) {
    const byUrl = new Map();
    for (const tab of tabs) {
      if (!/^(https?|file):/.test(tab.url || '')) continue;
      const key = normal(tab.url);
      if (!byUrl.has(key)) byUrl.set(key, []);
      byUrl.get(key).push(tab);
    }
    const extra = [];
    for (const group of byUrl.values()) {
      if (group.length < 2) continue;
      // Keep the active tab, else the pinned one, else the most recently used.
      group.sort((a, b) => (b.active - a.active) || (b.pinned - a.pinned) || ((b.lastAccessed || 0) - (a.lastAccessed || 0)));
      extra.push(...group.slice(1));
    }
    return extra;
  }

  async function closeDuplicates() {
    const extra = duplicatesOf(await allTabs());
    if (!extra.length) return;
    await chrome.tabs.remove(extra.map((tab) => tab.id));
    S.toast(t('tabsClosedDupes', I.number(extra.length)), { icon: 'duplicate' });
  }

  async function groupBySite() {
    const tabs = await chrome.tabs.query({ windowId: S.windowId });
    const byHost = new Map();
    for (const tab of tabs) {
      if (tab.pinned || tab.groupId !== chrome.tabGroups.TAB_GROUP_ID_NONE || !/^https?:/.test(tab.url || '')) continue;
      const host = SV_STORE.hostOf(tab.url || '');
      if (!host) continue;
      if (!byHost.has(host)) byHost.set(host, []);
      byHost.get(host).push(tab.id);
    }
    let made = 0;
    for (const [host, ids] of byHost) {
      if (ids.length < 2) continue;
      const groupId = await chrome.tabs.group({ tabIds: ids, createProperties: { windowId: S.windowId } });
      await chrome.tabGroups.update(groupId, { title: host.replace(/\.(com|org|net|ru|io|dev|app)$/, ''), color: hashColor(host) });
      made++;
    }
    S.toast(made ? I.plural('tabsGrouped', made) : t('tabsNothingToGroup'), { icon: 'group', tone: made ? 'ok' : 'warn' });
  }

  async function ungroupAll() {
    const tabs = await chrome.tabs.query({ windowId: S.windowId });
    const grouped = tabs.filter((tab) => tab.groupId !== chrome.tabGroups.TAB_GROUP_ID_NONE).map((tab) => tab.id);
    if (grouped.length) await chrome.tabs.ungroup(grouped);
  }

  async function suspendOthers() {
    const tabs = await chrome.tabs.query({ windowId: S.windowId, active: false, discarded: false, pinned: false, audible: false });
    let count = 0;
    for (const tab of tabs) {
      if (!/^https?:/.test(tab.url || '')) continue;
      try {
        await chrome.tabs.discard(tab.id);
        count++;
      } catch {}
    }
    S.toast(t('tabsSuspended', I.number(count)), { icon: 'snooze' });
  }

  async function sortBySite() {
    const tabs = await chrome.tabs.query({ windowId: S.windowId });
    const loose = tabs.filter((tab) => !tab.pinned && tab.groupId === chrome.tabGroups.TAB_GROUP_ID_NONE);
    const first = tabs.filter((tab) => tab.pinned || tab.groupId !== chrome.tabGroups.TAB_GROUP_ID_NONE).length;
    loose.sort((a, b) => Sidebar.hostOf(a.url).localeCompare(Sidebar.hostOf(b.url)) || (a.title || '').localeCompare(b.title || ''));
    for (const [offset, tab] of loose.entries()) await chrome.tabs.move(tab.id, { index: first + offset });
    S.toast(t('tabsSorted'), { icon: 'sort' });
  }

  // MARK: Tabs view

  let query = '';

  function tabRow(tab, dupes) {
    const badges = [];
    if (tab.pinned) badges.push(h('span', { class: 'tag' }, icon('pin', 10)));
    if (tab.audible) badges.push(h('span', { class: 'tag accent' }, icon('speaker', 10)));
    if (tab.discarded) badges.push(h('span', { class: 'tag', text: t('tabsZz') }));
    if (dupes.has(tab.id)) badges.push(h('span', { class: 'tag warn', text: t('tabsDup') }));
    const actions = h('div', { class: 'actions' },
      tab.discarded
        ? S.iconButton('refresh', t('tabsWake'), () => chrome.tabs.reload(tab.id))
        : (!tab.active ? S.iconButton('snooze', t('tabsSuspend'), () => chrome.tabs.discard(tab.id).catch(() => {})) : null),
      S.iconButton('pin', tab.pinned ? t('tabsUnpin') : t('tabsPin'), () => chrome.tabs.update(tab.id, { pinned: !tab.pinned }), { pressed: tab.pinned }),
      S.iconButton('x', t('close'), () => chrome.tabs.remove(tab.id), { danger: true }));
    return h('div', {
      class: `item${tab.id === S.tab?.id ? ' current' : ''}${tab.discarded ? ' dim' : ''}`, title: tab.url, tabindex: '0',
      onclick: () => S.focusTab(tab),
      onkeydown: (event) => { if (event.key === 'Enter') S.focusTab(tab); },
      onauxclick: (event) => { if (event.button === 1) chrome.tabs.remove(tab.id); }
    },
    h('img', { class: 'fav', src: S.favicon(tab.url), alt: '', loading: 'lazy' }),
    h('div', { class: 'text' },
      h('div', { class: 'title', text: tab.title || tab.url }),
      h('div', { class: 'sub' }, badges, Sidebar.hostOf(tab.url))),
    actions);
  }

  async function renderTabs(container) {
    const [tabs, groups, windows] = await Promise.all([allTabs(), chrome.tabGroups.query({}), chrome.windows.getAll()]);
    const dupes = new Set(duplicatesOf(tabs).map((tab) => tab.id));
    const groupById = new Map(groups.map((g) => [g.id, g]));
    const q = query.trim().toLowerCase();
    const match = (tab) => !q || `${tab.title} ${tab.url}`.toLowerCase().includes(q);
    const out = [];

    const suspended = tabs.filter((tab) => tab.discarded).length;
    out.push(h('div', { class: 'stats' },
      h('span', { text: I.plural('tabsCount', tabs.length) }),
      windows.length > 1 ? h('span', { text: I.plural('tabsWindows', windows.length) }) : null,
      suspended ? h('span', { text: t('tabsSuspendedCount', I.number(suspended)) }) : null,
      groups.length ? h('span', { text: I.plural('tabsGroups', groups.length) }) : null));

    const ordered = [...windows].sort((a, b) => (b.id === S.windowId) - (a.id === S.windowId));
    let shown = 0;
    ordered.forEach((win, index) => {
      const winTabs = tabs.filter((tab) => tab.windowId === win.id).sort((a, b) => a.index - b.index);
      const visible = winTabs.filter(match);
      if (!visible.length) return;
      shown += visible.length;
      if (windows.length > 1) {
        out.push(h('div', { class: 'group-head' },
          icon('window', 13),
          h('span', { class: 'grow ellipsis', text: win.id === S.windowId ? t('tabsThisWindow') : `${t('tabsWindow')} ${index + 1}` }),
          h('span', { text: I.number(winTabs.length) }),
          win.id !== S.windowId ? S.iconButton('external', t('open'), () => chrome.windows.update(win.id, { focused: true })) : null));
      }
      const list = h('div', { class: 'list' });
      let currentGroup = null;
      let groupList = null;
      for (const tab of visible) {
        const group = groupById.get(tab.groupId);
        if (!group) {
          currentGroup = null;
          list.append(tabRow(tab, dupes));
          continue;
        }
        if (currentGroup !== group.id) {
          currentGroup = group.id;
          const color = GROUP_COLORS[group.color] || GROUP_COLORS.grey;
          const count = winTabs.filter((x) => x.groupId === group.id).length;
          groupList = h('div', { class: 'list', hidden: group.collapsed && !q });
          list.append(h('div', { class: 'tgroup', style: { '--dot': color } },
            h('div', { class: 'tgroup-head', onclick: () => chrome.tabGroups.update(group.id, { collapsed: !group.collapsed }) },
              h('span', { class: 'dot', style: { background: color } }),
              h('span', { class: 'grow ellipsis', text: group.title || t('tabsUntitledGroup') }),
              h('span', { class: 'count', text: I.number(count) }),
              S.iconButton(group.collapsed ? 'plus' : 'minus', group.collapsed ? t('tabsExpand') : t('tabsCollapse'), () => chrome.tabGroups.update(group.id, { collapsed: !group.collapsed })),
              S.iconButton('restore', t('tabsUngroup'), async () => chrome.tabs.ungroup(winTabs.filter((x) => x.groupId === group.id).map((x) => x.id))),
              S.iconButton('x', t('tabsCloseGroup'), async () => chrome.tabs.remove(winTabs.filter((x) => x.groupId === group.id).map((x) => x.id)), { danger: true })),
            groupList));
        }
        groupList.append(tabRow(tab, dupes));
      }
      out.push(list);
    });
    if (!shown) out.push(S.empty('search', t('tabsNoMatch')));
    SV.clear(container).append(...out);
    return { dupes: dupes.size, groups: groups.filter((g) => g.windowId === S.windowId).length };
  }

  function suspendCard() {
    const settings = S.settings;
    const select = h('select', {
      class: 'field', onchange: (event) => {
        settings.suspendAfter = Number(event.target.value);
        SV_STORE.save({ suspendAfter: settings.suspendAfter });
      }
    }, SUSPEND_STEPS.map((minutes) => h('option', {
      value: String(minutes),
      text: minutes === 0 ? t('tabsAutoOff') : minutes < 60 ? t('tabsMinutes', I.number(minutes)) : t('tabsHours', I.number(minutes / 60))
    })));
    select.value = String(settings.suspendAfter || 0);
    const host = /^https?:/.test(S.tab?.url || '') ? SV_STORE.hostOf(S.tab.url) : '';
    const except = new Set(settings.suspendExcept || []);
    return h('div', { class: 'card pad' },
      h('div', { class: 'setting' },
        h('div', null, h('div', { class: 'name', text: t('tabsAutoSuspend') }), h('div', { class: 'detail', text: t('tabsAutoDetail') })),
        select),
      host ? h('div', { class: 'setting' },
        h('div', { class: 'name ellipsis', text: t('tabsNeverHere', host) }),
        Page.toggle(except.has(host), t('tabsNeverHere', host), (on) => {
          if (on) except.add(host);
          else except.delete(host);
          settings.suspendExcept = [...except];
          SV_STORE.save({ suspendExcept: settings.suspendExcept });
        })) : null);
  }

  S.register('tabs', {
    render({ body }) {
      const listBox = h('div');
      const toolbar = h('div', { class: 'toolbar' });
      const dupesButton = h('button', { class: 'btn', type: 'button', onclick: closeDuplicates }, icon('duplicate', 14), t('tabsDupes'));
      const update = async () => {
        const { dupes, groups } = await renderTabs(listBox);
        SV.append(SV.clear(dupesButton), [icon('duplicate', 14), t('tabsDupes'), dupes ? h('span', { class: 'count', text: I.number(dupes) }) : null]);
        dupesButton.disabled = !dupes;
        ungroup.hidden = !groups;
      };
      const ungroup = h('button', { class: 'btn', type: 'button', onclick: ungroupAll }, icon('restore', 14), t('tabsUngroupAll'));
      toolbar.append(
        h('button', { class: 'btn', type: 'button', onclick: groupBySite }, icon('group', 14), t('tabsGroupSites')),
        ungroup,
        dupesButton,
        h('button', { class: 'btn', type: 'button', onclick: suspendOthers }, icon('snooze', 14), t('tabsSuspendOthers')),
        h('button', { class: 'btn', type: 'button', onclick: sortBySite }, icon('sort', 14), t('tabsSort')));
      const search = S.search(t('tabsSearch'), (value) => { query = value; update(); }, query);
      body.append(search.el, toolbar, listBox, suspendCard());
      update();
      requestAnimationFrame(() => search.input.focus());
      return S.onTabs(update);
    }
  });

  // MARK: Sessions

  async function loadSessions() {
    return (await chrome.storage.local.get('sessions')).sessions || [];
  }
  async function storeSessions(list) {
    await chrome.storage.local.set({ sessions: list });
  }

  async function snapshot(scope) {
    const windows = await chrome.windows.getAll({ populate: true, windowTypes: ['normal'] });
    const groups = await chrome.tabGroups.query({});
    const groupInfo = new Map(groups.map((g) => [g.id, { title: g.title || '', color: g.color }]));
    const chosen = scope === 'window' ? windows.filter((w) => w.id === S.windowId) : windows;
    return chosen.map((win) => ({
      tabs: win.tabs.filter((tab) => /^(https?|file|ftp):/.test(tab.url || '')).map((tab) => ({
        url: tab.url, title: tab.title || tab.url, pinned: tab.pinned || undefined,
        group: tab.groupId > -1 ? groupInfo.get(tab.groupId) : undefined
      }))
    })).filter((win) => win.tabs.length);
  }

  async function saveSession(scope, name) {
    const windows = await snapshot(scope);
    const count = windows.reduce((n, w) => n + w.tabs.length, 0);
    if (!count) {
      S.toast(t('sesNothing'), { icon: 'save', tone: 'warn' });
      return;
    }
    const list = await loadSessions();
    const date = new Intl.DateTimeFormat(I.locale, { dateStyle: 'medium', timeStyle: 'short' }).format(new Date());
    list.unshift({ id: crypto.randomUUID(), name: name?.trim() || `${scope === 'window' ? t('sesWindowName') : t('sesAllName')} · ${date}`, created: Date.now(), windows, count });
    await storeSessions(list.slice(0, 200));
    S.toast(t('sesSaved', I.plural('tabsCount', count)), { icon: 'save' });
  }

  async function restoreSession(session, here) {
    for (const [index, win] of session.windows.entries()) {
      let windowId;
      const created = [];
      if (here && index === 0) {
        windowId = S.windowId;
        for (const tab of win.tabs) created.push([await chrome.tabs.create({ windowId, url: tab.url, pinned: !!tab.pinned, active: false }), tab]);
      } else {
        const opened = await chrome.windows.create({ url: win.tabs[0].url, focused: index === 0 });
        windowId = opened.id;
        created.push([opened.tabs[0], win.tabs[0]]);
        if (win.tabs[0].pinned) chrome.tabs.update(opened.tabs[0].id, { pinned: true });
        for (const tab of win.tabs.slice(1)) created.push([await chrome.tabs.create({ windowId, url: tab.url, pinned: !!tab.pinned, active: false }), tab]);
      }
      // Rebuild tab groups by title + colour.
      const groups = new Map();
      for (const [opened, saved] of created) {
        if (!saved.group) continue;
        const key = `${saved.group.title}|${saved.group.color}`;
        if (!groups.has(key)) groups.set(key, { info: saved.group, ids: [] });
        groups.get(key).ids.push(opened.id);
      }
      for (const { info, ids } of groups.values()) {
        try {
          const groupId = await chrome.tabs.group({ tabIds: ids, createProperties: { windowId } });
          await chrome.tabGroups.update(groupId, { title: info.title, color: info.color });
        } catch {}
      }
    }
  }

  function sessionCard(session, rerender) {
    let open = false;
    const tabsBox = h('div', { class: 'list session-tabs', hidden: true });
    const nameEl = h('div', { class: 'name ellipsis', text: session.name, title: t('sesRename') });
    nameEl.addEventListener('dblclick', () => {
      const input = h('input', { class: 'field full', value: session.name });
      nameEl.replaceWith(input);
      input.focus();
      input.select();
      const done = async () => {
        const list = await loadSessions();
        const target = list.find((s) => s.id === session.id);
        if (target && input.value.trim()) target.name = input.value.trim();
        await storeSessions(list);
        rerender();
      };
      input.addEventListener('keydown', (event) => { if (event.key === 'Enter') done(); if (event.key === 'Escape') rerender(); });
      input.addEventListener('blur', done);
    });
    const markdown = () => session.windows.flatMap((w) => w.tabs).map((tab) => `- [${(tab.title || tab.url).replace(/([[\]])/g, '\\$1')}](${tab.url})`).join('\n');
    return h('div', { class: 'card session' },
      h('div', { class: 'row' },
        icon('save', 16),
        h('div', { class: 'grow' }, nameEl,
          h('div', { class: 'hint', text: `${S.when(session.created)} · ${I.plural('tabsCount', session.count)}${session.windows.length > 1 ? ` · ${I.plural('tabsWindows', session.windows.length)}` : ''}` })),
        S.iconButton('lines', t('sesShow'), () => {
          open = !open;
          tabsBox.hidden = !open;
          if (open && !tabsBox.firstChild) {
            tabsBox.append(...session.windows.flatMap((w) => w.tabs).map((tab) => h('div', {
              class: 'item', title: tab.url, onclick: () => chrome.tabs.create({ url: tab.url, active: false })
            }, h('img', { class: 'fav', src: S.favicon(tab.url), alt: '' }), h('div', { class: 'text' }, h('div', { class: 'title', text: tab.title }), h('div', { class: 'sub', text: S.hostOf(tab.url) })))));
          }
        }),
        S.iconButton('copy', t('sesCopyLinks'), async () => { await navigator.clipboard.writeText(markdown()); S.toast(t('copied'), { icon: 'copy' }); }),
        S.iconButton('trash', t('delete'), async () => {
          const list = (await loadSessions()).filter((s) => s.id !== session.id);
          await storeSessions(list);
          rerender();
          S.toast(t('sesDeleted'), {
            icon: 'trash', tone: 'warn',
            action: { label: t('undo'), run: async () => { const again = await loadSessions(); again.unshift(session); await storeSessions(again); rerender(); } }
          });
        }, { danger: true })),
      h('div', { class: 'row', style: { gap: '6px', 'margin-top': '10px' } },
        h('button', { class: 'btn small primary', type: 'button', onclick: () => restoreSession(session, false) }, icon('window', 14), t('sesRestore')),
        h('button', { class: 'btn small', type: 'button', onclick: () => restoreSession(session, true) }, icon('plus', 14), t('sesAddHere'))),
      tabsBox);
  }

  async function recentlyClosed() {
    try {
      const sessions = await chrome.sessions.getRecentlyClosed({ maxResults: 12 });
      return sessions.map((entry) => entry.tab ? { kind: 'tab', id: entry.tab.sessionId, title: entry.tab.title, url: entry.tab.url, time: entry.lastModified }
        : entry.window ? { kind: 'window', id: entry.window.sessionId, title: I.plural('tabsCount', entry.window.tabs?.length || 0), url: entry.window.tabs?.[0]?.url, time: entry.lastModified } : null)
        .filter((entry) => entry && (entry.kind === 'window' || /^(https?|file|ftp):/.test(entry.url || '')));
    } catch {
      return [];
    }
  }

  S.register('sessions', {
    render({ body }) {
      const name = h('input', { class: 'field full', placeholder: t('sesNamePlaceholder') });
      const listBox = h('div', { style: { display: 'flex', 'flex-direction': 'column', gap: '8px' } });
      const closedBox = h('div');
      const rerender = async () => {
        const sessions = await loadSessions();
        SV.clear(listBox).append(...(sessions.length ? sessions.map((s) => sessionCard(s, rerender)) : [S.empty('save', t('sesEmpty'))]));
        const closed = await recentlyClosed();
        SV.clear(closedBox);
        if (closed.length) {
          closedBox.append(h('div', { class: 'group-head' }, icon('restore', 13), h('span', { class: 'grow', text: t('sesRecentlyClosed') })),
            h('div', { class: 'list' }, closed.map((entry) => h('div', {
              class: 'item', title: entry.url || '', onclick: () => chrome.sessions.restore(entry.id)
            },
            entry.kind === 'window' ? h('span', { class: 'fav' }, icon('window', 16)) : h('img', { class: 'fav', src: S.favicon(entry.url), alt: '' }),
            h('div', { class: 'text' }, h('div', { class: 'title', text: entry.title || entry.url }), h('div', { class: 'sub', text: `${S.hostOf(entry.url || '')} · ${S.when(entry.time * 1000)}` })),
            h('div', { class: 'actions' }, S.iconButton('restore', t('sesRestore'), () => chrome.sessions.restore(entry.id)))))));
        }
      };
      body.append(
        h('div', { class: 'card pad' },
          h('div', { style: { 'font-weight': '600', 'margin-bottom': '4px' }, text: t('sesTitle') }),
          h('div', { class: 'hint', style: { 'margin-bottom': '10px' }, text: t('sesDetail') }),
          name,
          h('div', { class: 'row', style: { gap: '6px', 'margin-top': '10px', 'flex-wrap': 'wrap' } },
            h('button', { class: 'btn small primary', type: 'button', onclick: async () => { await saveSession('window', name.value); name.value = ''; rerender(); } }, icon('save', 14), t('sesSaveWindow')),
            h('button', { class: 'btn small', type: 'button', onclick: async () => { await saveSession('all', name.value); name.value = ''; rerender(); } }, icon('tabs', 14), t('sesSaveAll')))),
        listBox, closedBox);
      rerender();
      const offStorage = SV_STORE.onChange((changes) => { if (changes.sessions) rerender(); });
      return offStorage;
    }
  });
})();
