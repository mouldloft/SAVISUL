// End-to-end check of the SAVISUL extension in headless Chrome, including the native host bridge.
// Usage: node browser-test.mjs   (CHROME=..., HOST_BIN=... to override paths)
import puppeteer from 'puppeteer-core';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { mkdtemp, mkdir, writeFile, rm } from 'node:fs/promises';
import { existsSync, unlinkSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import assert from 'node:assert/strict';

const here = path.dirname(fileURLToPath(import.meta.url));
const EXTENSION = path.resolve(here, '../../Extension');
const OUT = path.join(here, 'out');
const CHROME = process.env.CHROME || ['/Applications', path.join(os.homedir(), 'Applications'), path.join(os.homedir(), 'Desktop')]
  .map((dir) => path.join(dir, 'Google Chrome.app/Contents/MacOS/Google Chrome')).find(existsSync);
const HOST_BIN = process.env.HOST_BIN || '/Applications/SAVISUL.app/Contents/MacOS/SAVISUL';
const ID = 'cfgamdkhojfgnkklaojekgbpiclaapig';
const WIDTH = 1280;
const HEIGHT = 820;
const DPR = 2;

// MARK: Fixtures

const paragraphs = [
  'When the last regional service leaves the platform, a different railway wakes up. Night trains run on timetables that look leisurely on paper, yet every minute of the schedule is negotiated with freight operators, track crews and the slow arithmetic of sleeping passengers who must arrive rested rather than early.',
  'The carriages themselves are small feats of acoustic engineering. Floors float on rubber mounts, couplings are tensioned so the train starts without the familiar jolt, and the air system moves fresh air at a speed low enough that nobody feels a draught at two in the morning.',
  'Operators learned the hard way that comfort is mostly about predictability. A sleeper that brakes gently every time is better than one that is faster but uneven, because passengers forgive a late arrival far more easily than a night spent bracing against the wall.',
  'Maintenance happens in the narrow window when the train is parked at its destination. Crews have roughly six hours to clean, restock and inspect a set before it turns around, and the most reliable fleets are the ones designed so that every routine check can be done from the depot floor.',
  'There is also a quiet economic argument. A train that travels while people sleep turns hotel nights into seat kilometres, and for journeys between eight hundred and fifteen hundred kilometres it competes surprisingly well with short flights once the whole door-to-door time is counted.',
  'None of this works without the stations. Late-evening departures need staffed concourses, warm waiting rooms and connections that still run, which is why the revival of night trains tends to follow cities that already invested in their central stations.'
];

const tracked = '/article?utm_source=newsletter&utm_medium=email&fbclid=XYZ123&id=7';

const fixtures = {
  '/article': () => `<!doctype html><html lang="en"><head><meta charset="utf-8">
<title>The Quiet Engineering of Night Trains — Railway Review</title>
<meta property="og:title" content="The Quiet Engineering of Night Trains">
<meta name="author" content="Mira Holt">
<meta property="article:published_time" content="2026-09-28T08:00:00Z">
<style>
  body { margin: 0; font: 17px/1.6 Georgia, serif; background: #fff; color: #1f1f1f; }
  header { position: sticky; top: 0; z-index: 5; display: flex; gap: 22px; align-items: center; padding: 14px 32px; background: #fbfaf7; border-bottom: 1px solid #e4e0d8; font: 600 15px system-ui; }
  header nav a { color: #555; margin-right: 14px; text-decoration: none; }
  main { display: flex; gap: 48px; padding: 32px; }
  article { max-width: 700px; }
  h1 { font-size: 42px; line-height: 1.15; margin: 0 0 10px; }
  .byline { color: #777; font: 14px system-ui; }
  figure { margin: 28px 0; }
  figure img { width: 100%; border-radius: 10px; display: block; }
  figcaption { color: #888; font: 13px system-ui; margin-top: 8px; }
  blockquote { border-left: 3px solid #c9b98f; margin: 24px 0; padding: 4px 18px; color: #555; font-style: italic; }
  pre { background: #f4f2ee; padding: 14px; border-radius: 8px; font-size: 14px; }
  aside { width: 260px; font: 14px/1.5 system-ui; }
  aside a { display: block; color: #2c5fa8; margin: 6px 0; }
  .ad { margin: 24px 0; height: 180px; display: grid; place-items: center; background: repeating-linear-gradient(45deg, #fff6d6, #fff6d6 12px, #ffeeb0 12px, #ffeeb0 24px); border: 1px dashed #d8b84c; color: #9a7b14; font-weight: 700; }
  .cookie { position: fixed; left: 24px; right: 24px; bottom: 20px; z-index: 9; display: flex; justify-content: space-between; align-items: center; padding: 16px 20px; border-radius: 12px; background: #222; color: #eee; font: 14px system-ui; }
  footer { padding: 48px 32px; background: #f2f0eb; color: #777; font: 14px system-ui; }
</style></head><body>
<header><strong>Railway Review</strong><nav><a href="/">Home</a><a href="/">Trains</a><a href="/">Stations</a><a href="/">About</a></nav></header>
<main>
  <article>
    <h1>The Quiet Engineering of Night Trains</h1>
    <p class="byline">By Mira Holt · Sep 28, 2026</p>
    <p>${paragraphs[0]}</p>
    <figure><img alt="Sleeper train at dusk" src="data:image/svg+xml;utf8,${encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" width="1400" height="700"><defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#1d2b4a"/><stop offset="1" stop-color="#d98b5f"/></linearGradient></defs><rect width="1400" height="700" fill="url(#g)"/><rect x="120" y="430" width="1160" height="120" rx="24" fill="#20242c"/><g fill="#f4d48a">' + Array.from({ length: 12 }, (_, i) => `<rect x="${160 + i * 92}" y="460" width="60" height="34" rx="6"/>`).join('') + '</g><rect y="560" width="1400" height="12" fill="#0d0f13"/></svg>')}">
      <figcaption>A sleeper set waiting for its evening departure.</figcaption></figure>
    <p>${paragraphs[1]}</p>
    <h2>Predictability beats speed</h2>
    <p>${paragraphs[2]}</p>
    <blockquote>Passengers forgive a late arrival far more easily than a night spent bracing against the wall.</blockquote>
    <p>${paragraphs[3]}</p>
    <pre><code>turnaround = clean(35) + restock(40) + inspect(90) + buffer(15)</code></pre>
    <h2>The economics</h2>
    <p>${paragraphs[4]}</p>
    <p>${paragraphs[5]}</p>
  </article>
  <aside>
    <h3>Related</h3>
    <a href="/">Europe’s new sleeper routes</a><a href="/">How couplings work</a><a href="/">Inside a depot at 3 a.m.</a><a href="/">The return of the dining car</a>
    <div class="ad" id="ad">Advertisement</div>
  </aside>
</main>
<div class="cookie">We use cookies to improve your experience. <button>Accept</button></div>
<footer>© 2026 Railway Review</footer>
</body></html>`,

  '/long': () => {
    const colors = ['#e8584f', '#f0a04b', '#e8c43f', '#7cc576', '#4fb3c9', '#4f73e8', '#8a5be8', '#d45bb5', '#6b6b6b', '#2ea36b', '#c97a3a', '#3a7ac9'];
    return `<!doctype html><html><head><meta charset="utf-8"><title>Long page</title><style>
      body { margin: 0; font: 700 30px system-ui; }
      header { position: sticky; top: 0; z-index: 3; height: 64px; display: flex; align-items: center; padding: 0 24px; background: #111; color: #fff; }
      .band { height: 500px; display: flex; align-items: center; justify-content: center; color: #fff; }
      .chat { position: fixed; right: 20px; bottom: 20px; width: 64px; height: 64px; border-radius: 50%; background: #000; }
    </style></head><body><header>Sticky header</header>${colors.map((color, i) => `<div class="band" style="background:${color}">Band ${i + 1}</div>`).join('')}<div class="chat"></div>
    <script>window.BANDS = ${JSON.stringify(colors)};</script></body></html>`;
  },

  '/dark': () => `<!doctype html><html><head><meta charset="utf-8"><title>Already dark</title><style>
    body { margin: 0; padding: 60px; background: #121212; color: #ddd; font: 18px/1.6 system-ui; }
  </style></head><body><h1>Already dark</h1><p>${paragraphs[0]}</p><p>${paragraphs[1]}</p></body></html>`
};

// MARK: Harness

const results = [];
const problems = [];
let shotIndex = 0;

const ONLY = process.env.ONLY ? process.env.ONLY.split(',') : null;

async function step(name, run) {
  if (ONLY && results.length && !ONLY.some((part) => name.includes(part))) return;
  const started = Date.now();
  try {
    const detail = await run();
    results.push({ name, ok: true, ms: Date.now() - started, detail });
  } catch (error) {
    results.push({ name, ok: false, ms: Date.now() - started, detail: error?.stack?.split('\n').slice(0, 3).join(' | ') || String(error) });
  }
}

const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function until(check, { timeout = 6000, every = 80, label = 'condition' } = {}) {
  const deadline = Date.now() + timeout;
  let last;
  while (Date.now() < deadline) {
    try {
      last = await check();
      if (last) return last;
    } catch (error) {
      last = error.message;
    }
    await wait(every);
  }
  throw new Error(`timed out waiting for ${label} (last: ${JSON.stringify(last)})`);
}

async function snap(page, name) {
  const file = path.join(OUT, `${String(++shotIndex).padStart(2, '0')}-${name}.png`);
  await page.screenshot({ path: file });
  return file;
}

/** Evaluates code in the extension's isolated world, where `SV` lives. */
async function isolatedWorld(page) {
  const client = await page.createCDPSession();
  const contexts = new Map();
  client.on('Runtime.executionContextCreated', ({ context }) => contexts.set(context.id, context));
  client.on('Runtime.executionContextDestroyed', ({ executionContextId }) => contexts.delete(executionContextId));
  client.on('Runtime.executionContextsCleared', () => contexts.clear());
  client.on('Runtime.exceptionThrown', ({ exceptionDetails }) => {
    problems.push(`exception on ${page.url()}: ${exceptionDetails.exception?.description?.split('\n')[0] || exceptionDetails.text}`);
  });
  client.on('Runtime.consoleAPICalled', ({ type, args }) => {
    if (type === 'error' || type === 'warning') problems.push(`console.${type} on ${page.url()}: ${args.map((a) => a.value ?? a.description).join(' ')}`);
  });
  await client.send('Runtime.enable');
  const find = () => [...contexts.values()].find((c) => c.auxData?.type === 'isolated' && c.origin?.includes(ID) && c.auxData?.frameId === page.mainFrame()._id)
    || [...contexts.values()].find((c) => c.auxData?.type === 'isolated' && c.origin?.includes(ID));
  const run = async (expression) => {
    const context = await until(find, { timeout: 8000, label: 'isolated world' });
    const { result, exceptionDetails } = await client.send('Runtime.evaluate', {
      expression, contextId: context.id, returnByValue: true, awaitPromise: true, userGesture: true
    });
    if (exceptionDetails) throw new Error(exceptionDetails.exception?.description?.split('\n')[0] || exceptionDetails.text);
    return result.value;
  };
  return run;
}

// MARK: Run

await rm(OUT, { recursive: true, force: true });
await mkdir(OUT, { recursive: true });

const server = http.createServer((request, response) => {
  const route = fixtures[new URL(request.url, 'http://localhost').pathname];
  if (!route) {
    response.writeHead(404).end('not found');
    return;
  }
  response.writeHead(200, { 'content-type': 'text/html; charset=utf-8' }).end(route());
});
await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
const port = server.address().port;
const local = `http://localhost:${port}`;
const other = `http://127.0.0.1:${port}`;

const profile = await mkdtemp(path.join(os.tmpdir(), 'savisul-chrome-'));
await mkdir(path.join(profile, 'NativeMessagingHosts'), { recursive: true });
await writeFile(path.join(profile, 'NativeMessagingHosts', 'com.savisul.bridge.json'), JSON.stringify({
  name: 'com.savisul.bridge', description: 'SAVISUL for Mac', path: HOST_BIN, type: 'stdio',
  allowed_origins: [`chrome-extension://${ID}/`]
}));

const browser = await puppeteer.launch({
  executablePath: CHROME,
  headless: true,
  pipe: true,
  enableExtensions: true,
  userDataDir: profile,
  defaultViewport: null,
  args: [`--window-size=${WIDTH},${HEIGHT}`, `--force-device-scale-factor=${DPR}`, '--no-first-run', '--no-default-browser-check', '--lang=ru', '--hide-crash-restore-bubble']
});

let worker;
let page;
let sv;
const savedFiles = [];

try {
  await step('extension installs with the fixed id', async () => {
    const id = await browser.installExtension(EXTENSION);
    assert.equal(id, ID);
    const target = await browser.waitForTarget((t) => t.type() === 'service_worker' && t.url().startsWith(`chrome-extension://${ID}/`), { timeout: 10000 });
    worker = await target.worker();
    worker.on('console', (message) => {
      if (['error', 'warn'].includes(message.type())) problems.push(`worker ${message.type()}: ${message.text()}`);
    });
    return id;
  });

  const command = (name) => worker.evaluate(async (href, name) => {
    const tab = (await chrome.tabs.query({})).find((t) => t.url === href);
    if (!tab) throw new Error(`no tab for ${href}`);
    await chrome.tabs.sendMessage(tab.id, { type: 'command', command: name }).catch(() => {});
    return true;
  }, page.url(), name);

  const open = async (url) => {
    page = await browser.newPage();
    page.on('pageerror', (error) => problems.push(`pageerror on ${url}: ${error.message}`));
    await page.goto(url, { waitUntil: 'load' });
    await page.bringToFront();
    sv = await isolatedWorld(page);
    await until(() => sv('!!(globalThis.SV && SV.alive && SV.root)'), { label: 'notch mounted' });
    return page;
  };

  await step('notch mounts in the top layer of a normal page', async () => {
    await open(local + tracked);
    const info = await sv(`({ view: SV.notch.view, popover: SV.root.host.matches(':popover-open'), tag: SV.root.host.localName, closed: SV.root.host.shadowRoot === null })`);
    assert.equal(info.tag, 'savisul-notch');
    assert.equal(info.popover, true, 'host is shown as a popover');
    assert.equal(info.closed, true, 'shadow root is closed to the page');
    assert.equal(info.view, 'idle');
    await wait(400);
    await snap(page, 'idle');
    return JSON.stringify(info);
  });

  await step('notch stays above a page dialog and fullscreen', async () => {
    const stack = () => page.evaluate(() => document.elementsFromPoint(innerWidth / 2, 10).slice(0, 5).map((el) => el.localName));
    const before = await stack();
    await page.evaluate(() => {
      const dialog = document.createElement('dialog');
      dialog.id = 'cover';
      dialog.style.cssText = 'width:100vw;height:100vh;max-width:none;max-height:none;margin:0;padding:0;border:0;background:#e11';
      document.body.append(dialog);
      dialog.showModal();
    });
    await wait(250);
    const after = await stack();
    assert.equal(after[0], 'savisul-notch', `before ${before.join('>')} after ${after.join('>')}`);
    await page.evaluate(() => document.querySelector('#cover')?.close());
    await wait(80);
    await page.evaluate(() => document.documentElement.requestFullscreen().catch(() => {}));
    await wait(250);
    const full = await stack();
    if (await page.evaluate(() => !!document.fullscreenElement)) {
      assert.equal(full[0], 'savisul-notch', `fullscreen ${full.join('>')}`);
      await page.evaluate(() => document.exitFullscreen());
    }
    return `before ${before[0]} · dialog ${after[0]}`;
  });

  await step('injecting the scripts again keeps one working notch', async () => {
    await worker.evaluate(async (href) => {
      const tab = (await chrome.tabs.query({})).find((t) => t.url === href);
      const files = chrome.runtime.getManifest().content_scripts.flatMap((entry) => entry.js);
      await chrome.scripting.executeScript({ target: { tabId: tab.id }, files });
    }, page.url());
    await wait(600);
    const hosts = await page.evaluate(() => document.querySelectorAll('savisul-notch').length);
    assert.equal(hosts, 1, `${hosts} notches on the page`);
    const before = await sv(`SV.tools.outline.active()`);
    await sv(`SV.runTool('outline')`);
    await wait(150);
    const after = await sv(`SV.tools.outline.active()`);
    assert.equal(after, !before, 'a toggle flips exactly once');
    await sv(`SV.runTool('outline')`);
    return `${hosts} notch, outline ${before} → ${after}`;
  });

  await step('hovering the notch opens home with live SAVISUL state', async () => {
    const box = await sv(`(() => { const r = SV.root.querySelector('.notch').getBoundingClientRect(); return { x: r.x + r.width / 2, y: r.y + r.height / 2 }; })()`);
    await page.mouse.move(box.x, box.y + 30, { steps: 2 });
    await page.mouse.move(box.x, box.y, { steps: 4 });
    await until(() => sv(`SV.notch.view === 'home'`), { label: 'home view', timeout: 3000 }).catch(async (error) => {
      const debug = await sv(`({ view: SV.notch.view, hovering: SV.notch.hovering, box: ${JSON.stringify(box)}, rect: SV.root.querySelector('.notch').getBoundingClientRect().toJSON(), at: document.elementFromPoint(${box.x}, ${box.y})?.localName, open: SV.root.host.matches(':popover-open'), connected: SV.root.host.isConnected, settings: !!SV.settings, hover: SV.settings?.hover })`);
      throw new Error(`${error.message} ${JSON.stringify(debug)}`);
    });
    const mac = await until(() => sv(`(() => { const m = SV.root.querySelector('.mac'); return m?.querySelector('.mac-row') ? m.parentElement.textContent : ''; })()`), { timeout: 8000, label: 'mac section with state' });
    await wait(700);
    await snap(page, 'home');
    return mac.replace(/\s+/g, ' ').slice(0, 140);
  });

  await step('notes panel saves a note for this URL', async () => {
    await sv(`SV.notch.openPanel('notes', { direct: true })`);
    await until(() => sv(`!!SV.root.querySelector('textarea.note')`), { label: 'notes textarea' });
    await sv(`(() => { const a = SV.root.querySelector('textarea.note'); a.focus(); a.value = 'Check the depot timings in the turnaround formula.'; a.dispatchEvent(new Event('input', { bubbles: true })); })()`);
    const saved = await until(() => sv(`SV_STORE.getNotes(location.href).then((n) => n.page?.text || '')`), { label: 'saved note' });
    await wait(500);
    await snap(page, 'notes');
    return saved;
  });

  await step('link panel strips trackers and the QR code decodes to the clean link', async () => {
    await sv(`SV.notch.openPanel('link')`);
    const data = await until(() => sv(`SV.root.querySelector('canvas.qr')?.toDataURL('image/png') || ''`), { label: 'qr canvas' });
    const clean = await sv(`SV_STORE.cleanUrl(location.href)`);
    assert.ok(!/utm_|fbclid/.test(clean.url), clean.url);
    assert.ok(clean.url.includes('id=7'), 'keeps real parameters');
    const file = path.join(OUT, 'qr.png');
    await writeFile(file, Buffer.from(data.split(',')[1], 'base64'));
    const decoded = execFileSync(path.join(here, '.bin', 'qr-decode'), [file]).toString().trim();
    assert.equal(decoded, clean.url);
    await wait(500);
    await snap(page, 'link');
    return `${clean.removed} removed → ${decoded}`;
  });

  await step('reader mode extracts the article and closes with Esc', async () => {
    await sv(`SV.notch.close()`);
    await page.mouse.move(640, 500);
    await command('reader');
    await until(() => sv(`SV.tools.reader.active()`), { label: 'reader open' });
    const info = await sv(`(() => { const r = SV.root.querySelector('.reader'); return { title: r.querySelector('h1')?.textContent, paragraphs: r.querySelectorAll('.r-body p').length, junk: /Accept|Advertisement|Related/.test(r.textContent), byline: /By Mira Holt/.test(r.querySelector('.r-body').textContent), images: r.querySelectorAll('img').length }; })()`);
    assert.match(info.title || '', /Night Trains/);
    assert.ok(info.paragraphs >= 6, `paragraphs: ${info.paragraphs}`);
    assert.equal(info.junk, false, 'navigation, ads and cookie banner are dropped');
    assert.equal(info.byline, false, 'byline is shown once, in the reader header');
    await wait(800);
    await snap(page, 'reader');
    await page.keyboard.press('Escape');
    await until(async () => !(await sv(`SV.tools.reader.active()`)), { label: 'reader closed' });
    const scroll = await page.evaluate(() => getComputedStyle(document.documentElement).overflow);
    assert.notEqual(scroll, 'hidden', 'page scroll restored');
    return JSON.stringify(info);
  });

  await step('ruler measures the element under the pointer', async () => {
    await command('ruler');
    await until(() => sv(`SV.mode.active() === 'ruler' || SV.tools.ruler.active?.()`), { label: 'ruler mode' });
    const h1 = await page.evaluate(() => { const r = document.querySelector('h1').getBoundingClientRect(); return { x: r.x + 40, y: r.y + r.height / 2 }; });
    await sv(`(() => { globalThis.__moves = []; document.addEventListener('pointermove', (e) => __moves.push([e.clientX, e.clientY, e.target.localName, SV.isOurs(e.target)]), true); })()`);
    await page.mouse.move(h1.x, h1.y, { steps: 5 });
    const tag = await until(() => sv(`SV.root.querySelector('.ruler-layer .tag')?.textContent || ''`), { label: 'ruler tag', timeout: 3000 }).catch(async (error) => {
      const debug = await sv(`({ moves: __moves.slice(-3), at: document.elementFromPoint(${h1.x}, ${h1.y})?.localName, layer: SV.root.querySelector('.ruler-layer')?.childElementCount, active: SV.tools.ruler.active(), view: SV.notch.view, vis: document.visibilityState })`);
      throw new Error(`${error.message} ${JSON.stringify(debug)}`);
    });
    await wait(300);
    await snap(page, 'ruler');
    await page.keyboard.press('Escape');
    await until(async () => !(await sv(`!!SV.mode.active()`)), { label: 'ruler closed' });
    return tag;
  });

  await step('font inspector reads the paragraph typography', async () => {
    await sv(`SV.runTool('fonts')`);
    await until(() => sv(`!!SV.mode.active()`), { label: 'fonts mode' });
    const p = await page.evaluate(() => { const r = document.querySelector('article p:nth-of-type(2)').getBoundingClientRect(); return { x: r.x + 120, y: r.y + 20 }; });
    await page.mouse.move(p.x, p.y, { steps: 5 });
    const card = await until(() => sv(`(() => { const c = SV.root.querySelector('.inspector'); return c && /Georgia/.test(c.querySelector('.family')?.textContent) ? c.textContent : ''; })()`), { label: 'font card' });
    await wait(300);
    await snap(page, 'fonts');
    await page.keyboard.press('Escape');
    await until(async () => !(await sv(`!!SV.mode.active()`)), { label: 'fonts closed' });
    return card.replace(/\s+/g, ' ').slice(0, 120);
  });

  await step('zapper hides a clicked element', async () => {
    await command('zapper');
    await until(() => sv(`!!SV.mode.active()`), { label: 'zapper mode' });
    const ad = await page.evaluate(() => { document.querySelector('#ad').scrollIntoView({ block: 'center' }); const r = document.querySelector('#ad').getBoundingClientRect(); return { x: r.x + r.width / 2, y: r.y + r.height / 2 }; });
    await page.mouse.move(ad.x, ad.y, { steps: 4 });
    await wait(150);
    await page.mouse.click(ad.x, ad.y);
    await until(() => page.evaluate(() => getComputedStyle(document.querySelector('#ad')).display === 'none'), { label: 'ad hidden' });
    await wait(300);
    await snap(page, 'zapper');
    await page.keyboard.press('Escape');
    await until(async () => !(await sv(`!!SV.mode.active()`)), { label: 'zapper closed' });
    const rules = await worker.evaluate(async () => (await chrome.storage.local.get('zapRules')).zapRules || {});
    return JSON.stringify(rules);
  });

  await step('dark theme inverts a light page and turns back off', async () => {
    await page.evaluate(() => window.scrollTo(0, 0));
    await command('dark');
    await until(() => page.evaluate(() => getComputedStyle(document.documentElement).filter.includes('invert')), { label: 'invert filter' });
    await wait(600);
    await snap(page, 'dark');
    const notchUnaffected = await sv(`getComputedStyle(SV.root.host).filter`);
    const darkState = `({ attr: document.documentElement.getAttribute('data-savisul-dark'), marker: getComputedStyle(document.documentElement).getPropertyValue('--savisul-dark-loaded'), active: SV.tools.dark.active(), filter: getComputedStyle(document.documentElement).filter })`;
    const between = await sv(darkState);
    await command('dark');
    await until(() => page.evaluate(() => !getComputedStyle(document.documentElement).filter.includes('invert')), { label: 'invert removed', timeout: 3000 }).catch(async (error) => {
      throw new Error(`${error.message} before=${JSON.stringify(between)} after=${JSON.stringify(await sv(darkState))}`);
    });
    return `notch filter: ${notchUnaffected}`;
  });

  await step('dark everywhere skips sites that are already dark', async () => {
    await worker.evaluate(() => chrome.storage.local.set({ darkAll: true }));
    await until(() => worker.evaluate(async () => (await chrome.scripting.getRegisteredContentScripts({ ids: ['savisul-dark'] })).length === 1), { label: 'dark css registered' });
    await page.close();
    await open(`${other}/dark`);
    const sites = await until(async () => {
      const value = await worker.evaluate(async () => (await chrome.storage.local.get('darkSites')).darkSites || {});
      return value['127.0.0.1'] ? value : null;
    }, { label: 'native site entry' });
    assert.equal(sites['127.0.0.1'], 'native');
    assert.equal(await page.evaluate(() => getComputedStyle(document.documentElement).filter.includes('invert')), false, 'dark site not inverted');
    await page.close();
    await open(`${local}/article`);
    assert.equal(await page.evaluate(() => getComputedStyle(document.documentElement).filter.includes('invert')), true, 'light site dark on load');
    const registered = await worker.evaluate(async () => (await chrome.scripting.getRegisteredContentScripts({ ids: ['savisul-dark'] }))[0]);
    assert.ok(registered.excludeMatches?.includes('*://127.0.0.1/*'), JSON.stringify(registered));
    await wait(500);
    await snap(page, 'dark-everywhere');
    await worker.evaluate(() => chrome.storage.local.set({ darkAll: false }));
    return `${JSON.stringify(sites)} exclude=${JSON.stringify(registered.excludeMatches)}`;
  });

  let capture;
  await step('full-page screenshot stitches every band once', async () => {
    await page.close();
    await open(`${local}/long`);
    await page.evaluate(() => window.scrollTo(0, 1200));
    const before = await page.evaluate(() => ({ y: scrollY, height: document.documentElement.scrollHeight, width: innerWidth }));
    const created = browser.waitForTarget((t) => t.url().includes('/pages/capture.html#'), { timeout: 45000 });
    await command('full-screenshot');
    const target = await created;
    capture = await target.page();
    capture.on('pageerror', (error) => problems.push(`pageerror on capture: ${error.message}`));
    await capture.bringToFront();
    const image = await until(() => capture.evaluate(() => {
      const img = document.querySelector('img.shot');
      return img && img.complete && img.naturalWidth ? { w: img.naturalWidth, h: img.naturalHeight, parts: document.querySelectorAll('img.shot').length } : null;
    }), { timeout: 30000, label: 'stitched image' });
    assert.equal(image.parts, 1);
    assert.equal(image.w, before.width * DPR);
    assert.equal(image.h, before.height * DPR);
    const bands = await page.evaluate(() => window.BANDS);
    const samples = await capture.evaluate(async (bands, dpr) => {
      const img = document.querySelector('img.shot');
      const canvas = new OffscreenCanvas(img.naturalWidth, img.naturalHeight);
      const context = canvas.getContext('2d');
      context.drawImage(img, 0, 0);
      const at = (x, y) => Array.from(context.getImageData(x * dpr, y * dpr, 1, 1).data.slice(0, 3));
      const hex = (rgb) => '#' + rgb.map((v) => v.toString(16).padStart(2, '0')).join('');
      return {
        header: hex(at(400, 30)),
        bands: bands.map((_, i) => hex(at(80, 64 + i * 500 + 250))),
        repeatedHeader: bands.map((_, i) => hex(at(400, 64 + i * 500 + 30))),
        chatMiddle: hex(at(img.naturalWidth / dpr - 52, 64 + 6 * 500 + 400)),
        chatEnd: hex(at(img.naturalWidth / dpr - 52, img.naturalHeight / dpr - 52))
      };
    }, bands, DPR);
    const near = (a, b) => {
      const x = a.match(/\w\w/g).map((v) => parseInt(v, 16));
      const y = b.match(/\w\w/g).map((v) => parseInt(v, 16));
      return x.every((v, i) => Math.abs(v - y[i]) < 14);
    };
    assert.ok(near(samples.header, '#111111'), `header ${samples.header}`);
    samples.bands.forEach((color, i) => assert.ok(near(color, bands[i]), `band ${i + 1}: ${color} vs ${bands[i]}`));
    samples.repeatedHeader.forEach((color, i) => assert.ok(near(color, bands[i]), `sticky header repeated over band ${i + 1}: ${color}`));
    assert.ok(near(samples.chatMiddle, bands[6]), `fixed chat bubble repeated mid-page: ${samples.chatMiddle}`);
    const after = await page.evaluate(() => scrollY);
    assert.equal(after, before.y, 'scroll position restored');
    await wait(900);
    await snap(capture, 'capture');
    return `${image.w}×${image.h}px, end chat ${samples.chatEnd}`;
  });

  await step('capture page saves the PNG into ~/Pictures/SAVISUL through the app', async () => {
    assert.ok(capture, 'capture page open');
    const label = await until(() => capture.evaluate(() => document.querySelectorAll('#actions button').length >= 3 && document.querySelector('#actions button')?.textContent), { label: 'save button' });
    await capture.click('#actions button');
    const toast = await until(() => capture.evaluate(() => document.querySelector('.toast')?.textContent || ''), { timeout: 20000, label: 'save toast' });
    const file = execFileSync('/bin/zsh', ['-c', `ls -t "$HOME/Pictures/SAVISUL"/*.png | head -1`]).toString().trim();
    assert.ok(existsSync(file), file);
    const age = Date.now() - Number(execFileSync('stat', ['-f', '%m', file]).toString()) * 1000;
    assert.ok(age < 30000, 'saved just now');
    savedFiles.push(file);
    await wait(400);
    await snap(capture, 'capture-saved');
    return `${label} → ${toast} (${path.basename(file)})`;
  });

  await step('options page shows tools, shortcuts and the Mac connection', async () => {
    const options = await browser.newPage();
    options.on('pageerror', (error) => problems.push(`pageerror on options: ${error.message}`));
    await options.goto(`chrome-extension://${ID}/pages/options.html`, { waitUntil: 'load' });
    const text = await until(() => options.evaluate(() => {
      const mac = document.querySelector('#mac');
      return mac?.querySelector('.status-dot.on') ? mac.textContent : '';
    }), { timeout: 10000, label: 'connected Mac status' });
    await wait(600);
    await snap(options, 'options');
    await options.evaluate(() => window.scrollTo(0, 900));
    await wait(400);
    await snap(options, 'options-tools');
    return text.replace(/\s+/g, ' ').slice(0, 140);
  });
  await step('home labels fit in every language', async () => {
    await page.close();
    await open(`${local}/article`);
    const report = [];
    for (const language of ['ru', 'uk', 'fr', 'en']) {
      await worker.evaluate((language) => chrome.storage.local.set({ language }), language);
      await until(() => sv(`SV_I18N.lang === '${language}'`), { label: `language ${language}` });
      await sv(`SV.notch.openHome()`);
      await until(() => sv(`SV.notch.view === 'home' && !!SV.root.querySelector('.mac-row')`), { label: 'home with mac row' });
      await wait(700);
      const clipped = await sv(`[...SV.root.querySelectorAll('.layer.on :is(.chip span, .mac-btn span, .tile .label, .section-title, .foot span)')]
        .filter((el) => el.scrollWidth > el.clientWidth + 1 || el.scrollHeight > el.clientHeight + 1).map((el) => el.textContent)`);
      report.push(`${language}: ${clipped.length ? clipped.join(', ') : 'ok'}`);
      await snap(page, `home-${language}`);
      assert.deepEqual(clipped, [], `${language} clipped: ${clipped.join(', ')}`);
    }
    await worker.evaluate(() => chrome.storage.local.set({ language: 'auto' }));
    return report.join(' · ');
  });
} finally {
  await browser.close().catch(() => {});
  server.close();
  await rm(profile, { recursive: true, force: true }).catch(() => {});
  for (const file of savedFiles) {
    try { unlinkSync(file); } catch {}
  }
}

for (const result of results) {
  console.log(`${result.ok ? 'PASS' : 'FAIL'}  ${result.name}  (${result.ms} ms)${result.detail ? `\n      ${result.detail}` : ''}`);
}
if (problems.length) {
  console.log(`\n${problems.length} console problem(s):`);
  for (const line of [...new Set(problems)].slice(0, 30)) console.log(`  - ${line}`);
}
console.log(`\nScreenshots: ${OUT}`);
process.exitCode = results.every((r) => r.ok) ? 0 : 1;
