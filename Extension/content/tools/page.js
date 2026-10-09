(() => {
  if ((window.top !== window && !globalThis.__savisulDemo) || !globalThis.SV) return;
  const SV = globalThis.SV;

  const I = SV_I18N;
  const t = (...args) => I.t(...args);

  // MARK: Free copy

  const BLOCKED = ['contextmenu', 'copy', 'cut', 'paste', 'selectstart', 'dragstart'];
  let unlocked = false;
  const release = (event) => {
    if (SV.isOurs(event.target)) return;
    event.stopImmediatePropagation();
  };

  function setUnlocked(on) {
    unlocked = on;
    for (const type of BLOCKED) {
      if (on) window.addEventListener(type, release, true);
      else window.removeEventListener(type, release, true);
    }
    SV.pageStyle('savisul-unlock', on
      ? '*, *::before, *::after { -webkit-user-select: text !important; user-select: text !important; -webkit-touch-callout: default !important; } ::selection { background: Highlight !important; color: HighlightText !important; }'
      : null);
  }

  SV.tools.unlock = {
    label: 'pUnlock',
    icon: 'unlock',
    kind: 'toggle',
    active: () => unlocked,
    toggle() {
      setUnlocked(!unlocked);
      SV.toast(t(unlocked ? 'unlockOn' : 'unlockOff'), { icon: 'unlock', tone: 'info' });
    },
    stop: () => setUnlocked(false)
  };

  // MARK: Edit page

  let editing = false;
  let removeEditKey = null;

  function startEdit() {
    if (editing) return;
    editing = true;
    document.designMode = 'on';
    removeEditKey = SV.onKey((event) => {
      if (event.key !== 'Escape') return false;
      stopEdit();
      return true;
    });
    SV.mode.enter({
      id: 'edit', icon: 'pencil', name: t('pEdit'), hint: t('editHint'),
      actions: [{ label: t('tShot'), icon: 'camera', run: () => SV.notch.openPanel('shot', { direct: true }) }],
      onExit: () => stopEdit()
    });
  }

  function stopEdit() {
    if (!editing) return;
    editing = false;
    document.designMode = 'off';
    removeEditKey?.();
    removeEditKey = null;
    SV.mode.exit('edit');
  }

  SV.tools.edit = { label: 'pEdit', icon: 'pencil', kind: 'mode', active: () => editing, start: startEdit, stop: stopEdit };

  // MARK: Outlines

  let outlined = false;
  const OUTLINE_CSS = `
    html *:not(savisul-notch) { outline: 1px solid rgba(219, 199, 163, 0.55) !important; outline-offset: -1px !important; }
    html :is(div, section, article, main, header, footer, nav, aside):not(savisul-notch) { outline-color: rgba(120, 170, 255, 0.6) !important; }
    html :is(p, h1, h2, h3, h4, h5, h6, li, blockquote, pre):not(savisul-notch) { outline-color: rgba(120, 220, 160, 0.65) !important; }
    html :is(a, button, input, select, textarea, label):not(savisul-notch) { outline-color: rgba(255, 120, 120, 0.7) !important; }
    html :is(img, svg, video, canvas, picture, iframe):not(savisul-notch) { outline-color: rgba(255, 196, 80, 0.8) !important; }
  `;

  SV.tools.outline = {
    label: 'pOutline',
    icon: 'outline',
    kind: 'toggle',
    active: () => outlined,
    toggle() {
      outlined = !outlined;
      SV.pageStyle('savisul-outline', outlined ? OUTLINE_CSS : null);
      SV.toast(t(outlined ? 'outlineOn' : 'outlineOff'), { icon: 'outline', tone: 'info' });
    },
    stop() {
      outlined = false;
      SV.pageStyle('savisul-outline', null);
    }
  };

  // MARK: Read aloud

  const RATES = [1, 1.25, 1.5, 2, 0.75];
  const speech = { on: false, paused: false, parts: [], index: 0, rate: 1, voice: null, lang: '' };
  let removeSpeakKey = null;

  function sourceText() {
    const selection = String(getSelection() || '').trim();
    if (selection.length > 1) return selection;
    const article = SV.reader?.text?.() || '';
    if (article.length > 250) return article;
    return (document.body?.innerText || '').trim();
  }

  function split(text) {
    const clean = text.replace(/\s+/g, ' ').trim();
    const sentences = clean.match(/[^.!?。！？…]+[.!?。！？…]+["»”')\]]*\s*|[^.!?。！？…]+$/g) || [clean];
    const parts = [];
    let current = '';
    const flush = () => {
      if (current.trim()) parts.push(current.trim());
      current = '';
    };
    for (let sentence of sentences) {
      while (sentence.length > 220) {
        let cut = sentence.lastIndexOf(', ', 200);
        if (cut < 80) cut = sentence.lastIndexOf(' ', 200);
        if (cut < 80) cut = 200;
        if (current) flush();
        parts.push(sentence.slice(0, cut + 1).trim());
        sentence = sentence.slice(cut + 1);
      }
      if ((current + sentence).length > 220) flush();
      current += sentence;
    }
    flush();
    return parts;
  }

  async function pickVoice(lang) {
    let voices = speechSynthesis.getVoices();
    if (!voices.length) {
      await new Promise((resolve) => {
        const done = () => { speechSynthesis.removeEventListener('voiceschanged', done); resolve(); };
        speechSynthesis.addEventListener('voiceschanged', done);
        setTimeout(done, 1200);
      });
      voices = speechSynthesis.getVoices();
    }
    const base = lang.toLowerCase().split('-')[0];
    const matching = voices.filter((v) => v.lang.toLowerCase().replace('_', '-').startsWith(base));
    const quality = (v) => (/(premium|enhanced|siri|natural|neural)/i.test(v.name) ? 4 : 0) + (v.lang.toLowerCase() === lang.toLowerCase() ? 2 : 0) + (v.localService ? 1 : 0) + (v.default ? 1 : 0);
    return matching.sort((a, b) => quality(b) - quality(a))[0] || null;
  }

  function detectLang(text) {
    const declared = document.documentElement.lang;
    if (declared) return declared;
    const cyr = (text.match(/[а-яёіїєґ]/gi) || []).length;
    const lat = (text.match(/[a-z]/gi) || []).length;
    if (cyr > lat) return /[іїєґ]/i.test(text) ? 'uk-UA' : 'ru-RU';
    return navigator.language || 'en-US';
  }

  function speakNext() {
    if (!speech.on) return;
    if (speech.index >= speech.parts.length) {
      stopSpeak();
      return;
    }
    const utterance = new SpeechSynthesisUtterance(speech.parts[speech.index]);
    utterance.lang = speech.voice?.lang || speech.lang;
    if (speech.voice) utterance.voice = speech.voice;
    utterance.rate = speech.rate;
    utterance.onend = () => {
      if (!speech.on || utterance !== speech.current) return;
      speech.index += 1;
      updateSpeakMode();
      speakNext();
    };
    utterance.onerror = (event) => {
      if (event.error === 'interrupted' || event.error === 'canceled') return;
      speech.index += 1;
      speakNext();
    };
    speech.current = utterance;
    speechSynthesis.speak(utterance);
  }

  function updateSpeakMode() {
    if (!speech.on) return;
    const progress = speech.parts.length ? Math.round((speech.index / speech.parts.length) * 100) : 0;
    SV.mode.update({
      hint: `${t('speakHint')} · ${I.percent(progress)}`,
      actions: [
        { label: t(speech.paused ? 'speakResume' : 'speakPause'), icon: speech.paused ? 'play' : 'pause', run: togglePause },
        { label: `${I.number(speech.rate, 2, 0)}×`, title: t('speakRate'), run: cycleRate }
      ]
    });
  }

  function togglePause() {
    if (!speech.on) return;
    speech.paused = !speech.paused;
    if (speech.paused) speechSynthesis.pause();
    else speechSynthesis.resume();
    updateSpeakMode();
  }

  function cycleRate() {
    speech.rate = RATES[(RATES.indexOf(speech.rate) + 1) % RATES.length];
    if (speech.on && !speech.paused) {
      speech.current = null;
      speechSynthesis.cancel();
      speakNext();
    }
    updateSpeakMode();
  }

  async function startSpeak() {
    if (speech.on) return;
    if (!('speechSynthesis' in window)) return;
    const text = sourceText();
    if (text.replace(/\s/g, '').length < 2) {
      SV.toast(t('speakNone'), { icon: 'wave', tone: 'warn' });
      return;
    }
    speechSynthesis.cancel();
    Object.assign(speech, { on: true, paused: false, parts: split(text.slice(0, 60000)), index: 0, lang: detectLang(text) });
    SV.mode.enter({ id: 'speak', icon: 'wave', name: t('tSpeak'), hint: t('speakHint'), onExit: () => stopSpeak() });
    updateSpeakMode();
    removeSpeakKey = SV.onKey((event) => {
      if (event.key === 'Escape') {
        stopSpeak();
        return true;
      }
      return false;
    });
    speech.voice = await pickVoice(speech.lang);
    speakNext();
  }

  function stopSpeak() {
    if (!speech.on) return;
    speech.on = false;
    speech.current = null;
    speechSynthesis.cancel();
    removeSpeakKey?.();
    removeSpeakKey = null;
    SV.mode.exit('speak');
  }

  SV.tools.speak = { label: 'tSpeak', icon: 'wave', kind: 'mode', active: () => speech.on, start: startSpeak, stop: stopSpeak };
})();
