// Small working plates beside each field-guide chapter, built from the same parts as the desktop.
import { h, clear } from './dom.js';
import { icon, mark } from './icons.js';
import { t, lang } from './i18n.js';
import { evaluate, convert, fixLayout } from './overlays.js';
import { createPanelCard } from './panel.js';

const eq = () => h('span', { class: 'eq', 'aria-hidden': 'true' }, h('i'), h('i'), h('i'), h('i'));

function islandPlate() {
  const [eventTitle, eventDetail] = t('peekAgent');
  const stage = (label, shape) => h('figure', { class: 'state' }, h('div', { class: 'state-screen' }, shape), h('figcaption', { text: label }));
  return [
    stage(t('plateRest'), h('div', { class: 'mini-island rest' }, h('span', { class: 'mini-cover' }), h('span', { class: 'mini-lens' }), eq())),
    stage(t('plateEvent'), h('div', { class: 'mini-island event' },
      h('span', { class: 'mini-lens' }),
      h('div', { class: 'mini-event' }, h('span', { class: 'peek-icon mint' }, icon('check', 12)), h('span', null, h('b', { text: eventTitle }), h('small', { text: eventDetail }))))),
    stage(t('plateHover'), h('div', { class: 'mini-island open' },
      h('div', { class: 'mini-top' }, h('span', { class: 'mini-tab' }, icon('home', 9), t('tabHome')), h('span', { class: 'mini-lens' }), h('span', { class: 'mini-batt', text: '82%' })),
      h('div', { class: 'mini-player' }, h('span', { class: 'mini-cover big' }),
        h('span', { class: 'mini-lines' }, h('b', { text: 'Low Tide Hours' }), h('small', { text: 'Maren Vale' }), h('i', { class: 'mini-lyric', text: 'the tide came in and kept the time' }), h('span', { class: 'mini-progress' }, h('span'))))))
  ];
}

function soundPlate(bus) {
  return [createPanelCard(bus, 'mixer')];
}

function windowsPlate() {
  const frames = {
    left: [0, 0, 50, 100], left23: [0, 0, 66.6, 100], left13: [0, 0, 33.3, 100],
    right: [50, 0, 50, 100], right23: [33.4, 0, 66.6, 100], right13: [66.7, 0, 33.3, 100],
    max: [3, 2, 94, 98], restore: [22, 16, 50, 62]
  };
  let current = 'restore';
  const win = h('div', { class: 'mini-win' }, h('span', { class: 'mini-lights' }, h('i'), h('i'), h('i')));
  const label = h('div', { class: 'mini-label', role: 'status', 'aria-live': 'polite' });
  const screen = h('div', { class: 'mini-screen' }, h('div', { class: 'mini-menubar' }), h('div', { class: 'mini-desk' }, win));
  const go = (where) => {
    if (where === 'left' || where === 'right') {
      const steps = where === 'left' ? ['left', 'left23', 'left13'] : ['right', 'right23', 'right13'];
      current = steps.includes(current) ? steps[(steps.indexOf(current) + 1) % 3] : steps[0];
    } else current = where;
    const [x, y, w, hh] = frames[current];
    Object.assign(win.style, { left: `${x}%`, top: `${y}%`, width: `${w}%`, height: `${hh}%` });
    label.textContent = t('snapNames')[current];
  };
  const key = (text, where) => h('button', { class: 'keycap-button', type: 'button', onclick: () => go(where) }, h('kbd', { text }));
  const keys = h('div', { class: 'mini-keys' }, key('⌃⌥←', 'left'), key('⌃⌥→', 'right'), key('⌃⌥↩', 'max'), key('⌃⌥⌫', 'restore'));
  go('restore');
  return [screen, h('div', { class: 'mini-foot' }, keys, label)];
}

function commandPlate() {
  const input = h('input', { class: 'cmd-input', type: 'text', value: lang === 'ru' ? '100 $ в евро' : '100 $ in eur', 'aria-label': t('menuSearch'), autocomplete: 'off', spellcheck: 'false' });
  const out = h('div', { class: 'mini-results' });
  const apps = t('apps');
  const run = () => {
    const raw = input.value.trim();
    clear(out);
    const math = evaluate(raw);
    const conv = convert(raw);
    const row = (glyph, title, detail, on) => h('div', { class: `cmd-row${on ? ' on' : ''}` }, h('span', { class: 'cmd-icon' }, icon(glyph, 15)), h('span', { class: 'cmd-title', text: title }), detail ? h('span', { class: 'cmd-detail', text: detail }) : null);
    if (math != null) { out.append(row('plus', math.toLocaleString(lang === 'ru' ? 'ru-RU' : 'en-US', { maximumFractionDigits: 10 }), `${raw} =`, true)); return; }
    if (conv) { out.append(row('width', conv.text, conv.detail, true)); return; }
    let q = raw.toLowerCase();
    let found = apps.filter((name) => q && name.toLowerCase().includes(q));
    if (!found.length && /[а-яё]/i.test(q)) { q = fixLayout(q); found = apps.filter((name) => name.toLowerCase().includes(q)); if (found.length) out.append(h('div', { class: 'cmd-section', text: t('cmdLayout', q) })); }
    if (found.length) found.slice(0, 2).forEach((name, i) => out.append(row('window', name, '', i === 0)));
    else out.append(h('div', { class: 'cmd-empty', text: raw ? t('cmdEmpty') : t('plateTry') }));
  };
  input.addEventListener('input', run);
  run();
  return [h('div', { class: 'mini-cmd' }, h('div', { class: 'cmd-field' }, icon('search', 18), input), out), h('p', { class: 'plate-note', text: t('plateTry') })];
}

function chromePlate() {
  const tiles = ['pipette', 'ruler', 'note', 'camera', 'eyeOff', 'type', 'inspect', 'link', 'table', 'translate'];
  return [h('div', { class: 'mini-browser', 'aria-hidden': 'true' },
    h('div', { class: 'mini-chrome' }, h('span', { class: 'mini-lights' }, h('i'), h('i'), h('i')), h('span', { class: 'mini-omni' }, icon('lock', 9), 'fieldnotes.example')),
    h('div', { class: 'mini-page' },
      h('div', { class: 'mini-ext' }, h('div', { class: 'mini-ext-head' }, mark(12), h('b', { text: 'SAVISUL' })),
        h('div', { class: 'mini-ext-grid' }, tiles.map((glyph, i) => h('span', { class: `mini-tile${i === 9 ? ' on' : ''}` }, icon(glyph, 14))))),
      h('span', { class: 'mini-text w80' }), h('span', { class: 'mini-text w95' }), h('span', { class: 'mini-text w70' }), h('span', { class: 'mini-text w90' })))];
}

// Context Actions: pick what is selected, then an action; the result shows the way the app reports it.
function actionsPlate() {
  const kinds = t('ctxKinds');
  let kind = 0;
  const tabs = h('div', { class: 'ctx-kinds', role: 'tablist', 'aria-label': t('actionsTitle') });
  const head = h('div', { class: 'ctx-head' });
  const list = h('div', { class: 'ctx-list' });
  const result = h('div', { class: 'ctx-result', role: 'status', 'aria-live': 'polite' });
  const choose = (index) => {
    kind = index;
    const k = kinds[kind];
    clear(tabs).append(...kinds.map((item, i) => h('button', {
      type: 'button', role: 'tab', class: `ctx-kind${i === kind ? ' on' : ''}`, 'aria-selected': String(i === kind), onclick: () => choose(i)
    }, icon(item.icon, 13), h('span', { text: item.label }))));
    clear(head).append(h('span', { class: 'ctx-thumb' }, icon(k.icon, 17)),
      h('span', { class: 'ctx-what' }, h('b', { text: k.head }), h('small', { text: k.sample })),
      h('kbd', { class: 'ctx-key', text: '⌃⌥A' }));
    clear(list).append(...k.actions.map(([glyph, title, ai, outcome], i) => h('button', {
      type: 'button', class: 'ctx-row', onclick: (event) => {
        for (const row of list.querySelectorAll('.ctx-row')) row.classList.toggle('on', row === event.currentTarget);
        result.textContent = outcome;
        result.classList.toggle('ai', ai);
      }
    }, h('span', { class: `ctx-glyph${ai ? ' ai' : ''}` }, icon(glyph, 14)), h('span', { class: 'ctx-title', text: title }),
      ai ? h('span', { class: 'ctx-badge', text: t('actionsAI') }) : null, h('span', { class: 'ctx-num', text: `⌘${i + 1}` }))));
    result.textContent = t('ctxPick');
    result.classList.remove('ai');
  };
  choose(0);
  return [h('div', { class: 'mini-ctx' }, tabs, head, list), result];
}

// An automation: choose a template, run it, and watch the steps tick off while the notch shows the progress.
function autoPlate() {
  const templates = t('autoTemplates');
  let current = 0;
  let timers = [];
  const chips = h('div', { class: 'ctx-kinds' });
  const card = h('div', { class: 'auto-card' });
  const ring = h('span', { class: 'auto-ring' });
  const percent = h('span', { class: 'auto-pct', text: '' });
  const notice = h('span', { class: 'auto-notice' });
  const island = h('div', { class: 'auto-island' }, ring, h('span', { class: 'mini-lens' }), percent, notice);
  const button = h('button', { type: 'button', class: 'auto-run' });
  const stop = () => { timers.forEach(clearTimeout); timers = []; };
  const render = () => {
    stop();
    const tpl = templates[current];
    island.className = 'auto-island';
    percent.textContent = '';
    notice.textContent = '';
    ring.style.setProperty('--p', 0);
    clear(chips).append(...templates.map((item, i) => h('button', {
      type: 'button', class: `ctx-kind${i === current ? ' on' : ''}`, 'aria-pressed': String(i === current), onclick: () => { current = i; render(); }
    }, icon(item.icon, 13), h('span', { text: item.label }))));
    const line = (label, text, glyph) => h('div', { class: 'auto-line' }, h('span', { class: 'auto-label', text: label }), h('span', { class: 'auto-text' }, icon(glyph, 13), h('span', { text })));
    clear(card).append(...[
      line(t('autoWhen'), tpl.when, tpl.icon),
      tpl.cond ? line(t('autoIf'), tpl.cond, 'sliders') : null,
      h('div', { class: 'auto-line auto-do' }, h('span', { class: 'auto-label', text: t('autoDo') }),
        h('ol', { class: 'auto-steps' }, tpl.steps.map((step) => h('li', null, h('span', { class: 'auto-check' }, icon('check', 10)), h('span', { text: step })))))
    ].filter(Boolean));
    clear(button).append(icon('play', 13), h('span', { text: t('autoRun') }));
    button.disabled = false;
  };
  button.addEventListener('click', () => {
    render();
    const tpl = templates[current];
    const items = card.querySelectorAll('.auto-steps li');
    button.disabled = true;
    clear(button).append(h('span', { text: t('autoRunning') }));
    island.classList.add('live');
    items.forEach((item, i) => timers.push(setTimeout(() => {
      item.classList.add('done');
      const share = (i + 1) / items.length;
      ring.style.setProperty('--p', share);
      percent.textContent = `${Math.round(share * 100)}%`;
    }, 520 * (i + 1))));
    timers.push(setTimeout(() => {
      island.classList.remove('live');
      island.classList.add('told');
      notice.textContent = tpl.done;
      clear(button).append(icon('check', 13), h('span', { text: t('autoDone') }));
    }, 520 * items.length + 380));
    timers.push(setTimeout(() => { island.classList.remove('told'); button.disabled = false; clear(button).append(icon('play', 13), h('span', { text: t('autoRun') })); }, 520 * items.length + 3200));
  });
  render();
  return [h('div', { class: 'auto-screen' }, island), chips, card, button];
}

function panelPlate(bus) {
  return [createPanelCard(bus, 'lid')];
}

const PLATES = { island: islandPlate, sound: soundPlate, windows: windowsPlate, command: commandPlate, actions: actionsPlate, auto: autoPlate, chrome: chromePlate, panel: panelPlate };

export function renderPlates(bus) {
  for (const [id, build] of Object.entries(PLATES)) {
    const slot = document.getElementById(`plate-${id}`);
    if (slot) clear(slot).append(...build(bus));
  }
}
