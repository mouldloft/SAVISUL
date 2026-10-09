// The island: a replica of SAVISUL's notch island with the app's states (collapsed, peek, expanded)
// and its four tabs. Sample data only; nothing leaves the page.
import { h, clear, reducedMotion, coarsePointer } from './dom.js';
import { icon } from './icons.js';
import { t, onLang } from './i18n.js';
import { CONFIG } from './config.js';

const SVGNS = 'http://www.w3.org/2000/svg';

// Fictional tracks with original lyric lines, so the demo never shows someone else's music.
const TRACKS = [
  { title: 'Low Tide Hours', artist: 'Maren Vale', length: 214, art: ['#e7c48f', '#8a4f2a', '#1d1410'], shape: 'sun',
    lyrics: ['We left the porch light on for no one', 'the tide came in and kept the time', 'low tide hours, slow and golden', 'nothing to fix and nothing to find', 'stay a while, the night is open', 'the water knows the way back home'] },
  { title: 'Glasshouse', artist: 'North of Nine', length: 188, art: ['#a9c7bd', '#2f5b57', '#0f1c1c'], shape: 'rings',
    lyrics: ['Every window holds a different morning', 'I keep the brightest one for you', 'glasshouse, glasshouse', 'light comes in the way it wants to', 'we grow toward whatever’s warm', 'and leave the shadows to the floor'] },
  { title: 'Signal Fires', artist: 'Ilse Moreau', length: 231, art: ['#f0a36b', '#7a2e2a', '#170c0c'], shape: 'waves',
    lyrics: ['Count the hills between the towns', 'every fire says I’m still around', 'signal fires along the coast', 'burning low but burning close', 'if you see the light, come down', 'there’s a seat by the fire now'] }
];

function coverArt(track, size) {
  const svg = document.createElementNS(SVGNS, 'svg');
  svg.setAttribute('viewBox', '0 0 100 100');
  svg.setAttribute('width', size);
  svg.setAttribute('height', size);
  svg.setAttribute('aria-hidden', 'true');
  const [light, mid, dark] = track.art;
  const id = `g${Math.random().toString(36).slice(2, 8)}`;
  let shape = '';
  if (track.shape === 'sun') {
    shape = `<circle cx="64" cy="40" r="17" fill="${light}"/>` +
      [0, 1, 2, 3].map((i) => `<path d="M0 ${70 + i * 8} Q 25 ${62 + i * 8} 50 ${70 + i * 8} T 100 ${70 + i * 8} V100 H0Z" fill="${dark}" fill-opacity="${0.45 + i * 0.15}"/>`).join('');
  } else if (track.shape === 'rings') {
    shape = [34, 26, 18, 10].map((r, i) => `<circle cx="50" cy="54" r="${r}" fill="none" stroke="${light}" stroke-opacity="${0.35 + i * 0.18}" stroke-width="${2.2 + i}"/>`).join('') +
      `<rect x="0" y="78" width="100" height="22" fill="${dark}" fill-opacity=".7"/>`;
  } else {
    shape = [0, 1, 2, 3, 4].map((i) => `<path d="M-5 ${36 + i * 13} C 20 ${26 + i * 13}, 40 ${48 + i * 13}, 60 ${36 + i * 13} S 95 ${28 + i * 13}, 105 ${38 + i * 13}" fill="none" stroke="${light}" stroke-opacity="${0.9 - i * 0.15}" stroke-width="3.2"/>`).join('');
  }
  svg.innerHTML = `<defs><linearGradient id="${id}" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="${mid}"/><stop offset="1" stop-color="${dark}"/></linearGradient></defs>
    <rect width="100" height="100" fill="url(#${id})"/>${shape}`;
  return svg;
}

const fmt = (s) => `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, '0')}`;

const AGENTS = [
  { id: 'claude', name: 'Claude Code', state: 'working', minutes: 3, project: 'savisul-site', color: '#d98a6a', glyph: 'burst', usage: ['214K', '19:00', 0.62] },
  { id: 'cursor', name: 'Cursor', state: 'idle', minutes: 14, project: 'dotfiles', color: '#cfcac2', glyph: 'cube' },
  { id: 'codex', name: 'Codex', state: 'finished', minutes: 12, project: 'api-gateway', color: '#9fb4d8', glyph: 'hex' },
  { id: 'copilot', name: 'Copilot', state: 'none', color: '#b59ad8', glyph: 'spark' }
];

function agentGlyph(kind, color) {
  const svg = document.createElementNS(SVGNS, 'svg');
  svg.setAttribute('viewBox', '0 0 24 24');
  svg.setAttribute('width', 16);
  svg.setAttribute('height', 16);
  svg.setAttribute('aria-hidden', 'true');
  const paths = {
    burst: 'M12 3v18M3 12h18M5.6 5.6l12.8 12.8M18.4 5.6 5.6 18.4',
    cube: 'M12 3 20 7.5v9L12 21l-8-4.5v-9Z M4 7.5 12 12l8-4.5 M12 12v9',
    hex: 'M12 3.5 19.5 8v8L12 20.5 4.5 16V8Z M12 9.5a2.5 2.5 0 1 1 0 5 2.5 2.5 0 0 1 0-5Z',
    spark: 'M4 12c3 0 5-2 8-8 3 6 5 8 8 8-3 0-5 2-8 8-3-6-5-8-8-8Z'
  };
  svg.innerHTML = `<path d="${paths[kind]}" fill="none" stroke="${color}" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>`;
  return svg;
}

const DOWNLOADS = [
  { name: () => `SAVISUL-${CONFIG.version}.dmg`, size: '2.1 MB', when: ['dlNow'], kind: 'disk' },
  { name: () => 'Q3 roadmap.pdf', size: '840 KB', when: ['dlMin', 12], kind: 'pdf' },
  { name: () => 'night-ridge.heic', size: '3.4 MB', when: ['dlHour', 1], kind: 'image' },
  { name: () => 'invoice-1043.pdf', size: '96 KB', when: ['dlYesterday'], kind: 'pdf' }
];

function fileThumb(kind) {
  const el = h('span', { class: `file-thumb ${kind}`, 'aria-hidden': 'true' });
  if (kind === 'disk') el.append(icon('laptop', 14));
  else if (kind === 'pdf') el.append(h('b', { text: 'PDF' }));
  else if (kind === 'image') el.append(icon('image', 14));
  else el.append(icon('page', 14));
  return el;
}

const HEIGHTS = { home: 206, agents: 236, files: 214, camera: 196 };
const PEEKS = {
  agent: ['peekAgent', 'check', 'mint'],
  charging: ['peekCharging', 'bolt', 'mint'],
  headphones: ['peekHeadphones', 'headphones', ''],
  meeting: ['peekMeeting', 'calendar', ''],
  download: ['peekDownload', 'download', ''],
  timer: ['peekTimer', 'timer', 'champagne'],
  copied: ['peekCopied', 'copy', 'champagne'],
  mics: ['peekMics', 'micOff', 'amber'],
  micsOn: ['peekMicsOn', 'mic', 'mint'],
  output: ['peekOutput', 'speaker', ''],
  opening: ['peekOpening', 'window', ''],
  pasted: ['peekPasted', 'clipboard', 'champagne'],
  plain: ['peekPlain', 'type', 'champagne']
};

export function createIsland(host, bus) {
  const state = {
    mode: 'collapsed', tab: 'home', pinned: false, hovering: false,
    track: 0, pos: 47, playing: true,
    timer: null, eventMinutes: 18,
    shelf: [], cameraStream: null, peekTimer: null, leaveTimer: null, enterTimer: null, introDone: false
  };

  const root = h('div', { class: 'island', 'data-mode': 'collapsed', 'data-tab': 'home' });
  const shape = h('div', { class: 'island-shape', 'aria-hidden': 'true' });
  const lens = h('span', { class: 'island-lens', 'aria-hidden': 'true' });

  // Collapsed live activity: cover on the left, equalizer on the right of the camera.
  const miniArt = h('span', { class: 'mini-art' });
  const eq = () => h('span', { class: 'eq', 'aria-hidden': 'true' }, h('i'), h('i'), h('i'), h('i'));
  const collapsed = h('button', { class: 'island-collapsed', type: 'button', 'aria-expanded': 'false' }, miniArt, eq());

  const peekIcon = h('span', { class: 'peek-icon' });
  const peekTitle = h('span', { class: 'peek-title' });
  const peekDetail = h('span', { class: 'peek-detail' });
  const peek = h('div', { class: 'island-peek', role: 'status', 'aria-live': 'polite' }, peekIcon, h('span', { class: 'peek-text' }, peekTitle, peekDetail));

  const tabsBar = h('div', { class: 'island-tabs', role: 'tablist' });
  const status = h('div', { class: 'island-status' });
  const panes = h('div', { class: 'island-panes' });
  const inner = h('div', { class: 'island-inner' }, h('div', { class: 'island-top' }, tabsBar, status), panes);
  const expanded = h('div', { class: 'island-expanded' }, inner);

  root.append(shape, lens, collapsed, peek, expanded);
  host.append(root);

  // MARK: Player

  let lyricNow, lyricNext, progressFill, timeNow, timeLeft, playButton, titleEl, artistEl, coverSlot, homeEq;

  function renderTrackBits() {
    const track = TRACKS[state.track];
    clear(miniArt).append(coverArt(track, 22));
    if (!titleEl) return;
    titleEl.textContent = track.title;
    artistEl.textContent = track.artist;
    clear(coverSlot).append(coverArt(track, 96), h('span', { class: 'cover-badge', 'aria-hidden': 'true' }, icon('music', 11)));
    updatePlayer();
  }

  function updatePlayer() {
    const track = TRACKS[state.track];
    root.classList.toggle('playing', state.playing);
    if (!titleEl) return;
    const per = track.length / track.lyrics.length;
    const line = Math.min(track.lyrics.length - 1, Math.floor(state.pos / per));
    if (lyricNow.dataset.line !== String(line) || lyricNow.dataset.track !== String(state.track)) {
      lyricNow.dataset.line = String(line);
      lyricNow.dataset.track = String(state.track);
      lyricNow.textContent = track.lyrics[line];
      lyricNext.textContent = track.lyrics[line + 1] || '';
      lyricNow.classList.remove('rise');
      void lyricNow.offsetWidth;
      lyricNow.classList.add('rise');
    }
    progressFill.style.transform = `scaleX(${state.pos / track.length})`;
    timeNow.textContent = fmt(state.pos);
    timeLeft.textContent = `-${fmt(track.length - state.pos)}`;
    clear(playButton).append(icon(state.playing ? 'pause' : 'playFill', 22));
    playButton.setAttribute('aria-label', t(state.playing ? 'pause' : 'play'));
  }

  function skip(dir) {
    state.track = (state.track + dir + TRACKS.length) % TRACKS.length;
    state.pos = 0;
    renderTrackBits();
  }

  setInterval(() => {
    if (!state.playing || document.hidden) return;
    state.pos += 0.5;
    if (state.pos >= TRACKS[state.track].length) skip(1);
    else updatePlayer();
  }, 500);

  // MARK: Timer

  let timerSlot;
  function renderTimer() {
    if (!timerSlot) return;
    clear(timerSlot);
    if (!state.timer) {
      timerSlot.append(h('span', { class: 'timer-icon' }, icon('timer', 16)),
        ...[1, 5, 10, 25].map((m) => h('button', { class: 'chip', type: 'button', onclick: () => startTimer(m), 'aria-label': t('timerMin', m) }, m === 25 ? t('timerMin', 25) : String(m))));
      return;
    }
    const left = Math.max(0, state.timer.end - Date.now()) / 1000;
    const ring = document.createElementNS(SVGNS, 'svg');
    ring.setAttribute('viewBox', '0 0 36 36');
    ring.setAttribute('class', 'timer-ring');
    const frac = left / (state.timer.minutes * 60);
    ring.innerHTML = `<circle cx="18" cy="18" r="15" fill="none" stroke="rgba(255,255,255,.12)" stroke-width="3"/>
      <circle cx="18" cy="18" r="15" fill="none" stroke="#dbc7a3" stroke-width="3" stroke-linecap="round" pathLength="100" stroke-dasharray="${(frac * 100).toFixed(2)} 100" transform="rotate(-90 18 18)"/>`;
    timerSlot.append(ring,
      h('span', { class: 'timer-text' }, h('b', { text: fmt(Math.ceil(left)) }), h('small', { text: t('timerMin', state.timer.minutes) })),
      h('button', { class: 'round', type: 'button', 'aria-label': t('timerAdd'), onclick: () => { state.timer.end += 60000; renderTimer(); } }, icon('plus', 14)),
      h('button', { class: 'round', type: 'button', 'aria-label': t('timerStop'), onclick: () => { state.timer = null; renderTimer(); } }, icon('x', 14)));
  }

  function startTimer(minutes) {
    state.timer = { minutes, end: Date.now() + minutes * 60000 };
    renderTimer();
  }

  setInterval(() => {
    if (!state.timer) return;
    if (Date.now() >= state.timer.end) {
      const minutes = state.timer.minutes;
      state.timer = null;
      renderTimer();
      showPeek('timer', minutes);
    } else if (state.mode === 'expanded' && state.tab === 'home') renderTimer();
  }, 1000);

  // MARK: Panes

  function homePane() {
    coverSlot = h('div', { class: 'cover' });
    titleEl = h('div', { class: 'track-title' });
    artistEl = h('div', { class: 'track-artist' });
    lyricNow = h('div', { class: 'lyric-now' });
    lyricNext = h('div', { class: 'lyric-next' });
    progressFill = h('span');
    timeNow = h('span');
    timeLeft = h('span');
    homeEq = eq();
    playButton = h('button', { class: 'ctrl play', type: 'button', onclick: () => { state.playing = !state.playing; updatePlayer(); } });
    timerSlot = h('div', { class: 'card timer-card' });
    const player = h('div', { class: 'player' },
      coverSlot,
      h('div', { class: 'track' },
        h('div', { class: 'track-head' }, h('div', { class: 'grow' }, titleEl, artistEl), homeEq),
        lyricNow, lyricNext,
        h('div', { class: 'progress' }, progressFill),
        h('div', { class: 'times' }, timeNow, timeLeft),
        h('div', { class: 'controls' },
          h('button', { class: 'ctrl', type: 'button', 'aria-label': t('prevTrack'), onclick: () => skip(-1) }, icon('prev', 20)),
          playButton,
          h('button', { class: 'ctrl', type: 'button', 'aria-label': t('nextTrack'), onclick: () => skip(1) }, icon('next', 20)))));
    const side = h('div', { class: 'home-side' },
      h('div', { class: 'card event-card' }, h('span', { class: 'event-icon' }, icon('calendar', 16)),
        h('span', { class: 'grow' }, h('b', { text: t('eventTitle') }), h('small', { text: t('eventWhen', state.eventMinutes) }))),
      timerSlot);
    const pane = h('div', { class: 'pane home', role: 'tabpanel' }, player, side);
    renderTrackBits();
    renderTimer();
    return pane;
  }

  function agentsPane() {
    const grid = h('div', { class: 'agents' });
    for (const agent of AGENTS) {
      const line = agent.state === 'working' ? t('agentWorking', agent.minutes)
        : agent.state === 'idle' ? t('agentIdle', agent.minutes)
          : agent.state === 'finished' ? t('agentFinished', agent.minutes) : t('agentNone');
      const card = h('div', { class: `agent ${agent.state}` },
        h('div', { class: 'agent-head' },
          h('span', { class: 'agent-glyph' }, agentGlyph(agent.glyph, agent.color)),
          h('span', { class: 'grow' }, h('b', { text: agent.name }), h('small', null, agent.state === 'working' ? h('i', { class: 'live-dot' }) : null, line))),
        agent.project ? h('div', { class: 'agent-project', text: agent.project }) : null,
        agent.usage ? h('div', { class: 'usage' },
          h('div', { class: 'usage-bar' }, h('span', { style: { transform: `scaleX(${agent.usage[2]})` } })),
          h('small', { text: t('agentUsage', ...agent.usage) })) : null);
      grid.append(card);
    }
    return h('div', { class: 'pane agents-pane', role: 'tabpanel' },
      h('div', { class: 'pane-head' }, icon('sparkle', 14), h('span', { text: t('agentsSummary') })), grid);
  }

  function filesPane() {
    const list = h('ul', { class: 'shelf-list' });
    const drop = h('div', { class: 'shelf-drop', tabindex: '0' },
      icon('tray', 22), h('b', { text: t('shelfDrop') }), h('small', { text: t('shelfShake') }));
    const renderShelf = () => {
      clear(list);
      drop.classList.toggle('has-files', state.shelf.length > 0);
      for (const file of state.shelf.slice(-4)) list.append(h('li', null, fileThumb(file.kind), h('span', { class: 'grow' }, h('b', { text: file.name }), h('small', { text: file.size }))));
      if (state.shelf.length) list.append(h('li', { class: 'shelf-note' }, h('small', { text: t('shelfLocal') }), h('button', { class: 'link', type: 'button', text: t('shelfClear'), onclick: () => { state.shelf = []; renderShelf(); } })));
    };
    const human = (bytes) => bytes > 1e6 ? `${(bytes / 1e6).toFixed(1)} MB` : `${Math.max(1, Math.round(bytes / 1e3))} KB`;
    drop.addEventListener('dragover', (event) => { event.preventDefault(); drop.classList.add('over'); });
    drop.addEventListener('dragleave', () => drop.classList.remove('over'));
    drop.addEventListener('drop', (event) => {
      event.preventDefault();
      drop.classList.remove('over');
      const files = [...(event.dataTransfer?.files || [])];
      if (files.length) {
        for (const file of files) state.shelf.push({ name: file.name, size: human(file.size), kind: /image/.test(file.type) ? 'image' : /pdf/.test(file.type) ? 'pdf' : 'doc' });
      } else {
        const name = event.dataTransfer?.getData('text/plain');
        const known = DOWNLOADS.find((d) => d.name() === name);
        if (known) state.shelf.push({ name, size: known.size, kind: known.kind });
      }
      renderShelf();
    });
    renderShelf();
    const downloads = h('ul', { class: 'downloads' });
    for (const item of DOWNLOADS) {
      downloads.append(h('li', { draggable: 'true', ondragstart: (event) => event.dataTransfer.setData('text/plain', item.name()) },
        fileThumb(item.kind), h('span', { class: 'grow' }, h('b', { text: item.name() }), h('small', { text: `${item.size} · ${t(...item.when)}` }))));
    }
    return h('div', { class: 'pane files', role: 'tabpanel' },
      h('div', { class: 'files-col' }, h('div', { class: 'pane-head', text: t('shelf') }), drop, list),
      h('div', { class: 'files-col' }, h('div', { class: 'pane-head', text: t('downloads') }), downloads));
  }

  function stopCamera() {
    state.cameraStream?.getTracks().forEach((track) => track.stop());
    state.cameraStream = null;
  }

  function cameraPane() {
    const mirror = h('div', { class: 'mirror' }, icon('video', 22));
    const note = h('small', { text: t('cameraNote') });
    const button = h('button', { class: 'pill-button', type: 'button' }, t('cameraOn'));
    const render = () => {
      clear(mirror);
      if (state.cameraStream) {
        const video = h('video', { autoplay: true, muted: true, playsinline: true });
        video.srcObject = state.cameraStream;
        mirror.append(video);
        button.textContent = t('cameraOff');
      } else {
        mirror.append(icon('video', 22));
        button.textContent = t('cameraOn');
      }
    };
    button.addEventListener('click', async () => {
      if (state.cameraStream) { stopCamera(); render(); return; }
      try {
        state.cameraStream = await navigator.mediaDevices.getUserMedia({ video: { width: 640, height: 360 }, audio: false });
      } catch {
        note.textContent = t('cameraError');
      }
      render();
    });
    render();
    return h('div', { class: 'pane camera', role: 'tabpanel' }, mirror,
      h('div', { class: 'camera-copy' }, h('b', { text: t('cameraTitle') }), note, button));
  }

  const PANES = { home: homePane, agents: agentsPane, files: filesPane, camera: cameraPane };
  const TAB_ICONS = { home: 'home', agents: 'sparkle', files: 'tray', camera: 'video' };
  const TAB_LABELS = { home: 'tabHome', agents: 'tabAgents', files: 'tabFiles', camera: 'tabCamera' };

  function renderTop() {
    clear(tabsBar);
    for (const id of Object.keys(PANES)) {
      const active = id === state.tab;
      tabsBar.append(h('button', {
        class: `island-tab${active ? ' active' : ''}`, type: 'button', role: 'tab', 'aria-selected': String(active), 'aria-label': t(TAB_LABELS[id]),
        onclick: () => setTab(id)
      }, icon(TAB_ICONS[id], 14), active ? h('span', { text: t(TAB_LABELS[id]) }) : null));
    }
    clear(status).append(
      h('span', { class: 'battery' }, icon('battery', 18), h('span', { text: '82%' })),
      h('button', { class: `icon-button${state.pinned ? ' on' : ''}`, type: 'button', 'aria-label': t('islandPin'), 'aria-pressed': String(state.pinned), onclick: () => { state.pinned = !state.pinned; renderTop(); } }, icon('pin', 15)),
      h('button', { class: 'icon-button', type: 'button', 'aria-label': t('islandSettings'), onclick: () => bus.emit('panel', 'settings') }, icon('gear', 15)));
  }

  function renderPane() {
    if (state.tab !== 'camera') stopCamera();
    titleEl = null;
    timerSlot = null;
    const pane = PANES[state.tab]();
    panes.replaceChildren(pane);
    root.style.setProperty('--expanded-h', `${HEIGHTS[state.tab]}px`);
    measure();
  }

  // The open height follows the content, so translations and narrow screens never clip it.
  function measure() {
    requestAnimationFrame(() => { if (inner.offsetHeight) root.style.setProperty('--expanded-h', `${Math.ceil(inner.offsetHeight)}px`); });
  }
  addEventListener('resize', measure);

  function setTab(tab) {
    if (!PANES[tab]) return;
    state.tab = tab;
    root.dataset.tab = tab;
    renderTop();
    renderPane();
  }

  // MARK: Modes

  function setMode(mode) {
    state.mode = mode;
    root.dataset.mode = mode;
    collapsed.setAttribute('aria-expanded', String(mode === 'expanded'));
    if (mode !== 'expanded') stopCamera();
    bus.emit('island-mode', mode);
  }

  function expand(tab) {
    clearTimeout(state.peekTimer);
    if (tab && tab !== state.tab) setTab(tab);
    else if (!panes.firstChild) renderPane();
    setMode('expanded');
  }

  function collapse() {
    if (state.pinned) return;
    setMode('collapsed');
  }

  function showPeek(kind, ...args) {
    if (state.mode === 'expanded' && kind !== 'copied') return;
    const [key, glyph, tone] = PEEKS[kind] || PEEKS.agent;
    const [title, detail] = t(key);
    peekTitle.textContent = title.replace(/\{(\d+)\}/g, (_, i) => args[Number(i)] ?? '');
    peekDetail.textContent = detail.replace(/\{(\d+)\}/g, (_, i) => args[Number(i)] ?? '');
    peekIcon.className = `peek-icon ${tone}`;
    clear(peekIcon).append(icon(glyph, 15));
    if (state.mode === 'expanded') return;
    setMode('peek');
    clearTimeout(state.peekTimer);
    state.peekTimer = setTimeout(() => { if (state.mode === 'peek') setMode('collapsed'); }, 3200);
  }

  const touch = coarsePointer();
  root.addEventListener('pointerenter', (event) => {
    if (event.pointerType === 'touch') return;
    state.hovering = true;
    clearTimeout(state.leaveTimer);
    clearTimeout(state.enterTimer);
    if (state.mode !== 'expanded') state.enterTimer = setTimeout(() => { expand(); bus.emit('island-touched'); }, 90);
  });
  root.addEventListener('pointerleave', (event) => {
    if (event.pointerType === 'touch') return;
    state.hovering = false;
    clearTimeout(state.enterTimer);
    state.leaveTimer = setTimeout(() => { if (!state.hovering) collapse(); }, 520);
  });
  collapsed.addEventListener('click', () => { if (state.mode === 'expanded') collapse(); else { expand(); bus.emit('island-touched'); } });
  root.addEventListener('keydown', (event) => {
    if (event.key === 'Escape' && state.mode === 'expanded') { state.pinned = false; collapse(); collapsed.focus(); }
  });
  document.addEventListener('pointerdown', (event) => {
    if (state.mode === 'expanded' && !root.contains(event.target) && (touch || !state.hovering)) collapse();
  });

  // Ambient events, the way the real island pushes itself open for a moment.
  const AMBIENT = [['agent'], ['charging'], ['meeting'], ['headphones'], ['download', CONFIG.version]];
  let ambient = 0;
  setInterval(() => {
    if (document.hidden || state.mode !== 'collapsed' || state.hovering || !state.introDone) return;
    if (root.getBoundingClientRect().bottom < 0) return;
    const [kind, ...args] = AMBIENT[ambient++ % AMBIENT.length];
    showPeek(kind, ...args);
  }, 17000);

  bus.on('peek', showPeek);

  // The first-load moment: the pill wakes, opens on Home for a beat, then settles.
  function intro() {
    renderTop();
    renderPane();
    if (reducedMotion()) { state.introDone = true; return; }
    setTimeout(() => { if (!state.hovering) expand('home'); }, 1100);
    setTimeout(() => { if (!state.hovering && !state.pinned) collapse(); state.introDone = true; }, 5200);
  }

  onLang(() => { renderTop(); if (state.mode === 'expanded' || panes.firstChild) renderPane(); });

  renderTrackBits();
  intro();
  return { root, expand, collapse, peek: showPeek, setTab, get mode() { return state.mode; } };
}
