(() => {
  const I = SV_I18N;
  let toastTimer = 0;

  const Page = {
    settings: null,
    appLanguage: null,

    async init() {
      Page.settings = await SV_STORE.load();
      Page.appLanguage = (await chrome.storage.local.get('appLanguage')).appLanguage || null;
      I.lang = I.resolve(Page.settings.language, Page.appLanguage);
      document.documentElement.lang = I.lang;
      Page.applyTheme();
      matchMedia('(prefers-color-scheme: light)').addEventListener('change', Page.applyTheme);
      return Page.settings;
    },

    applyTheme() {
      let theme = Page.settings?.theme || 'dark';
      if (theme === 'auto') theme = matchMedia('(prefers-color-scheme: light)').matches ? 'light' : 'dark';
      document.documentElement.dataset.theme = theme;
    },

    toast(text, { icon = 'check', tone = 'ok', action = null, duration = 2600 } = {}) {
      let el = document.getElementById('toast');
      if (!el) {
        el = SV.h('div', { id: 'toast', class: 'toast', role: 'status', 'aria-live': 'polite' });
        document.body.append(el);
      }
      SV.clear(el).append(SV.icon(icon, 16), SV.h('span', { class: 'grow', text }));
      if (action) el.append(SV.h('button', { class: 'btn small', type: 'button', onclick: action.run }, action.label));
      el.dataset.tone = tone;
      requestAnimationFrame(() => el.classList.add('on'));
      clearTimeout(toastTimer);
      toastTimer = setTimeout(() => el.classList.remove('on'), action ? Math.max(duration, 6000) : duration);
    },

    seg(items, selected, onSelect) {
      const group = SV.h('div', { class: 'seg', role: 'group' });
      for (const [value, label] of items) {
        group.append(SV.h('button', {
          type: 'button', 'aria-pressed': String(value === selected),
          onclick: (event) => {
            group.querySelectorAll('button').forEach((b) => b.setAttribute('aria-pressed', String(b === event.currentTarget)));
            onSelect(value);
          }
        }, label));
      }
      return group;
    },

    toggle(on, label, onChange) {
      return SV.h('button', {
        class: 'switch', type: 'button', role: 'switch', 'aria-checked': String(!!on), 'aria-label': label,
        onclick: (event) => {
          const next = event.currentTarget.getAttribute('aria-checked') !== 'true';
          event.currentTarget.setAttribute('aria-checked', String(next));
          onChange(next);
        }
      });
    },

    when(timestamp) {
      const date = new Date(timestamp);
      const days = Math.round((Date.now() - timestamp) / 86400000);
      if (days < 1) return new Intl.DateTimeFormat(I.locale, { hour: '2-digit', minute: '2-digit' }).format(date);
      if (days < 7) return new Intl.RelativeTimeFormat(I.locale, { numeric: 'auto' }).format(-days, 'day');
      return new Intl.DateTimeFormat(I.locale, { day: 'numeric', month: 'short', year: date.getFullYear() === new Date().getFullYear() ? undefined : 'numeric' }).format(date);
    }
  };

  globalThis.Page = Page;
})();
