// Face Unlock, acted out: the lock screen, the padlock under the notch, the scanning ring and the way in.
// One timeline drives every part, so the field guide plate, the desktop demo and the README GIF show the same seconds.
import { h } from './dom.js';
import { icon } from './icons.js';
import { t } from './i18n.js';

/** Seconds in one run, from the locked screen back to it. */
export const FACE_LOOP = 6.4;

const W = 1280;
const H = 640;
const NOTCH = { w: 236, h: 40 };
const SIZES = {
  rest: { w: NOTCH.w, h: NOTCH.h, r: 14 },
  locked: { w: NOTCH.w + 22, h: NOTCH.h + 46, r: 22 },
  scan: { w: 304, h: NOTCH.h + 196, r: 40 },
  notice: { w: NOTCH.w + 340, h: NOTCH.h + 50, r: 26 }
};
// When the island takes each shape.
const SHAPES = [[0, 'rest'], [0.3, 'rest'], [0.7, 'locked'], [1.1, 'locked'], [1.5, 'scan'], [3.55, 'scan'],
  [3.95, 'notice'], [5.4, 'notice'], [5.75, 'rest'], [FACE_LOOP, 'rest']];
const TICKS = 30;
const RING = 76;

const clamp = (x) => Math.min(1, Math.max(0, x));
const seg = (time, from, to) => clamp((time - from) / (to - from));
const mix = (a, b, p) => a + (b - a) * p;
const smooth = (p) => (p < 0.5 ? 4 * p * p * p : 1 - Math.pow(-2 * p + 2, 3) / 2);
const overshoot = (p) => 1 + 2.4 * Math.pow(p - 1, 3) + 1.4 * Math.pow(p - 1, 2);
const SVGNS = 'http://www.w3.org/2000/svg';

function glyph(paths, size, width, extra) {
  const svg = document.createElementNS(SVGNS, 'svg');
  for (const [key, value] of Object.entries({ width: size, height: size, viewBox: '0 0 24 24', fill: 'none', stroke: 'currentColor',
    'stroke-width': width, 'stroke-linecap': 'round', 'stroke-linejoin': 'round', 'aria-hidden': 'true', class: extra })) svg.setAttribute(key, value);
  for (const d of paths) {
    const path = document.createElementNS(SVGNS, 'path');
    path.setAttribute('d', d);
    svg.append(path);
  }
  return svg;
}

const FACE = ['M3.5 8V5.5a2 2 0 0 1 2-2H8', 'M16 3.5h2.5a2 2 0 0 1 2 2V8', 'M20.5 16v2.5a2 2 0 0 1-2 2H16', 'M8 20.5H5.5a2 2 0 0 1-2-2V16',
  'M9 9v1.6', 'M15 9v1.6', 'M12 9.2v3.8h-1', 'M9.3 15.8c1.6 1.2 3.8 1.2 5.4 0'];
const CHECK = ['M5.5 12.5l4.2 4.2L18.5 7.8'];

/** The scene at 1280×640, scaled by its container. `play()` loops it; `render(seconds)` draws one moment, for capture. */
export function createFaceDemo({ live = true } = {}) {
  const wallpaper = h('div', { class: 'fd-wallpaper' });
  const now = new Date();
  const date = now.toLocaleDateString(t('faceDemoLocale'), { weekday: 'long', month: 'long', day: 'numeric' });
  const lock = h('div', { class: 'fd-lock' },
    h('p', { class: 'fd-date', text: date }),
    h('p', { class: 'fd-time', text: '9:41' }),
    h('div', { class: 'fd-user' }, h('span', { class: 'fd-avatar' }, icon('user', 22)), h('span', { class: 'fd-field', text: t('faceDemoField') })));
  const window1 = h('div', { class: 'fd-window one' }, h('i'), h('b'), h('b'), h('b'));
  const window2 = h('div', { class: 'fd-window two' }, h('i'), h('b'), h('b'));
  const desktop = h('div', { class: 'fd-desktop' }, h('div', { class: 'fd-menubar' }), window1, window2);

  const padlock = h('span', { class: 'fd-padlock' }, icon('lock', 26));
  const face = h('span', { class: 'fd-face' }, glyph(FACE, 92, 1.35));
  const check = h('span', { class: 'fd-check' }, glyph(CHECK, 74, 2.3));
  const ticks = Array.from({ length: TICKS }, (_, index) => h('i', { style: { '--a': `${(index / TICKS) * 360}deg` } }));
  const ring = h('span', { class: 'fd-ring', style: { '--r': `${RING}px` } }, ...ticks);
  const notice = h('span', { class: 'fd-notice' }, glyph(CHECK, 26, 2.6, 'fd-notice-check'), h('b', { text: t('faceDemoUnlocked') }));
  const island = h('div', { class: 'fd-island' }, h('div', { class: 'fd-body' }, h('span', { class: 'fd-lens' }), padlock, ring, face, check, notice));

  const stage = h('div', { class: 'fd-stage' }, wallpaper, desktop, lock, island);
  const el = h('div', { class: 'face-demo', role: 'img', 'aria-label': t('faceDemoLabel') }, stage);

  function shapeAt(time) {
    for (let index = 0; index < SHAPES.length - 1; index++) {
      const [from, a] = SHAPES[index];
      const [to, b] = SHAPES[index + 1];
      if (time >= from && time <= to) {
        const p = to > from ? (time - from) / (to - from) : 1;
        const grow = SIZES[b].w * SIZES[b].h > SIZES[a].w * SIZES[a].h;
        const k = grow ? overshoot(p) : smooth(p);
        return { w: mix(SIZES[a].w, SIZES[b].w, k), h: mix(SIZES[a].h, SIZES[b].h, k), r: mix(SIZES[a].r, SIZES[b].r, clamp(k)) };
      }
    }
    return SIZES.rest;
  }

  function render(seconds) {
    const time = ((seconds % FACE_LOOP) + FACE_LOOP) % FACE_LOOP;
    const shape = shapeAt(time);
    island.style.width = `${shape.w}px`;
    island.style.height = `${shape.h}px`;
    island.style.setProperty('--radius', `${shape.r}px`);

    padlock.style.opacity = seg(time, 0.45, 0.75) * (1 - seg(time, 1.1, 1.28));
    face.style.opacity = seg(time, 1.3, 1.55) * (1 - seg(time, 3.0, 3.15));
    const checkIn = seg(time, 3.1, 3.4);
    check.style.opacity = seg(time, 3.1, 3.3) * (1 - seg(time, 3.45, 3.62));
    check.style.transform = `translate(-50%, -50%) scale(${mix(0.55, 1, overshoot(checkIn))})`;

    const ringOn = seg(time, 1.3, 1.55) * (1 - seg(time, 3.45, 3.62));
    const green = seg(time, 3.0, 3.25);
    const turn = (((time - 1.3) / 1.1) % 1 + 1) % 1;
    ring.style.opacity = ringOn;
    // A soft green light under the island once it knows the face.
    island.style.boxShadow = `0 22px 70px -20px rgba(140, 214, 176, ${(0.55 * green * ringOn).toFixed(3)})`;
    ticks.forEach((tick, index) => {
      const behind = (turn - index / TICKS + 1) % 1;
      const sweep = Math.max(0.14, 1 - behind * 2.2);
      tick.style.opacity = mix(sweep, 1, green);
      tick.style.setProperty('--g', green);
    });

    notice.style.opacity = seg(time, 3.85, 4.1) * (1 - seg(time, 5.4, 5.55));

    const open = smooth(seg(time, 3.45, 4.05)) - smooth(seg(time, 5.85, 6.35));
    wallpaper.style.filter = `blur(${mix(18, 0, open)}px) brightness(${mix(0.58, 1, open)}) saturate(${mix(1.15, 1, open)})`;
    lock.style.opacity = 1 - open;
    lock.style.transform = `translateY(${-28 * open}px)`;
    desktop.style.opacity = open;
    desktop.style.transform = `scale(${mix(1.04, 1, open)})`;
  }

  // The stage is drawn at 1280×640 and scaled to whatever box holds it.
  const fit = () => {
    const box = el.getBoundingClientRect();
    const scale = Math.max(box.width / W, box.height / H) || 1;
    stage.style.transform = `translate(-50%, -50%) scale(${scale})`;
  };
  new ResizeObserver(fit).observe(el);

  let frame = 0;
  let started = 0;
  const loop = (stamp) => {
    // A plate rebuilt for another language leaves this one behind; it stops with it.
    if (!el.isConnected) return stop();
    if (!started) started = stamp;
    render((stamp - started) / 1000);
    frame = requestAnimationFrame(loop);
  };
  function play() {
    if (frame) return;
    started = 0;
    frame = requestAnimationFrame(loop);
  }
  function stop() {
    cancelAnimationFrame(frame);
    frame = 0;
  }

  render(0);
  if (live) {
    const still = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    if (still) {
      render(3.35);
    } else {
      // Plays only while on screen.
      new IntersectionObserver(([entry]) => {
        if (entry.isIntersecting) play(); else stop();
      }).observe(el);
    }
  }
  return { el, render, play, stop, fit };
}

/** The whole run once over the live desktop, ending on the unlocked desktop, then the real desktop comes back. */
export function playOverDesktop(host) {
  const demo = createFaceDemo({ live: false });
  demo.el.classList.add('fd-over');
  host.append(demo.el);
  demo.fit();
  const still = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  let started = 0;
  const end = 4.9;
  const step = (stamp) => {
    if (!started) started = stamp;
    const seconds = still ? end : (stamp - started) / 1000;
    demo.render(Math.min(seconds, end));
    if (seconds < end) {
      requestAnimationFrame(step);
      return;
    }
    demo.el.style.opacity = '0';
    setTimeout(() => demo.el.remove(), 480);
  };
  requestAnimationFrame(step);
}
