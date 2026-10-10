// Stroke icons on a 24×24 grid, shared grammar with the SAVISUL extension: "c" circle, "r" rect, everything else a path.
const ICONS = {
  "moon": "M20 14.5A8 8 0 0 1 9.5 4a8 8 0 1 0 10.5 10.5Z",
  "sun": "c12 12 4|M12 2.5v2M12 19.5v2M4.6 4.6 6 6M18 18l1.4 1.4M2.5 12h2M19.5 12h2M4.6 19.4 6 18M18 6l1.4-1.4",
  "book": "M12 7.5C10.3 5.9 7.7 5.2 4 5.3v12.9c3.7-.1 6.3.6 8 2.3 1.7-1.7 4.3-2.4 8-2.3V5.3c-3.7-.1-6.3.6-8 2.2Z|M12 7.5v13",
  "pipette": "M14 6.5 17.5 10|M15.3 5.2l2.3-2.3a2.2 2.2 0 0 1 3.1 3.1l-2.3 2.3|M14 7l3 3-8.6 8.6a2 2 0 0 1-1.4.6H5v-2c0-.5.2-1 .6-1.4Z",
  "ruler": "M3.5 16.5 16.5 3.5l4 4-13 13Z|M7.5 12.5l2 2M10.5 9.5l2 2M13.5 6.5l2 2",
  "note": "M5 4.5h14v9.5l-5.5 5.5H5Z|M13.5 19.5V14H19|M8.5 8.5h7M8.5 11.5h4",
  "camera": "M4 8.5h3.2l1.6-2.5h6.4l1.6 2.5H20v10.5H4Z|c12 13.3 3.4",
  "eyeOff": "M3 3l18 18|M10.6 5.1C11 5 11.5 5 12 5c5 0 8.5 4.5 9.5 7-.6 1.4-1.4 2.7-2.6 3.8|M6.6 6.6C4.6 8 3.2 10 2.5 12c1 2.5 4.5 7 9.5 7 1.8 0 3.4-.5 4.8-1.3|M9.9 9.9a3 3 0 0 0 4.2 4.2",
  "type": "M5 7V5h14v2|M12 5v14|M9 19h6",
  "link": "M10 14a4.5 4.5 0 0 0 6.4 0l3-3a4.5 4.5 0 0 0-6.4-6.4l-1 1|M14 10a4.5 4.5 0 0 0-6.4 0l-3 3a4.5 4.5 0 0 0 6.4 6.4l1-1",
  "play": "r3 5 18 14 3.5|M10.2 9.3v5.4l4.6-2.7Z",
  "image": "r3 4 18 16 3.5|c9 10 1.8|M21 15.5 16 11l-9 9",
  "unlock": "r4.5 11 15 10 2.5|M8 11V7.5a4 4 0 0 1 7.7-1.6",
  "pencil": "M4 20h4L19 9a2.8 2.8 0 0 0-4-4L4 16Z|M13.5 6.5l4 4",
  "outline": "M4 8V5.5A1.5 1.5 0 0 1 5.5 4H8M16 4h2.5A1.5 1.5 0 0 1 20 5.5V8M20 16v2.5a1.5 1.5 0 0 1-1.5 1.5H16M8 20H5.5A1.5 1.5 0 0 1 4 18.5V16|M10.5 4h3M10.5 20h3M4 10.5v3M20 10.5v3",
  "sliders": "M4 7h9M17 7h3M4 17h3M11 17h9|c15 7 2|c9 17 2",
  "x": "M6.5 6.5l11 11M17.5 6.5l-11 11",
  "back": "M14.5 5.5 8 12l6.5 6.5",
  "check": "M5 12.5l4.5 4.5L19 7.5",
  "copy": "r8 8 12 12 2.5|M16 8V6.5A2.5 2.5 0 0 0 13.5 4h-7A2.5 2.5 0 0 0 4 6.5v7A2.5 2.5 0 0 0 6.5 16H8",
  "download": "M12 4v11|M7 10.5l5 5 5-5|M5 20h14",
  "trash": "M4.5 7h15|M10 11v6M14 11v6|M6.5 7l.8 12.1A1.5 1.5 0 0 0 8.8 20.5h6.4a1.5 1.5 0 0 0 1.5-1.4L17.5 7|M9 7V4.5h6V7",
  "pin": "M9 4h6l-.8 5.5L17 13H7l2.8-3.5Z|M12 13v7",
  "external": "M14 4h6v6|M20 4l-9 9|M18 14v4.5a1.5 1.5 0 0 1-1.5 1.5h-11A1.5 1.5 0 0 1 4 18.5v-11A1.5 1.5 0 0 1 5.5 6H10",
  "laptop": "r5 5 14 10 1.8|M2.5 19h19",
  "coffee": "M5 9h11v4.5a5.5 5.5 0 0 1-11 0Z|M16 10.5h1.5a2.5 2.5 0 0 1 0 5H16|M9 3.5V6M12.5 3.5V6",
  "displayOff": "r3 4 18 12 2|M9 20h6M12 16v4|M14.6 7.6a2.8 2.8 0 1 0 1.8 4.8 2.4 2.4 0 0 1-1.8-4.8Z",
  "speaker": "M4 9.5h3.5L12 5.5v13l-4.5-4H4Z|M15.5 9.2a4 4 0 0 1 0 5.6M18.2 6.8a7.5 7.5 0 0 1 0 10.4",
  "speakerOff": "M4 9.5h3.5L12 5.5v13l-4.5-4H4Z|M16 9.5l5 5M21 9.5l-5 5",
  "battery": "r2.5 7.5 17 9 2.5|M21.5 10.5v3",
  "bolt": "M13 3 5.5 13.5H12L11 21l7.5-10.5H12Z",
  "cpu": "r6 6 12 12 2|r9.5 9.5 5 5 .8|M9 3v3M15 3v3M9 18v3M15 18v3M3 9h3M3 15h3M18 9h3M18 15h3",
  "folder": "M3.5 7A1.5 1.5 0 0 1 5 5.5h4l2 2h8A1.5 1.5 0 0 1 20.5 9v8.5A1.5 1.5 0 0 1 19 19H5a1.5 1.5 0 0 1-1.5-1.5Z",
  "qr": "r4 4 6 6 1|r14 4 6 6 1|r4 14 6 6 1|M14 14h2.5v2.5H14ZM17.5 17.5H20V20h-2.5ZM14 20h1M20 14h-1",
  "globe": "c12 12 8.5|M3.5 12h17|M12 3.5c2.4 2.6 3.5 5.4 3.5 8.5s-1.1 5.9-3.5 8.5c-2.4-2.6-3.5-5.4-3.5-8.5s1.1-5.9 3.5-8.5Z",
  "page": "M6 3.5h8l4 4v13H6Z|M14 3.5v4h4|M9 12h6M9 15.5h6",
  "crop": "M7 3v14h14|M3 7h14v14",
  "screen": "r3 4.5 18 12.5 2|M8.5 20.5h7",
  "minus": "M5.5 12h13",
  "plus": "M12 5.5v13M5.5 12h13",
  "pip": "r3 5 18 14 2.5|r12 11.5 6.5 5 1",
  "loop": "M17 3.5l3 3-3 3|M4 12v-.5A5 5 0 0 1 9 6.5h11|M7 20.5l-3-3 3-3|M20 12v.5a5 5 0 0 1-5 5H4",
  "keyboard": "r2.5 6 19 12 2.5|M6.5 10h.01M10 10h.01M13.5 10h.01M17 10h.01M7 14h10",
  "search": "c11 11 6.5|M16 16l4 4",
  "sparkle": "M12 3.5l1.9 5.1 5.1 1.9-5.1 1.9L12 17.5l-1.9-5.1L5 10.5l5.1-1.9Z",
  "width": "M4 12h16|M7.5 8.5 4 12l3.5 3.5|M16.5 8.5 20 12l-3.5 3.5",
  "lines": "M5 6.5h14M5 10.5h14M5 14.5h9M5 18.5h11",
  "restore": "M4.5 12a7.5 7.5 0 1 0 2.2-5.3|M4.5 4.5v4h4",
  "pause": "M9 6v12|M15 6v12",
  "stop": "r6.5 6.5 11 11 2.5",
  "wave": "M4 12h1.5|M8 8v8|M11.5 5v14|M15 9v6|M18.5 11v2",
  "sidebar": "r3 4 18 16 2.5|M14.5 4v16|M17 8.5h1M17 11.5h1",
  "tabs": "r3 8 18 12 2.5|M6 8V5.5A1.5 1.5 0 0 1 7.5 4h4A1.5 1.5 0 0 1 13 5.5V8",
  "table": "r3.5 4.5 17 15 2.5|M3.5 9.5h17|M3.5 14.5h17|M9.5 9.5v10",
  "translate": "M4 5.5h9|M8.5 4v1.5|M11 5.5c-.8 3.6-3.3 6.4-6.5 8|M6.5 8.6c1.2 2 3 3.6 5 4.4|M13 20l3.8-9 3.7 9|M14.2 17.3h5",
  "inspect": "M4 9V5.5A1.5 1.5 0 0 1 5.5 4H9|M15 4h3.5A1.5 1.5 0 0 1 20 5.5V9|M4 15v3.5A1.5 1.5 0 0 0 5.5 20H9|M12 12l7.5 3-3.2 1.3L15 19.5Z",
  "archive": "r3.5 4.5 17 4.5 1.5|M5 9v9.5A1.5 1.5 0 0 0 6.5 20h11a1.5 1.5 0 0 0 1.5-1.5V9|M10 12.5h4",
  "markdown": "r2.5 6 19 12 2.5|M6 15V9l2.5 3L11 9v6|M15.5 9v6|M13.5 13l2 2 2-2",
  "tray": "M3.5 13.5 6 5.5h12l2.5 8|M3.5 13.5V18a1.5 1.5 0 0 0 1.5 1.5h14a1.5 1.5 0 0 0 1.5-1.5v-4.5h-5a3.5 3.5 0 0 1-7 0Z",
  "film": "r3 4 18 16 2.5|M7.5 4v16M16.5 4v16|M3 9h4.5M3 15h4.5M16.5 9H21M16.5 15H21",
  "printer": "M7 9V4h10v5|r4 9 16 7.5 2|M7 14h10v6H7Z",
  "snooze": "M20 14.5A8 8 0 0 1 9.5 4a8 8 0 1 0 10.5 10.5Z|M14 4h4l-4 4h4",
  "duplicate": "r8 8 12 12 2.5|r4 4 12 12 2.5",
  "group": "r3.5 3.5 7 7 2|r13.5 3.5 7 7 2|r3.5 13.5 7 7 2|M17 13.5v7M13.5 17h7",
  "save": "M5 4.5h11l3.5 3.5v11.5H5Z|M8 4.5V9h7V4.5|r8 13 8 6.5 1",
  "star": "M12 4l2.4 5 5.4.7-4 3.7 1 5.4L12 16.2 7.2 18.8l1-5.4-4-3.7 5.4-.7Z",
  "chat": "M5 5.5h14a1.5 1.5 0 0 1 1.5 1.5v8.5A1.5 1.5 0 0 1 19 17h-8l-4.5 3.5V17H5a1.5 1.5 0 0 1-1.5-1.5V7A1.5 1.5 0 0 1 5 5.5Z",
  "send": "M4.5 12 19.5 4.5 15 19.5l-3-6Z|M12 13.5l7.5-9",
  "refresh": "M19.5 12a7.5 7.5 0 1 1-2.2-5.3|M19.5 4.5v4h-4",
  "window": "r3 4.5 18 15 2.5|M3 8.5h18|M6 6.5h.01M8.5 6.5h.01",
  "key": "c8 15 4|M11 12l8-8|M16 7l2.5 2.5|M14 9l2 2",
  "sort": "M7 5v14|M4 16l3 3 3-3|M14 7h6M14 12h4M14 17h2",
  "compare": "r3 5 7.5 14 2|r13.5 5 7.5 14 2|M6 9h1.5M16.5 9h1.5M6 12.5h1.5M16.5 12.5h1.5",
  "music": "M9 18V6l11-2v12|c6.5 18 2.5|c17.5 16 2.5",
  "mail": "r3 5.5 18 13 2.5|M3.5 7l8.5 6 8.5-6",
  "hash": "M9 4 7.5 20M16.5 4 15 20M4.5 9h15.5M4 15h15.5",
  "home": "M4 11.5 12 4.5l8 7|M6 10v9.5h4.5V15h3v4.5H18V10",
  "video": "r3 6.5 12.5 11 2.5|M15.5 10.5 21 7.5v9l-5.5-3",
  "gear": "c12 12 3|M12 2.8v2.4M12 18.8v2.4M2.8 12h2.4M18.8 12h2.4M5.5 5.5l1.7 1.7M16.8 16.8l1.7 1.7M5.5 18.5l1.7-1.7M16.8 7.2l1.7-1.7",
  "dots": "M6 12h.01M12 12h.01M18 12h.01",
  "prev": "M11 7 5 12l6 5Z|M19 7l-6 5 6 5Z",
  "next": "M13 7l6 5-6 5Z|M5 7l6 5-6 5Z",
  "playFill": "M8 5.5v13l10.5-6.5Z",
  "wifi": "M3.5 9.5a12 12 0 0 1 17 0|M6.5 12.8a7.5 7.5 0 0 1 11 0|M9.5 16a3 3 0 0 1 5 0|M12 19h.01",
  "chevron": "M9.5 5.5 16 12l-6.5 6.5",
  "chevronDown": "M5.5 9.5 12 16l6.5-6.5",
  "calendar": "r3.5 5 17 15 2.5|M3.5 9.5h17|M8 3v4M16 3v4",
  "timer": "c12 13 7.5|M12 9v4l2.5 2|M9.5 2.5h5",
  "terminal": "r3 4.5 18 15 2.5|M7 9.5l3 2.5-3 2.5|M12.5 14.5h4.5",
  "headphones": "M4 15v-3a8 8 0 0 1 16 0v3|r3.5 14 4 6 1.5|r16.5 14 4 6 1.5",
  "mic": "r9 3 6 11 3|M5.5 11a6.5 6.5 0 0 0 13 0|M12 17.5V21",
  "micOff": "M3 3l18 18|M15 10V6a3 3 0 0 0-5.7-1.3|M9 9v2a3 3 0 0 0 4.8 2.4|M18.5 11a6.5 6.5 0 0 1-1 3.4M5.5 11a6.5 6.5 0 0 0 9.6 5.7|M12 17.5V21",
  "grid": "r4 4 6.5 6.5 1.5|r13.5 4 6.5 6.5 1.5|r4 13.5 6.5 6.5 1.5|r13.5 13.5 6.5 6.5 1.5",
  "code": "M8.5 7 3.5 12l5 5|M15.5 7l5 5-5 5|M13.5 4.5l-3 15",
  "clipboard": "r5 4.5 14 16 2.5|M9 4.5V3.5h6v1|M8.5 10h7M8.5 13.5h7M8.5 17h4",
  "github": "M9 19c-4.3 1.4-4.3-2.5-6-3m12 5v-3.5c0-1 .1-1.4-.5-2 2.8-.3 5.5-1.4 5.5-6a4.6 4.6 0 0 0-1.3-3.2 4.2 4.2 0 0 0-.1-3.2s-1.1-.3-3.5 1.3a12.3 12.3 0 0 0-6.2 0C6.5 2.8 5.4 3.1 5.4 3.1a4.2 4.2 0 0 0-.1 3.2A4.6 4.6 0 0 0 4 9.5c0 4.6 2.7 5.7 5.5 6-.6.6-.6 1.2-.5 2V21",
  "shield": "M12 3.5 5 6v5.5c0 4.3 2.9 7.7 7 9 4.1-1.3 7-4.7 7-9V6Z|M9 12l2.2 2.2L15.5 10",
  "lock": "r4.5 11 15 10 2.5|M8 11V7.5a4 4 0 0 1 8 0V11",
  "faceid": "M3.5 8V5.5a2 2 0 0 1 2-2H8|M16 3.5h2.5a2 2 0 0 1 2 2V8|M20.5 16v2.5a2 2 0 0 1-2 2H16|M8 20.5H5.5a2 2 0 0 1-2-2V16|M9 9v1.6|M15 9v1.6|M12 9.2v3.8h-1|M9.3 15.8c1.6 1.2 3.8 1.2 5.4 0",
  "eye": "M2.5 12c1-2.5 4.5-7 9.5-7s8.5 4.5 9.5 7c-1 2.5-4.5 7-9.5 7s-8.5-4.5-9.5-7Z|c12 12 3",
  "user": "c12 8.5 3.6|M5 20c.8-3.6 3.6-6 7-6s6.2 2.4 7 6",
  "scale": "M12 4v16|M5 20h14|M6 8h12|M6 8l-3 6a3 3 0 0 0 6 0Z|M18 8l-3 6a3 3 0 0 0 6 0Z",
  "arrowUp": "M12 19V5|M6 11l6-6 6 6",
  "arrowRight": "M5 12h14|M13 6l6 6-6 6",
  "agentDot": "c12 12 3"
};

const SVGNS = 'http://www.w3.org/2000/svg';

export function icon(name, size = 18, extraClass = '') {
  const svg = document.createElementNS(SVGNS, 'svg');
  const attrs = { width: size, height: size, viewBox: '0 0 24 24', fill: 'none', stroke: 'currentColor', 'stroke-width': 1.7,
    'stroke-linecap': 'round', 'stroke-linejoin': 'round', 'aria-hidden': 'true', class: `icon ${extraClass}`.trim() };
  for (const [key, value] of Object.entries(attrs)) svg.setAttribute(key, value);
  for (const part of (ICONS[name] || ICONS.sparkle).split('|')) {
    let node;
    if (part[0] === 'c') {
      const [cx, cy, r] = part.slice(1).split(' ');
      node = document.createElementNS(SVGNS, 'circle');
      node.setAttribute('cx', cx); node.setAttribute('cy', cy); node.setAttribute('r', r);
    } else if (part[0] === 'r') {
      const [x, y, w, hgt, rx] = part.slice(1).split(' ');
      node = document.createElementNS(SVGNS, 'rect');
      node.setAttribute('x', x); node.setAttribute('y', y); node.setAttribute('width', w); node.setAttribute('height', hgt);
      if (rx) node.setAttribute('rx', rx);
    } else {
      node = document.createElementNS(SVGNS, 'path');
      node.setAttribute('d', part);
    }
    svg.append(node);
  }
  if (name === 'playFill' || name === 'prev' || name === 'next') svg.setAttribute('fill', 'currentColor');
  return svg;
}

// The four-block SAVISUL mark, same proportions as the app icon.
export function mark(width = 20, extraClass = '') {
  const svg = document.createElementNS(SVGNS, 'svg');
  svg.setAttribute('viewBox', '0 0 20 12');
  svg.setAttribute('width', width);
  svg.setAttribute('height', (width * 12) / 20);
  svg.setAttribute('aria-hidden', 'true');
  svg.setAttribute('class', `mark ${extraClass}`.trim());
  svg.setAttribute('fill', 'currentColor');
  for (const [x, y, w, hgt, r] of [[0, 0, 5.6, 12, 0.78], [7.1, 0, 2.4, 12, 0.34], [11, 0, 9, 5.25, 0.74], [11, 6.75, 9, 5.25, 0.74]]) {
    const rect = document.createElementNS(SVGNS, 'rect');
    rect.setAttribute('x', x); rect.setAttribute('y', y); rect.setAttribute('width', w); rect.setAttribute('height', hgt); rect.setAttribute('rx', r);
    svg.append(rect);
  }
  return svg;
}

// Replaces <i data-icon="name" data-size="16"> placeholders in static markup.
export function hydrateIcons(root = document) {
  for (const slot of root.querySelectorAll('i[data-icon]')) slot.replaceWith(icon(slot.dataset.icon, Number(slot.dataset.size) || 18));
  for (const slot of root.querySelectorAll('i[data-mark]')) slot.replaceWith(mark(Number(slot.dataset.mark) || 20));
}
