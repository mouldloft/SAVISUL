(() => {
  if ((window.top !== window && !globalThis.__savisulDemo) || globalThis.__savisulEarly) return;
  globalThis.__savisulEarly = true;

  // Keys typed into the notch must not reach the page's own shortcuts. After an extension update the
  // previous copy's listeners stay on the page, so each copy only reacts to the notch it created.
  const keyEvents = ['keydown', 'keyup', 'keypress'];
  const fromNotch = (event) => {
    const sv = globalThis.SV;
    const notch = sv?.alive ? sv.root?.host : null;
    return !!notch && event.composedPath().includes(notch);
  };
  for (const type of keyEvents) {
    window.addEventListener(type, (event) => {
      if (!fromNotch(event)) return;
      event.stopImmediatePropagation();
      if (type === 'keydown') globalThis.__savisulKeys?.(event);
    }, true);
  }

  const host = location.hostname.replace(/^www\./, '');
  chrome.storage.local.get('zapRules').then(({ zapRules }) => {
    const rules = zapRules?.[host];
    if (!rules?.length) return;
    let style = document.getElementById('savisul-zap-saved');
    if (!style) {
      style = document.createElement('style');
      style.id = 'savisul-zap-saved';
      (document.head || document.documentElement).appendChild(style);
    }
    style.textContent = rules.map((selector) => `${selector}{display:none!important}`).join('\n');
  }).catch(() => {});
})();
