(() => {
  if ((window.top !== window && !globalThis.__savisulDemo) || !globalThis.SV) return;
  const SV = globalThis.SV;

  const { h, icon } = SV;
  const I = SV_I18N;
  const t = (...args) => I.t(...args);

  let notes = { page: null, site: null };
  let scope = null;
  let url = location.href;

  async function refresh() {
    try {
      notes = await SV_STORE.getNotes(location.href);
    } catch {
      return;
    }
    SV.notch.indicate('note', !!(notes.page || notes.site));
  }

  function watchUrl() {
    const check = () => {
      if (location.href === url) return;
      url = location.href;
      refresh();
    };
    if (window.navigation?.addEventListener) {
      const onNavigate = () => setTimeout(check, 0);
      window.navigation.addEventListener('navigatesuccess', onNavigate);
      SV.cleanups.push(() => window.navigation.removeEventListener('navigatesuccess', onNavigate));
    }
    const timer = setInterval(check, 2000);
    SV.cleanups.push(() => clearInterval(timer));
    SV.listen(window, 'popstate', check);
  }

  function panel(api) {
    scope ||= notes.page || !notes.site ? 'page' : 'site';
    const body = api.body;
    const area = h('textarea', { class: 'note', spellcheck: 'true', 'data-autofocus': '' });
    const status = h('span', { class: 'hint grow' });
    let dirty = false;
    let saving = null;

    const describe = () => {
      const count = area.value.length;
      status.textContent = count ? I.plural('noteChars', count) : '';
    };

    const save = async () => {
      if (!dirty) return;
      dirty = false;
      const note = await SV_STORE.saveNote(scope, location.href, area.value, document.title);
      notes[scope] = note;
      SV.notch.indicate('note', !!(notes.page || notes.site));
      status.textContent = `${t('noteSaved')} · ${area.value.length ? I.plural('noteChars', area.value.length) : ''}`.replace(/ · $/, '');
    };
    const queueSave = SV.debounce(() => { saving = save(); }, 450);

    const load = () => {
      const note = notes[scope];
      area.value = note?.text || '';
      area.placeholder = scope === 'site' ? t('notePlaceholderSite', SV.host) : t('notePlaceholder');
      describe();
      autosize();
    };

    const autosize = () => {
      area.style.height = 'auto';
      area.style.height = `${SV.clamp(area.scrollHeight + 2, 150, 360)}px`;
      api.refit();
    };

    const scopes = SV.seg([['page', t('noteScopePage')], ['site', t('noteScopeSite')]], scope, async (value) => {
      await save();
      scope = value;
      scopes.querySelectorAll('button').forEach((b, i) => b.setAttribute('aria-pressed', String((i === 0 ? 'page' : 'site') === scope)));
      load();
      area.focus();
    });

    const remove = SV.iconButton('trash', t('delete'), async () => {
      area.value = '';
      dirty = true;
      await save();
      notes[scope] = null;
      SV.notch.indicate('note', !!(notes.page || notes.site));
      describe();
      SV.toast(t('noteDeleted'), { icon: 'trash', tone: 'info' });
    });

    area.addEventListener('input', () => {
      dirty = true;
      describe();
      autosize();
      queueSave();
    });

    body.append(
      h('div', { class: 'row' }, scopes, h('span', { class: 'grow' }), remove),
      area,
      h('div', { class: 'row' }, status,
        h('button', { class: 'btn small', type: 'button', onclick: () => SV.send('open', { url: chrome.runtime.getURL('pages/options.html#notes') }) }, icon('note', 14), t('noteAll'))));
    load();
    return () => { save(); };
  }

  SV.tools.notes = {
    label: 'tNote',
    icon: 'note',
    kind: 'panel',
    title: () => t('noteTitle'),
    badge: () => !!(notes.page || notes.site),
    panel,
    init() {
      refresh();
      watchUrl();
      SV.cleanups.push(SV_STORE.onChange((changes) => {
        if (Object.keys(changes).some((key) => key === SV_STORE.pageKey(location.href) || key === SV_STORE.siteKey(location.href))) refresh();
      }));
    }
  };
})();
