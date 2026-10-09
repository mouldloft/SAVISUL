(() => {
  const { h, icon } = SV;
  const I = SV_I18N;
  const t = (...args) => I.t(...args);
  const S = Sidebar;

  // MARK: Bookmarks

  let folderPath = [];
  let bookmarkQuery = '';

  function bookmarkRow(node, rerender) {
    if (!node.url) {
      return h('div', { class: 'item', onclick: () => { folderPath.push({ id: node.id, title: node.title }); rerender(); } },
        h('span', { class: 'folder-icon' }, icon('folder', 16)),
        h('div', { class: 'text' }, h('div', { class: 'title', text: node.title || t('bmUntitled') })),
        h('div', { class: 'actions' }, S.iconButton('external', t('bmOpenAll'), async () => {
          const children = (await chrome.bookmarks.getChildren(node.id)).filter((c) => c.url);
          for (const child of children.slice(0, 40)) chrome.tabs.create({ url: child.url, active: false });
          S.toast(t('bmOpened', I.number(Math.min(children.length, 40))), { icon: 'tabs' });
        })));
    }
    return h('div', {
      class: 'item', title: node.url,
      onclick: (event) => (event.metaKey || event.ctrlKey ? chrome.tabs.create({ url: node.url, active: false }) : chrome.tabs.update(S.tab.id, { url: node.url })),
      onauxclick: (event) => { if (event.button === 1) chrome.tabs.create({ url: node.url, active: false }); }
    },
    h('img', { class: 'fav', src: S.favicon(node.url), alt: '', loading: 'lazy' }),
    h('div', { class: 'text' }, h('div', { class: 'title', text: node.title || node.url }), h('div', { class: 'sub', text: S.hostOf(node.url) })),
    h('div', { class: 'actions' },
      S.iconButton('external', t('bmNewTab'), () => chrome.tabs.create({ url: node.url, active: false })),
      S.iconButton('trash', t('delete'), async () => {
        const saved = { parentId: node.parentId, index: node.index, title: node.title, url: node.url };
        await chrome.bookmarks.remove(node.id);
        rerender();
        S.toast(t('bmDeleted'), { icon: 'trash', tone: 'warn', action: { label: t('undo'), run: async () => { await chrome.bookmarks.create(saved); rerender(); } } });
      }, { danger: true })));
  }

  async function findDuplicateBookmarks() {
    const [root] = await chrome.bookmarks.getTree();
    const seen = new Map();
    const walk = (node) => {
      if (node.url) {
        const key = SV_STORE.normalizeUrl(node.url);
        if (!seen.has(key)) seen.set(key, []);
        seen.get(key).push(node);
      }
      node.children?.forEach(walk);
    };
    walk(root);
    return [...seen.values()].filter((list) => list.length > 1);
  }

  S.register('bookmarks', {
    render({ body }) {
      const listBox = h('div');
      const starBox = h('div');
      let showDupes = false;

      const renderStar = async () => {
        const tab = S.tab;
        SV.clear(starBox);
        if (!tab || !/^(https?|file):/.test(tab.url || '')) return;
        const existing = await chrome.bookmarks.search({ url: tab.url }).catch(() => []);
        starBox.append(h('div', { class: 'card ai-context' },
          h('img', { class: 'fav', src: S.favicon(tab.url), alt: '' }),
          h('div', { class: 'grow' }, h('div', { class: 'ellipsis', style: { 'font-weight': '600' }, text: tab.title }), h('div', { class: 'hint ellipsis', text: S.hostOf(tab.url) })),
          existing.length
            ? h('button', { class: 'btn small', type: 'button', onclick: async () => { for (const b of existing) await chrome.bookmarks.remove(b.id); renderStar(); rerender(); } }, icon('star', 14), t('bmRemove'))
            : h('button', { class: 'btn small primary', type: 'button', onclick: async () => {
              const parentId = folderPath.at(-1)?.id;
              await chrome.bookmarks.create({ title: tab.title, url: tab.url, ...(parentId ? { parentId } : {}) });
              S.toast(t('bmAdded'), { icon: 'star' });
              renderStar();
              rerender();
            } }, icon('star', 14), t('bmAdd'))));
      };

      const rerender = async () => {
        const out = [];
        if (showDupes) {
          const dupes = await findDuplicateBookmarks();
          out.push(h('div', { class: 'row' },
            h('span', { class: 'grow', style: { 'font-weight': '600' }, text: t('bmDupesTitle', I.number(dupes.length)) }),
            h('button', { class: 'btn small', type: 'button', onclick: () => { showDupes = false; rerender(); } }, t('done'))));
          if (!dupes.length) out.push(S.empty('star', t('bmNoDupes')));
          else {
            out.push(h('button', {
              class: 'btn small primary', type: 'button', onclick: async () => {
                let removed = 0;
                for (const list of dupes) for (const node of list.slice(1)) { await chrome.bookmarks.remove(node.id); removed++; }
                S.toast(t('bmDupesRemoved', I.number(removed)), { icon: 'trash' });
                rerender();
              }
            }, icon('trash', 14), t('bmRemoveDupes')));
            for (const list of dupes) out.push(h('div', { class: 'list' }, list.map((node) => bookmarkRow(node, rerender))));
          }
        } else if (bookmarkQuery.trim()) {
          const results = (await chrome.bookmarks.search(bookmarkQuery.trim())).filter((node) => node.url).slice(0, 150);
          out.push(results.length ? h('div', { class: 'list' }, results.map((node) => bookmarkRow(node, rerender))) : S.empty('search', t('bmNoMatch')));
        } else {
          const parentId = folderPath.at(-1)?.id;
          if (!parentId) {
            const recent = await chrome.bookmarks.getRecent(8);
            if (recent.length) {
              out.push(h('div', { class: 'group-head' }, icon('restore', 13), h('span', { class: 'grow', text: t('bmRecent') })));
              out.push(h('div', { class: 'list' }, recent.map((node) => bookmarkRow(node, rerender))));
            }
            const [root] = await chrome.bookmarks.getTree();
            out.push(h('div', { class: 'group-head' }, icon('folder', 13), h('span', { class: 'grow', text: t('bmFolders') })));
            out.push(h('div', { class: 'list' }, root.children.map((node) => bookmarkRow(node, rerender))));
          } else {
            const children = await chrome.bookmarks.getChildren(parentId);
            out.push(h('div', { class: 'crumbs' },
              h('button', { type: 'button', onclick: () => { folderPath = []; rerender(); } }, t('sbBookmarks')),
              ...folderPath.flatMap((crumb, index) => ['›', h('button', { type: 'button', onclick: () => { folderPath = folderPath.slice(0, index + 1); rerender(); } }, crumb.title)])));
            out.push(children.length
              ? h('div', { class: 'list' }, [...children.filter((c) => !c.url), ...children.filter((c) => c.url)].map((node) => bookmarkRow(node, rerender)))
              : S.empty('folder', t('bmEmptyFolder')));
          }
        }
        SV.clear(listBox).append(...out);
      };

      const search = S.search(t('bmSearch'), (value) => { bookmarkQuery = value; rerender(); }, bookmarkQuery);
      body.append(search.el, starBox,
        h('div', { class: 'toolbar' }, h('button', { class: 'btn', type: 'button', onclick: () => { showDupes = true; rerender(); } }, icon('duplicate', 14), t('bmFindDupes'))),
        listBox);
      renderStar();
      rerender();
      const offTabs = S.onTabs((kind) => { if (kind === 'active') renderStar(); });
      const onChange = () => rerender();
      for (const event of ['onCreated', 'onRemoved', 'onChanged', 'onMoved']) chrome.bookmarks[event].addListener(onChange);
      return () => {
        offTabs();
        for (const event of ['onCreated', 'onRemoved', 'onChanged', 'onMoved']) chrome.bookmarks[event].removeListener(onChange);
      };
    }
  });

  // MARK: Notes

  let noteQuery = '';
  let noteScope = 'page';

  S.register('notes', {
    render({ body }) {
      const editor = h('div');
      const listBox = h('div');
      let saveTimer = 0;

      const renderEditor = async () => {
        SV.clear(editor);
        const tab = S.tab;
        if (!tab || !/^(https?|file):/.test(tab.url || '')) {
          editor.append(h('div', { class: 'card pad hint', text: t('notesNoPage') }));
          return;
        }
        const notes = await SV_STORE.getNotes(tab.url);
        const area = h('textarea', { class: 'field full', rows: '6', placeholder: noteScope === 'site' ? t('notePlaceholderSite', S.hostOf(tab.url)) : t('notePlaceholder') });
        area.value = notes[noteScope]?.text || '';
        const status = h('span', { class: 'hint grow', text: notes[noteScope] ? `${t('noteSaved')} · ${S.when(notes[noteScope].updated)}` : '' });
        area.addEventListener('input', () => {
          clearTimeout(saveTimer);
          saveTimer = setTimeout(async () => {
            await SV_STORE.saveNote(noteScope, tab.url, area.value, tab.title);
            status.textContent = t('noteSaved');
            renderList();
          }, 450);
        });
        editor.append(h('div', { class: 'card pad' },
          h('div', { class: 'row', style: { 'margin-bottom': '10px' } },
            Page.seg([['page', t('noteScopePage')], ['site', t('noteScopeSite')]], noteScope, (value) => { noteScope = value; renderEditor(); }),
            h('span', { class: 'grow' }),
            S.iconButton('trash', t('delete'), async () => { await SV_STORE.saveNote(noteScope, tab.url, '', tab.title); renderEditor(); renderList(); }, { danger: true })),
          area,
          h('div', { class: 'row', style: { 'margin-top': '6px' } }, status, h('span', { class: 'hint ellipsis', text: noteScope === 'site' ? S.hostOf(tab.url) : tab.title }))));
      };

      const renderList = async () => {
        const q = noteQuery.trim().toLowerCase();
        const notes = (await SV_STORE.allNotes()).filter((n) => !q || `${n.text} ${n.title} ${n.url}`.toLowerCase().includes(q));
        SV.clear(listBox).append(
          h('div', { class: 'group-head' }, icon('note', 13), h('span', { class: 'grow', text: t('notesAll', I.number(notes.length)) })),
          notes.length ? h('div', { class: 'list' }, notes.map((note) => h('div', {
            class: 'item', title: note.url, onclick: () => chrome.tabs.update(S.tab.id, { url: note.url })
          },
          h('img', { class: 'fav', src: S.favicon(note.url), alt: '' }),
          h('div', { class: 'text' },
            h('div', { class: 'title', text: note.text.split('\n')[0].slice(0, 120) }),
            h('div', { class: 'sub', text: `${note.scope === 'site' ? `${t('noteScopeSite')} · ` : ''}${note.title || note.host} · ${S.when(note.updated)}` })),
          h('div', { class: 'actions' }, S.iconButton('external', t('bmNewTab'), () => chrome.tabs.create({ url: note.url, active: false })))))) : S.empty('note', t('notesEmpty')));
      };

      const search = S.search(t('notesSearch'), (value) => { noteQuery = value; renderList(); }, noteQuery);
      body.append(editor, search.el, listBox);
      renderEditor();
      renderList();
      return S.onTabs((kind) => { if (kind === 'active') renderEditor(); });
    }
  });
})();
