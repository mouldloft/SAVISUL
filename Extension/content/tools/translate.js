(() => {
  if ((window.top !== window && !globalThis.__savisulDemo) || !globalThis.SV) return;
  const SV = globalThis.SV;

  const { h, icon } = SV;
  const I = SV_I18N;
  const t = (...args) => I.t(...args);

  const TARGETS = ['en', 'ru', 'uk', 'fr', 'de', 'es', 'it', 'pt', 'pl', 'nl', 'tr', 'cs', 'zh', 'ja', 'ko', 'ar', 'hi', 'vi', 'id'];
  const SKIP = new Set(['script', 'style', 'noscript', 'template', 'code', 'pre', 'kbd', 'samp', 'textarea', 'input', 'select', 'svg', 'math', 'canvas', 'savisul-notch']);
  const MAX_NODES = 6000;

  const state = {
    translated: false,
    busy: false,
    target: null,
    source: '',
    originals: new Map(),
    cache: new Map(),
    translator: null,
    observer: null,
    progress: 0
  };

  const hasApi = () => typeof globalThis.Translator?.create === 'function';
  const languageName = (code) => {
    try { return new Intl.DisplayNames([I.locale], { type: 'language' }).of(code) || code; } catch { return code; }
  };
  const targetLanguage = () => {
    const chosen = SV.settings?.translateTo;
    return chosen && chosen !== 'auto' ? chosen : I.lang;
  };

  async function detectSource(sample) {
    if (typeof globalThis.LanguageDetector?.create === 'function') {
      try {
        const detector = await LanguageDetector.create();
        const [best] = await detector.detect(sample);
        detector.destroy?.();
        if (best?.detectedLanguage && best.detectedLanguage !== 'und' && best.confidence > 0.4) return best.detectedLanguage.split('-')[0];
      } catch {}
    }
    const declared = (document.documentElement.lang || '').split('-')[0].toLowerCase();
    if (declared) return declared;
    if ((sample.match(/[а-яё]/gi) || []).length > sample.length / 4) return /[іїєґ]/i.test(sample) ? 'uk' : 'ru';
    return 'en';
  }

  function textNodes(root) {
    const out = [];
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
      acceptNode(node) {
        const value = node.nodeValue;
        if (!value || value.trim().length < 2 || !/\p{L}/u.test(value)) return NodeFilter.FILTER_REJECT;
        for (let el = node.parentElement; el && el !== root.parentElement; el = el.parentElement) {
          if (SKIP.has(el.localName) || el.isContentEditable || el.getAttribute('translate') === 'no' || el.classList.contains('notranslate')) return NodeFilter.FILTER_REJECT;
        }
        return NodeFilter.FILTER_ACCEPT;
      }
    });
    while (walker.nextNode() && out.length < MAX_NODES) out.push(walker.currentNode);
    return out;
  }

  async function translateText(value) {
    const core = value.trim();
    if (state.cache.has(core)) return state.cache.get(core);
    const result = await state.translator.translate(core);
    state.cache.set(core, result);
    return result;
  }

  async function translateNodes(nodes, onProgress) {
    let done = 0;
    let index = 0;
    const worker = async () => {
      while (index < nodes.length && state.translated && SV.alive) {
        const node = nodes[index++];
        const original = state.originals.get(node) ?? node.nodeValue;
        try {
          const result = await translateText(original);
          if (!state.translated) return;
          const lead = original.match(/^\s*/)[0];
          const tail = original.match(/\s*$/)[0];
          if (!state.originals.has(node)) state.originals.set(node, original);
          node.nodeValue = `${lead}${result}${tail}`;
        } catch {}
        done++;
        onProgress?.(done / nodes.length);
      }
    };
    await Promise.all(Array.from({ length: 4 }, worker));
  }

  function watchNew() {
    state.observer?.disconnect();
    let pending = new Set();
    const flush = SV.debounce(() => {
      const roots = [...pending].filter((n) => n.isConnected);
      pending = new Set();
      const nodes = roots.flatMap((root) => (root.nodeType === 3 ? (state.originals.has(root) ? [] : [root]) : textNodes(root).filter((n) => !state.originals.has(n))));
      if (nodes.length) translateNodes(nodes.slice(0, 800));
    }, 400);
    state.observer = new MutationObserver((records) => {
      for (const record of records) {
        if (SV.isOurs(record.target)) continue;
        for (const node of record.addedNodes) if (!SV.isOurs(node)) pending.add(node);
      }
      if (pending.size) flush();
    });
    state.observer.observe(document.body, { childList: true, subtree: true });
  }

  async function ensureTranslator(source, target, onDownload) {
    if (state.translator && state.translator.sourceLanguage === source && state.translator.targetLanguage === target) return state.translator;
    state.translator?.destroy?.();
    state.translator = null;
    const availability = await Translator.availability({ sourceLanguage: source, targetLanguage: target });
    if (availability === 'unavailable') throw new Error('pair');
    state.translator = await Translator.create({
      sourceLanguage: source,
      targetLanguage: target,
      monitor(monitor) {
        monitor.addEventListener('downloadprogress', (event) => onDownload?.(event.loaded));
      }
    });
    state.cache.clear();
    return state.translator;
  }

  function openFallback(target) {
    const url = `https://translate.google.com/translate?sl=auto&tl=${encodeURIComponent(target)}&u=${encodeURIComponent(location.href)}`;
    SV.send('open', { url });
  }

  async function translatePage(render) {
    if (state.busy) return;
    const target = targetLanguage();
    if (!hasApi()) {
      openFallback(target);
      return;
    }
    state.busy = true;
    render();
    try {
      const nodes = textNodes(document.body);
      const sample = nodes.slice(0, 80).map((n) => n.nodeValue.trim()).join(' ').slice(0, 2000);
      const source = await detectSource(sample);
      if (source === target) {
        SV.toast(t('trSame', languageName(target)), { icon: 'translate', tone: 'info' });
        return;
      }
      state.source = source;
      state.target = target;
      await ensureTranslator(source, target, (loaded) => {
        state.progress = loaded;
        render(t('trDownloading', I.percent(loaded * 100)));
      });
      state.translated = true;
      SV.notch.indicate('live', true);
      await translateNodes(nodes, (fraction) => {
        state.progress = fraction;
        render();
      });
      for (const el of document.querySelectorAll('[title], [placeholder], img[alt]')) {
        if (SV.isOurs(el)) continue;
        for (const attr of ['title', 'placeholder', 'alt']) {
          const value = el.getAttribute(attr);
          if (!value || value.length < 2 || !/\p{L}/u.test(value)) continue;
          try {
            const result = await translateText(value);
            (state.attrs ||= []).push([el, attr, value]);
            el.setAttribute(attr, result);
          } catch {}
        }
      }
      watchNew();
      SV.toast(t('trDone', languageName(source), languageName(target)), { icon: 'translate' });
    } catch (error) {
      if (String(error?.message) === 'pair') SV.toast(t('trPair', languageName(state.source || '?'), languageName(target)), { icon: 'translate', tone: 'warn', duration: 4200 });
      else SV.toast(t('trFailed'), { icon: 'translate', tone: 'warn' });
      if (!state.originals.size) state.translated = false;
    } finally {
      state.busy = false;
      render();
    }
  }

  function restore() {
    state.translated = false;
    state.observer?.disconnect();
    state.observer = null;
    for (const [node, original] of state.originals) if (node.isConnected) node.nodeValue = original;
    state.originals.clear();
    for (const [el, attr, value] of state.attrs || []) el.setAttribute(attr, value);
    state.attrs = [];
    SV.notch.indicate('live', !!SV.notch.mode);
  }

  async function translateSelection(out) {
    const textValue = String(getSelection() || '').trim();
    if (!textValue) {
      SV.toast(t('trSelectFirst'), { icon: 'translate', tone: 'info' });
      return;
    }
    const target = targetLanguage();
    if (!hasApi()) {
      SV.send('open', { url: `https://translate.google.com/?sl=auto&tl=${encodeURIComponent(target)}&text=${encodeURIComponent(textValue.slice(0, 4000))}&op=translate` });
      return;
    }
    SV.clear(out).append(h('div', { class: 'row' }, h('span', { class: 'spinner' }), h('span', { class: 'hint', text: t('trWorking') })));
    try {
      const source = await detectSource(textValue);
      if (source === target) {
        SV.clear(out).append(h('div', { class: 'hint', text: t('trSame', languageName(target)) }));
        return;
      }
      const translator = await ensureTranslator(source, target);
      const result = await translator.translate(textValue);
      SV.clear(out).append(h('div', { class: 'card tr-result' },
        h('div', { class: 'hint', text: `${languageName(source)} → ${languageName(target)}` }),
        h('div', { class: 'tr-text', text: result }),
        h('div', { class: 'row', style: { 'justify-content': 'flex-end' } },
          h('button', { class: 'btn small', type: 'button', onclick: async () => { await SV.copy(result); SV.toast(t('copied'), { icon: 'copy' }); } }, icon('copy', 14), t('copy')))));
    } catch {
      SV.clear(out).append(h('div', { class: 'hint', text: t('trFailed') }));
    }
  }

  function panel(api) {
    const status = h('div', { class: 'hint' });
    const actions = h('div', { class: 'row', style: { gap: '6px', 'flex-wrap': 'wrap' } });
    const out = h('div');
    const render = (note) => {
      SV.clear(actions);
      if (state.busy) {
        actions.append(h('button', { class: 'btn primary', type: 'button', disabled: true }, h('span', { class: 'spinner' }), note || t('trProgress', I.percent(state.progress * 100))));
      } else if (state.translated) {
        actions.append(h('button', { class: 'btn primary', type: 'button', onclick: () => { restore(); render(); } }, icon('restore', 15), t('trOriginal')));
      } else {
        actions.append(h('button', { class: 'btn primary', type: 'button', 'data-autofocus': '', onclick: () => translatePage(render) }, icon('translate', 15), t('trPage')));
      }
      actions.append(h('button', { class: 'btn', type: 'button', onclick: () => translateSelection(out).then(() => api.refit()) }, icon('type', 15), t('trSelection')));
      status.textContent = hasApi()
        ? (state.translated ? t('trDone', languageName(state.source), languageName(state.target)) : t('trOnDevice'))
        : t('trNoApi');
      api.refit();
    };
    const select = h('select', {
      class: 'select', 'aria-label': t('trTo'), onchange: (event) => {
        SV.settings.translateTo = event.target.value;
        SV_STORE.save({ translateTo: event.target.value });
      }
    }, h('option', { value: 'auto', text: `${t('setAuto')} · ${languageName(I.lang)}` }), TARGETS.map((code) => h('option', { value: code, text: languageName(code) })));
    select.value = SV.settings?.translateTo || 'auto';
    api.body.append(
      h('div', { class: 'card', style: { padding: '4px 12px' } },
        h('div', { class: 'setting' }, h('span', { class: 'name', text: t('trTo') }), select)),
      actions, status, out);
    render();
    return null;
  }

  SV.css += `
.select { height: 28px; max-width: 220px; padding: 0 28px 0 10px; border-radius: 9px; border: 0; background: var(--tile-hover); color: var(--ink); font: inherit; font-size: 12.5px;
  appearance: none; background-image: linear-gradient(45deg, transparent 50%, var(--ink-2) 50%), linear-gradient(135deg, var(--ink-2) 50%, transparent 50%);
  background-position: calc(100% - 14px) 12px, calc(100% - 9px) 12px; background-size: 5px 5px; background-repeat: no-repeat; cursor: pointer; }
.select option { background: #222; color: #eee; }
.tr-result { display: flex; flex-direction: column; gap: 8px; }
.tr-text { font-size: 13.5px; line-height: 1.5; white-space: pre-wrap; max-height: 36vh; overflow-y: auto; }
`;

  SV.tools.translate = {
    label: 'tTranslate',
    icon: 'translate',
    kind: 'panel',
    title: () => t('trTitle'),
    panel,
    active: () => state.translated,
    stop: () => { if (state.translated) restore(); }
  };
})();
