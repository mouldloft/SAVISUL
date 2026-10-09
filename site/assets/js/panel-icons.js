// SF Symbols stand-ins for the SAVISUL panel, drawn on a 24×24 grid at semibold weight.
// Parts: ['p', d, mode, transform?], ['c', cx, cy, r, mode], ['r', x, y, w, h, rx, mode, dash?]; mode 's' strokes, 'f' fills.
const NS = 'http://www.w3.org/2000/svg';

function gear(teeth = 8, outer = 9.6, inner = 7.4) {
  const step = (Math.PI * 2) / teeth;
  const pts = [];
  for (let i = 0; i < teeth; i++) {
    const a = i * step - Math.PI / 2;
    for (const [da, r] of [[-0.36, inner], [-0.2, outer], [0.2, outer], [0.36, inner]]) {
      const t = a + da * step;
      pts.push(`${(12 + Math.cos(t) * r).toFixed(2)} ${(12 + Math.sin(t) * r).toFixed(2)}`);
    }
  }
  return `M${pts.join('L')}Z`;
}
const roundRect = (x, y, w, h, r) => `M${x + r} ${y}h${w - 2 * r}a${r} ${r} 0 0 1 ${r} ${r}v${h - 2 * r}a${r} ${r} 0 0 1-${r} ${r}h-${w - 2 * r}a${r} ${r} 0 0 1-${r}-${r}v-${h - 2 * r}a${r} ${r} 0 0 1 ${r}-${r}Z`;
const hole = (cx, cy, r) => `M${cx - r} ${cy}a${r} ${r} 0 1 0 ${2 * r} 0a${r} ${r} 0 1 0-${2 * r} 0Z`;

const SPEAKER = 'M3.6 9.3h3.2l4.6-4v13.4l-4.6-4H3.6Z';
const MIC = [9, 2.8, 6, 11, 3];
const CPU_PINS = 'M9.5 3.5v3M14.5 3.5v3M9.5 17.5v3M14.5 17.5v3M3.5 9.5h3M3.5 14.5h3M17.5 9.5h3M17.5 14.5h3';
const BOLT = 'M13.3 2.8 5.2 13.4h6.1l-1 7.8 8.5-11.1h-6.2l.7-7.3Z';
const BLADE = 'M12 10.2C10.8 6.2 12.3 3.4 14.9 3.7c2.2.3 2 3.6-1.6 6.8';
// A four-point sparkle whose sides curve in through the centre, like SF Symbols' stars.
const star = (x, y, r) => `M${x} ${y - r}Q${x} ${y} ${x + r} ${y}Q${x} ${y} ${x} ${y + r}Q${x} ${y} ${x - r} ${y}Q${x} ${y} ${x} ${y - r}Z`;
const WAND_STARS = `${star(17.2, 5.2, 3.2)}${star(20.4, 12.2, 1.9)}${star(10.6, 4.4, 1.7)}`;

const SYMBOLS = {
  bolt: [['p', BOLT, 's']],
  boltFill: [['p', BOLT, 'f']],
  speaker: [['p', SPEAKER, 's'], ['p', 'M15.2 9.2a4 4 0 0 1 0 5.6M18 6.6a7.6 7.6 0 0 1 0 10.8', 's']],
  speakerFill: [['p', SPEAKER, 'f'], ['p', 'M15.2 9.2a4 4 0 0 1 0 5.6M18 6.6a7.6 7.6 0 0 1 0 10.8', 's']],
  speakerSlash: [['p', SPEAKER, 'f'], ['p', 'M15.5 9.5l5 5M20.5 9.5l-5 5', 's']],
  speakerZzz: [['p', SPEAKER, 's'], ['p', 'M15 8h3.2l-3.2 3.6h3.2M18.6 13.6h2.4l-2.4 2.8H21', 's']],
  cpu: [['r', 6.5, 6.5, 11, 11, 2.2, 's'], ['r', 9.6, 9.6, 4.8, 4.8, 0.8, 's'], ['p', CPU_PINS, 's']],
  cpuFill: [['p', `${roundRect(6, 6, 12, 12, 2.4)}${roundRect(9.6, 9.6, 4.8, 4.8, 0.8)}`, 'e'], ['p', CPU_PINS, 's']],
  code: [['p', 'M8.2 6.8 3.6 12l4.6 5.2M15.8 6.8 20.4 12l-4.6 5.2M13.6 4.8l-3.2 14.4', 's']],
  grid: [['r', 3.6, 3.6, 7, 7, 1.8, 's'], ['r', 13.4, 3.6, 7, 7, 1.8, 's'], ['r', 3.6, 13.4, 7, 7, 1.8, 's'], ['r', 13.4, 13.4, 7, 7, 1.8, 's']],
  gridFill: [['r', 3.2, 3.2, 7.6, 7.6, 2, 'f'], ['r', 13.2, 3.2, 7.6, 7.6, 2, 'f'], ['r', 3.2, 13.2, 7.6, 7.6, 2, 'f'], ['r', 13.2, 13.2, 7.6, 7.6, 2, 'f']],
  gear: [['p', gear(), 's'], ['c', 12, 12, 3.1, 's']],
  gearFill: [['p', `${gear(8, 10, 7.8)}${hole(12, 12, 3)}`, 'e']],
  ellipsis: [['c', 5.5, 12, 1.7, 'f'], ['c', 12, 12, 1.7, 'f'], ['c', 18.5, 12, 1.7, 'f']],
  laptop: [['p', 'M6 5.5h12a1 1 0 0 1 1 1V15H5V6.5a1 1 0 0 1 1-1Z', 's'], ['p', 'M2.6 17.8h18.8', 's']],
  moon: [['p', 'M19.6 14.6A8 8 0 0 1 9.4 4.4a8 8 0 1 0 10.2 10.2Z', 's']],
  moonFill: [['p', 'M19.6 14.6A8 8 0 0 1 9.4 4.4a8 8 0 1 0 10.2 10.2Z', 'f']],
  moonZzz: [['p', 'M16.8 15.8A7 7 0 0 1 7.7 6.7a7 7 0 1 0 9.1 9.1Z', 's'], ['p', 'M14.5 3.4h3l-3 3.4h3M18.8 7.8h2.4l-2.4 2.7h2.4', 's']],
  cup: [['p', 'M5.5 8.5h11v3.8a5.5 5.5 0 0 1-11 0Z', 's'], ['p', 'M16.5 10h1.3a2.2 2.2 0 0 1 0 4.4h-1.6M3.5 20h16', 's']],
  sun: [['c', 12, 12, 3.6, 's'], ['p', 'M12 2.8v2.4M12 18.8v2.4M2.8 12h2.4M18.8 12h2.4M5.5 5.5l1.7 1.7M16.8 16.8l1.7 1.7M5.5 18.5l1.7-1.7M16.8 7.2l1.7-1.7', 's']],
  chevronRight: [['p', 'M9.5 5.5 16 12l-6.5 6.5', 's']],
  chevronDown: [['p', 'M5.5 9.5 12 16l6.5-6.5', 's']],
  chevronUp: [['p', 'M5.5 14.5 12 8l6.5 6.5', 's']],
  battery: [['r', 2.5, 7.5, 17, 9, 2.6, 's'], ['r', 4.6, 9.6, 9.6, 4.8, 1.1, 'f'], ['p', 'M21.4 10.6v2.8', 's']],
  batteryBolt: [['r', 2.5, 7.5, 17, 9, 2.6, 's'], ['p', 'M12.2 8.8 8.4 12.6h2.8l-.8 2.6 3.8-3.8h-2.8Z', 'f'], ['p', 'M21.4 10.6v2.8', 's']],
  mic: [['r', ...MIC, 's'], ['p', 'M5.8 11.2a6.2 6.2 0 0 0 12.4 0M12 17.4v3.2', 's']],
  micFill: [['r', ...MIC, 'f'], ['p', 'M5.8 11.2a6.2 6.2 0 0 0 12.4 0M12 17.4v3.2', 's']],
  micSlash: [['r', ...MIC, 'f'], ['p', 'M5.8 11.2a6.2 6.2 0 0 0 12.4 0M12 17.4v3.2M3.5 3.5l17 17', 's']],
  waveform: [['p', 'M4 10v4M8 7v10M12 4v16M16 8v8M20 10.5v3', 's']],
  swap: [['p', 'M7 4.5v13M3.5 14 7 17.5l3.5-3.5M17 19.5v-13M13.5 10 17 6.5l3.5 3.5', 's']],
  memory: [['r', 3.5, 7, 17, 10, 2, 's'], ['p', 'M8 10.5v3M12 10.5v3M16 10.5v3M6.5 17v2.5M10 17v2.5M14 17v2.5M17.5 17v2.5', 's']],
  thermometer: [['p', 'M10 13.7V5.5a2 2 0 0 1 4 0v8.2a4 4 0 1 1-4 0Z', 's'], ['p', 'M12 10v6', 's'], ['c', 12, 17.2, 1.6, 'f']],
  fan: [['c', 12, 12, 1.8, 'f'], ['p', BLADE, 's'], ['p', BLADE, 's', 'rotate(120 12 12)'], ['p', BLADE, 's', 'rotate(240 12 12)']],
  dashedRect: [['r', 3.5, 5.5, 17, 13, 2.5, 's', '2.6 2.4']],
  window: [['r', 3.5, 4.5, 17, 15, 2.5, 's'], ['p', 'M3.5 9h17', 's'], ['c', 6.4, 6.8, 0.7, 'f'], ['c', 8.6, 6.8, 0.7, 'f']],
  display: [['r', 2.8, 4, 18.4, 12.4, 2, 's'], ['p', 'M9 20.2h6M12 16.4v3.8', 's']],
  record: [['c', 12, 12, 8.6, 's'], ['c', 12, 12, 4.3, 'f']],
  stop: [['r', 7, 7, 10, 10, 2.4, 'f']],
  viewfinder: [['p', 'M4 8.5V6a2 2 0 0 1 2-2h2.5M15.5 4H18a2 2 0 0 1 2 2v2.5M20 15.5V18a2 2 0 0 1-2 2h-2.5M8.5 20H6a2 2 0 0 1-2-2v-2.5', 's'], ['p', 'M8 9.8h1.6l.9-1.3h3l.9 1.3H16v5.8H8Z', 's'], ['c', 12, 12.7, 1.5, 's']],
  menubar: [['r', 3, 5, 18, 14, 3, 's'], ['p', 'M3 9.5h18', 's']],
  folder: [['p', 'M3.5 7A1.5 1.5 0 0 1 5 5.5h4l2 2h8A1.5 1.5 0 0 1 20.5 9v8.5A1.5 1.5 0 0 1 19 19H5a1.5 1.5 0 0 1-1.5-1.5Z', 's']],
  puzzle: [['p', 'M4.5 8h3.6a2.1 2.1 0 1 1 4 0h3.6v3.6a2.1 2.1 0 1 1 0 4V19H4.5v-3.4a2.1 2.1 0 1 0 0-4Z', 's']],
  bell: [['p', 'M6.5 16.5V11a5.5 5.5 0 0 1 9.2-4.1M17.5 10.8v5.7l1.5 1H5l1.5-1M10 19.8a2 2 0 0 0 4 0', 's'], ['c', 18, 6, 2.3, 'f']],
  flag: [['p', 'M5.5 20.5V4M5.5 4.5h13l-2.4 4 2.4 4h-13', 's'], ['p', 'M9.5 4.5v8M13.5 4.5v8M5.5 8.5h11', 's']],
  paperplane: [['p', 'M3.4 11.4 20.6 3.9 13.1 21.1l-2.3-7.4Z', 'f']],
  plus: [['p', 'M12 5v14M5 12h14', 's']],
  xmark: [['p', 'M6.5 6.5l11 11M17.5 6.5l-11 11', 's']],
  network: [['c', 12, 12, 8.6, 's'], ['p', 'M3.4 12h17.2M12 3.4c2.4 2.4 3.5 5.3 3.5 8.6s-1.1 6.2-3.5 8.6c-2.4-2.4-3.5-5.3-3.5-8.6S9.6 5.8 12 3.4Z', 's']],
  eye: [['p', 'M2.5 12C4.5 7.8 8 5.5 12 5.5s7.5 2.3 9.5 6.5c-2 4.2-5.5 6.5-9.5 6.5S4.5 16.2 2.5 12Z', 's'], ['c', 12, 12, 3, 's']],
  power: [['p', 'M12 3.5v8M7.2 6.3a7 7 0 1 0 9.6 0', 's']],
  dock: [['r', 3, 4.5, 18, 15, 3, 's'], ['p', 'M6.8 16h10.4', 's']],
  pin: [['p', 'M9 3.5h6l-.8 5.6 2.8 3.4H7l2.8-3.4Z', 's'], ['p', 'M12 12.5v8', 's']],
  pinFill: [['p', 'M9 3.5h6l-.8 5.6 2.8 3.4H7l2.8-3.4Z', 'f'], ['p', 'M12 12.5v8', 's']],
  command: [['p', 'M9 9V6.5A2.5 2.5 0 1 0 6.5 9H9Zm0 0v6m0-6h6m-6 6H6.5A2.5 2.5 0 1 0 9 17.5V15Zm0 0h6m0 0v2.5a2.5 2.5 0 1 0 2.5-2.5H15Zm0 0V9m0 0h2.5A2.5 2.5 0 1 0 15 6.5V9Z', 's']],
  keyboard: [['r', 2.5, 6, 19, 12, 2.5, 's'], ['p', 'M6.5 9.8h.01M9.8 9.8h.01M13.2 9.8h.01M16.5 9.8h.01M7.5 14.2h9', 's']],
  screenRecord: [['r', 3, 5, 14.5, 11.5, 2.2, 's', '2.4 2.2'], ['c', 17.6, 16.6, 3.3, 'f']],
  lockShield: [['p', 'M12 3 5 5.8v5.4c0 4.4 2.9 8 7 9.8 4.1-1.8 7-5.4 7-9.8V5.8Z', 's'], ['r', 9.4, 11.2, 5.2, 4.2, 0.8, 'f'], ['p', 'M10.4 11.2V10a1.6 1.6 0 0 1 3.2 0v1.2', 's']],
  check: [['p', 'M5 12.5l4.5 4.5L19 7.5', 's']],
  copy: [['r', 8, 8, 12, 12, 2.5, 's'], ['p', 'M16 8V6.5A2.5 2.5 0 0 0 13.5 4h-7A2.5 2.5 0 0 0 4 6.5v7A2.5 2.5 0 0 0 6.5 16H8', 's']],
  ecg: [['p', 'M3 12h4l2-5 3.5 10 2.5-7 1.5 2H21', 's']],
  terminal: [['r', 3, 4.5, 18, 15, 2.5, 's'], ['p', 'M7 9.5l3 2.5-3 2.5M12.5 14.5H17', 's']],
  drive: [['r', 3, 8, 18, 8, 2.2, 's'], ['c', 16.6, 12, 1, 'f'], ['p', 'M6.5 12h5', 's']],
  headphones: [['p', 'M4 15v-3a8 8 0 0 1 16 0v3', 's'], ['r', 3.5, 14, 4, 6, 1.5, 's'], ['r', 16.5, 14, 4, 6, 1.5, 's']],
  compass: [['c', 12, 12, 8.6, 's'], ['p', 'M15.6 8.4 13.2 13.2 8.4 15.6l2.4-4.8Z', 'f']],
  note: [['p', 'M9 18V6.5l10-2.2V16', 's'], ['c', 6.6, 18, 2.4, 'f'], ['c', 16.6, 16, 2.4, 'f']],
  video: [['r', 3, 7, 12.5, 10, 2.4, 'f'], ['p', 'M16 11 21 8v8l-5-3Z', 'f']],
  cube: [['p', 'M12 3 20 7.5v9L12 21l-8-4.5v-9Z', 's'], ['p', 'M4 7.5 12 12l8-4.5M12 12v9', 's']],
  chat: [['p', 'M5 5.5h14a1.5 1.5 0 0 1 1.5 1.5v8.5A1.5 1.5 0 0 1 19 17h-8l-4.5 3.5V17H5a1.5 1.5 0 0 1-1.5-1.5V7A1.5 1.5 0 0 1 5 5.5Z', 's']],
  appDashed: [['r', 4, 4, 16, 16, 4.4, 's', '2.4 2.2']],
  arrowSwap: [['p', 'M4 8h13l-3.5-3.5M20 16H7l3.5 3.5', 's']],
  wand: [['p', 'M4.6 19.4 14.2 9.8', 's'], ['p', WAND_STARS, 'f']],
  wandFill: [['p', 'M3.4 18.6 13.4 8.6l2 2-10 10Z', 'f'], ['p', 'M4.4 19.6 14.4 9.6', 's'], ['p', WAND_STARS, 'f']],
  sparkles: [['p', `${star(10, 13.4, 6.6)}${star(18, 5.6, 2.9)}${star(18.4, 17.8, 2.1)}`, 'f']],
  capsule: [['r', 2.6, 6.8, 18.8, 10.4, 5.2, 's'], ['r', 5.8, 10, 12.4, 4, 2, 'f']],
  clipboard: [['r', 5, 4.6, 14, 16.4, 2.6, 's'], ['r', 8.6, 2.8, 6.8, 3.8, 1.4, 'f'], ['p', 'M8.6 11.2h6.8M8.6 15.2h4.6', 's']],
  search: [['c', 10.4, 10.4, 6.2, 's'], ['p', 'M15 15l5.2 5.2', 's']],
  flow: [['c', 6, 17.5, 2.3, 'f'], ['c', 18, 17.5, 2.3, 'f'], ['c', 12, 6, 2.3, 'f'], ['p', 'M7.4 15.4 10.7 8.2M13.3 8.2l3.3 7.2M8.6 17.5h6.8', 's', null]],
  play: [['p', 'M8.5 5.6v12.8l10-6.4Z', 'f']],
  pencil: [['p', 'M4.5 19.5l1-4L15.8 5.2a1.8 1.8 0 0 1 2.6 0l.4.4a1.8 1.8 0 0 1 0 2.6L8.5 18.5Z', 's'], ['p', 'M14 7l3 3', 's']],
  page: [['p', 'M6.5 3.5h7l4 4v13h-11Z', 's'], ['p', 'M13.5 3.5v4h4', 's']]
};

export function sym(name, size = 16, extraClass = '') {
  const svg = document.createElementNS(NS, 'svg');
  svg.setAttribute('viewBox', '0 0 24 24');
  svg.setAttribute('width', size);
  svg.setAttribute('height', size);
  svg.setAttribute('aria-hidden', 'true');
  svg.setAttribute('class', `sym ${extraClass}`.trim());
  for (const part of SYMBOLS[name] || SYMBOLS.appDashed) {
    const [kind] = part;
    let node;
    let mode;
    if (kind === 'p') {
      node = document.createElementNS(NS, 'path');
      node.setAttribute('d', part[1]);
      mode = part[2];
      if (part[3]) node.setAttribute('transform', part[3]);
    } else if (kind === 'c') {
      node = document.createElementNS(NS, 'circle');
      node.setAttribute('cx', part[1]); node.setAttribute('cy', part[2]); node.setAttribute('r', part[3]);
      mode = part[4];
    } else {
      node = document.createElementNS(NS, 'rect');
      ['x', 'y', 'width', 'height', 'rx'].forEach((a, i) => node.setAttribute(a, part[i + 1]));
      mode = part[6];
      if (part[7]) node.setAttribute('stroke-dasharray', part[7]);
    }
    if (mode === 's') {
      node.setAttribute('fill', 'none');
      node.setAttribute('stroke', 'currentColor');
      node.setAttribute('stroke-width', '2');
      node.setAttribute('stroke-linecap', 'round');
      node.setAttribute('stroke-linejoin', 'round');
    } else {
      node.setAttribute('fill', 'currentColor');
      if (mode === 'e') node.setAttribute('fill-rule', 'evenodd');
    }
    svg.append(node);
  }
  return svg;
}

// macOS-style app tiles for the sample apps. Neutral glyphs, never third-party logos.
const TILES = {
  cursor: ['linear-gradient(160deg, #3a3a3c, #0d0d0e)', '#f2f2f2', 'cube'],
  vscode: ['linear-gradient(160deg, #ffffff, #e6eaf0)', '#2b7fd1', 'code'],
  chatgpt: ['linear-gradient(160deg, #ffffff, #e9e9ea)', '#1f1f1f', 'chat'],
  claude: ['linear-gradient(160deg, #e3956f, #c45f3d)', '#fff7f0', 'chat'],
  chrome: ['linear-gradient(160deg, #ffffff, #e8ebee)', '#3a7bd5', 'network'],
  telegram: ['linear-gradient(160deg, #3fb1ea, #1c87c9)', '#ffffff', 'paperplane'],
  finder: ['linear-gradient(160deg, #8fd0ff, #2d7fe0)', '#ffffff', 'folder'],
  safari: ['linear-gradient(160deg, #ffffff, #e5eaf0)', '#2c86e8', 'compass'],
  music: ['linear-gradient(160deg, #ff6b7f, #f23a54)', '#ffffff', 'note'],
  facetime: ['linear-gradient(160deg, #5fe07a, #22b14c)', '#ffffff', 'video']
};

export function appTile(kind, size = 28) {
  const el = document.createElement('span');
  el.className = 'app-tile';
  el.style.width = `${size}px`;
  el.style.height = `${size}px`;
  if (kind === 'savisul') {
    const img = document.createElement('img');
    img.src = 'assets/img/icon-256.webp';
    img.alt = '';
    img.width = size;
    img.height = size;
    el.append(img);
    el.classList.add('image');
    return el;
  }
  const [bg, color, glyph] = TILES[kind] || TILES.cursor;
  el.style.background = bg;
  el.style.color = color;
  el.append(sym(glyph, Math.round(size * 0.58)));
  return el;
}
