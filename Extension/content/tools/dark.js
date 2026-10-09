(() => {
  if ((window.top !== window && !globalThis.__savisulDemo) || !globalThis.SV) return;
  const SV = globalThis.SV;

  const t = (...args) => SV_I18N.t(...args);
  const html = document.documentElement;

  const loaded = () => getComputedStyle(html).getPropertyValue('--savisul-dark-loaded').trim() === '1';
  const enabled = () => loaded() && html.getAttribute('data-savisul-dark') !== 'off';

  // Reads the site's own background with dark.css switched off for the duration of the check.
  function pageIsDark() {
    const previous = html.getAttribute('data-savisul-dark');
    html.setAttribute('data-savisul-dark', 'off');
    try {
      for (const el of [document.body, html]) {
        if (!el) continue;
        const color = SV.parseColor(getComputedStyle(el).backgroundColor);
        if (color && color.a > 0.5) return SV.luminance(color) < 0.2;
      }
      const center = SV.elementAt(innerWidth / 2, innerHeight / 2);
      return center ? SV.luminance(SV.backgroundOf(center)) < 0.2 : false;
    } finally {
      if (previous == null) html.removeAttribute('data-savisul-dark');
      else html.setAttribute('data-savisul-dark', previous);
    }
  }

  async function apply(on) {
    if (on) {
      html.removeAttribute('data-savisul-dark');
      if (!loaded()) {
        try { await SV.send('dark:inject'); } catch {}
      }
    } else {
      html.setAttribute('data-savisul-dark', 'off');
    }
    SV.notch.indicate('dark', on);
  }

  SV.tools.dark = {
    label: 'pDark',
    icon: 'moon',
    kind: 'toggle',
    active: enabled,
    apply,
    async toggle() {
      const on = !enabled();
      await apply(on);
      if (!globalThis.__savisulDemo) SV.send('dark:set', { host: SV.host, mode: on }).catch(() => {});
      SV.toast(t(on ? 'darkOn' : 'darkOff', SV.site || location.protocol.replace(':', '')), { icon: on ? 'moon' : 'sun', tone: 'info' });
      if (SV.notch.view === 'home') SV.notch.openHome();
    },
    init(settings) {
      const site = settings.darkSites?.[SV.host];
      if (loaded() && settings.darkAll && site === undefined && pageIsDark()) {
        html.setAttribute('data-savisul-dark', 'off');
        SV.send('dark:set', { host: SV.host, mode: 'native' }).catch(() => {});
      }
      SV.notch.indicate('dark', enabled());
    }
  };
})();
