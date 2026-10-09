// End-to-end check of the browser platform features (side panel, tabs, sessions, bookmarks, notes, AI,
// data, export, translation, CSS inspector, media, Shelf) in headless Chrome.
// Usage: node platform-test.mjs   (CHROME=..., HOST_BIN=..., ONLY=part,part)
import puppeteer from 'puppeteer-core';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { mkdtemp, mkdir, writeFile, rm, readdir, stat, readFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import assert from 'node:assert/strict';

const here = path.dirname(fileURLToPath(import.meta.url));
const EXTENSION = path.resolve(here, '../../Extension');
const OUT = path.join(here, 'out-platform');
const CHROME = process.env.CHROME || ['/Applications', path.join(os.homedir(), 'Applications'), path.join(os.homedir(), 'Desktop')]
  .map((dir) => path.join(dir, 'Google Chrome.app/Contents/MacOS/Google Chrome')).find(existsSync);
const HOST_BIN = process.env.HOST_BIN || '/Applications/SAVISUL.app/Contents/MacOS/SAVISUL';
const ID = 'cfgamdkhojfgnkklaojekgbpiclaapig';

// MARK: Fixtures

const paragraph = (n) => `Paragraph ${n}. When the last regional service leaves the platform, a different railway wakes up. Night trains run on timetables that look leisurely on paper, yet every minute of the schedule is negotiated with freight operators, track crews and the slow arithmetic of sleeping passengers who must arrive rested rather than early.`;

const fixtures = {
  '/article': () => `<!doctype html><html lang="en"><head><meta charset="utf-8"><title>The Quiet Engineering of Night Trains</title>
<meta property="og:title" content="The Quiet Engineering of Night Trains"><meta name="author" content="Mira Holt">
<style>body{margin:0;font:17px/1.6 Georgia,serif} main{max-width:720px;margin:40px auto;padding:0 24px} .card{padding:18px;border-radius:12px;background:#f4f0e8;box-shadow:0 4px 12px rgba(0,0,0,.15)}</style></head>
<body><main><article><h1>The Quiet Engineering of Night Trains</h1>
<p>${paragraph(1)} Read <a href="/timetable">the timetable</a> for <strong>details</strong>.</p>
<h2>Predictability beats speed</h2><p>${paragraph(2)}</p>
<blockquote>Passengers forgive a late arrival far more easily than a night spent bracing against the wall.</blockquote>
<p>${paragraph(3)}</p>
<pre><code class="language-text">turnaround = clean(35) + restock(40) + inspect(90)</code></pre>
<ul><li>Floors float on rubber mounts</li><li>Couplings are tensioned</li></ul>
<p>${paragraph(4)}</p><div class="card" id="card">A card worth capturing on its own.</div><p>${paragraph(5)}</p></article></main></body></html>`,

  '/data': () => `<!doctype html><html lang="en"><head><meta charset="utf-8"><title>Night train fares</title></head><body style="font:16px system-ui;padding:30px">
<h1>Fares</h1>
<table id="fares"><caption>Night trains 2026</caption><thead><tr><th>Route</th><th>Hours</th><th>Price</th></tr></thead>
<tbody><tr><td>Vienna – Paris</td><td>14</td><td>€89</td></tr><tr><td>Berlin – Stockholm</td><td>16</td><td>€99</td></tr><tr><td colspan="2">Zurich – Hamburg, via Basel</td><td>€79</td></tr></tbody></table>
<p>Questions: bookings@railway.example or +43 1 234 5678.</p>
<a href="https://other.example/x?utm_source=a&id=3">Partner</a> <a href="/local">Local page</a>
<video src="/clip.mp4" title="Depot tour"></video> <a href="/song.mp3">Soundtrack</a>
</body></html>`,

  '/second': () => '<!doctype html><html><head><meta charset="utf-8"><title>Second page</title></head><body><h1>Second</h1><p>Plain page.</p></body></html>'
};

// MARK: Harness

const results = [];
const problems = [];
let shotIndex = 0;
const ONLY = process.env.ONLY ? process.env.ONLY.split(',') : null;
const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function step(name, run) {
  if (ONLY && !ONLY.some((part) => name.includes(part)) && !name.startsWith('extension')) return;
  const started = Date.now();
  try {
    const detail = await run();
    results.push({ name, ok: true, ms: Date.now() - started, detail });
  } catch (error) {
    results.push({ name, ok: false, ms: Date.now() - started, detail: error?.stack?.split('\n').slice(0, 3).join(' | ') || String(error) });
  }
}

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
  await wait(650);
  const file = path.join(OUT, `${String(++shotIndex).padStart(2, '0')}-${name}.png`);
  await page.screenshot({ path: file });
  return file;
}

async function isolatedWorld(page) {
  const client = await page.createCDPSession();
  const contexts = new Map();
  client.on('Runtime.executionContextCreated', ({ context }) => contexts.set(context.id, context));
  client.on('Runtime.executionContextDestroyed', ({ executionContextId }) => contexts.delete(executionContextId));
  client.on('Runtime.executionContextsCleared', () => contexts.clear());
  client.on('Runtime.exceptionThrown', ({ exceptionDetails }) => {
    problems.push(`exception on ${page.url()}: ${exceptionDetails.exception?.description?.split('\n')[0] || exceptionDetails.text}`);
  });
  await client.send('Runtime.enable');
  const find = () => [...contexts.values()].find((c) => c.auxData?.type === 'isolated' && c.origin?.includes(ID) && c.auxData?.frameId === page.mainFrame()._id)
    || [...contexts.values()].find((c) => c.auxData?.type === 'isolated' && c.origin?.includes(ID));
  return async (expression) => {
    const context = await until(find, { timeout: 8000, label: 'isolated world' });
    const { result, exceptionDetails } = await client.send('Runtime.evaluate', { expression, contextId: context.id, returnByValue: true, awaitPromise: true, userGesture: true });
    if (exceptionDetails) throw new Error(exceptionDetails.exception?.description?.split('\n')[0] || exceptionDetails.text);
    return result.value;
  };
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
const local = `http://localhost:${server.address().port}`;

const profile = await mkdtemp(path.join(os.tmpdir(), 'savisul-platform-'));
const downloads = path.join(profile, 'Downloads');
await mkdir(path.join(profile, 'NativeMessagingHosts'), { recursive: true });
await mkdir(path.join(profile, 'Default'), { recursive: true });
await mkdir(downloads, { recursive: true });
await writeFile(path.join(profile, 'Default', 'Preferences'), JSON.stringify({ download: { default_directory: downloads, prompt_for_download: false, directory_upgrade: true } }));
await writeFile(path.join(profile, 'NativeMessagingHosts', 'com.savisul.bridge.json'), JSON.stringify({
  name: 'com.savisul.bridge', description: 'SAVISUL for Mac', path: HOST_BIN, type: 'stdio', allowed_origins: [`chrome-extension://${ID}/`]
}));

const browser = await puppeteer.launch({
  executablePath: CHROME, headless: true, pipe: true, enableExtensions: true, userDataDir: profile, defaultViewport: null,
  args: ['--window-size=1280,860', '--force-device-scale-factor=2', '--no-first-run', '--no-default-browser-check', '--lang=en', '--hide-crash-restore-bubble']
});

let worker;
let page;
let sv;

async function open(url) {
  page = await browser.newPage();
  page.on('pageerror', (error) => problems.push(`pageerror on ${url}: ${error.message}`));
  await page.goto(url, { waitUntil: 'load' });
  await page.bringToFront();
  sv = await isolatedWorld(page);
  await until(() => sv('!!(globalThis.SV && SV.alive && SV.root)'), { label: 'notch mounted' });
  return page;
}

async function files(ext) {
  const list = [];
  const walk = async (dir) => {
    for (const entry of await readdir(dir, { withFileTypes: true }).catch(() => [])) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) await walk(full);
      else if (full.endsWith(ext)) list.push({ file: full, size: (await stat(full)).size });
    }
  };
  await walk(downloads);
  return list;
}

async function sidebarPage() {
  const sb = await browser.newPage();
  sb.on('pageerror', (error) => problems.push(`pageerror on sidebar: ${error.message}`));
  sb.on('console', (message) => { if (message.type() === 'error') problems.push(`sidebar console: ${message.text()}`); });
  await sb.setViewport({ width: 420, height: 860, deviceScaleFactor: 2 });
  await sb.goto(`chrome-extension://${ID}/pages/sidebar.html`, { waitUntil: 'load' });
  await until(() => sb.evaluate(() => !!document.querySelector('.sb-nav button')), { label: 'sidebar nav' });
  return sb;
}

try {
  await step('extension installs and the worker starts cleanly', async () => {
    const id = await browser.installExtension(EXTENSION);
    assert.equal(id, ID);
    const target = await browser.waitForTarget((t) => t.type() === 'service_worker' && t.url().startsWith(`chrome-extension://${ID}/`), { timeout: 10000 });
    worker = await target.worker();
    worker.on('console', (message) => { if (['error', 'warn'].includes(message.type())) problems.push(`worker ${message.type()}: ${message.text()}`); });
    const info = await worker.evaluate(async () => ({
      handlers: Object.keys(handlers).filter((k) => /sidebar|archive|shelf|print|blob/.test(k)),
      menus: typeof buildMenus, sidePanel: typeof chrome.sidePanel?.open
    }));
    assert.deepEqual(info.handlers.sort(), ['archive:save', 'blob:download', 'print:open', 'shelf:add', 'sidebar:open'].sort());
    await worker.evaluate(() => scheduleSuspend());
    const alarm = await until(() => worker.evaluate(() => chrome.alarms.get('savisul-suspend')), { label: 'suspend alarm' });
    return `${info.handlers.length} handlers · alarm every ${alarm.periodInMinutes} min · sidePanel ${info.sidePanel}`;
  });

  await step('home shows the new tools and the Browser section in every language', async () => {
    await open(`${local}/article`);
    const report = [];
    for (const language of ['en', 'ru', 'uk', 'fr']) {
      await worker.evaluate((language) => chrome.storage.local.set({ language }), language);
      await until(() => sv(`SV_I18N.lang === '${language}'`), { label: `language ${language}` });
      await sv('SV.notch.openHome()');
      await until(() => sv(`SV.notch.view === 'home'`), { label: 'home' });
      await wait(500);
      const info = await sv(`({
        tiles: [...SV.root.querySelectorAll('.layer.on .tile .label')].map((n) => n.textContent),
        browser: SV.root.querySelectorAll('.layer.on .section')[2]?.querySelectorAll('.chip').length,
        clipped: [...SV.root.querySelectorAll('.layer.on :is(.chip span, .tile .label, .section-title)')].filter((el) => el.scrollWidth > el.clientWidth + 1).map((el) => el.textContent),
        height: Math.round(SV.root.querySelector('.layer.home').getBoundingClientRect().height)
      })`);
      assert.equal(info.tiles.length, 15, info.tiles.join(','));
      assert.equal(info.browser, 6);
      assert.deepEqual(info.clipped, [], `${language} clipped ${info.clipped.join(', ')}`);
      report.push(`${language}: ${info.tiles.length} tiles, ${info.height}px`);
      await snap(page, `home-${language}`);
    }
    await worker.evaluate(() => chrome.storage.local.set({ language: 'en' }));
    await sv('SV.notch.close()');
    return report.join(' · ');
  });

  await step('page exports to clean Markdown', async () => {
    const md = await sv('SV.pageMarkdown().text');
    await writeFile(path.join(OUT, 'article.md'), md);
    for (const needle of ['# The Quiet Engineering of Night Trains', '## Predictability beats speed', '> Passengers forgive', '```\n', '- Floors float on rubber mounts', `[the timetable](${local}/timetable)`, '**details**']) {
      assert.ok(md.includes(needle), `missing ${needle}\n${md.slice(0, 600)}`);
    }
    return `${md.length} chars · ${md.split('\n').length} lines`;
  });

  await step('Markdown download and web archive land in Downloads', async () => {
    await sv(`SV.notch.openPanel('export', { direct: true })`);
    await until(() => sv(`!!SV.root.querySelector('.option-row')`), { label: 'export panel' });
    await snap(page, 'export-panel');
    await sv(`SV.root.querySelector('.option-row .option').click()`);
    const md = await until(async () => (await files('.md'))[0], { label: 'markdown file', timeout: 8000 });
    await sv(`SV.send('archive:save', { target: 'download', name: 'night-trains' })`);
    const archive = await until(async () => (await files('.mhtml'))[0], { label: 'mhtml file', timeout: 12000 }).catch(async (error) => {
      const state = await worker.evaluate(() => chrome.downloads.search({ limit: 5, orderBy: ['-startTime'] }));
      throw new Error(`${error.message} downloads=${JSON.stringify(state.map((d) => ({ f: d.filename, s: d.state, danger: d.danger, err: d.error, url: d.url.slice(0, 40) })))}`);
    });
    assert.ok(archive.size > 2000, `archive ${archive.size} bytes`);
    const head = (await readFile(archive.file, 'utf8')).slice(0, 400);
    assert.ok(/multipart\/related/i.test(head), 'mhtml header');
    return `${path.basename(md.file)} ${md.size} B · ${path.basename(archive.file)} ${archive.size} B`;
  });

  await step('PDF opens a clean printable copy', async () => {
    const before = (await browser.pages()).length;
    await sv(`SV.send('print:open', { doc: { title: 'The Quiet Engineering of Night Trains', site: 'Railway Review', url: location.href, lang: 'en', html: SV.reader.extract().body.innerHTML } })`);
    const print = await until(async () => (await browser.pages()).find((p) => p.url().includes('/pages/print.html')), { label: 'print tab' });
    await until(() => print.evaluate(() => document.querySelector('h1.title')?.textContent), { label: 'print title' });
    const info = await print.evaluate(() => ({ title: document.querySelector('h1.title').textContent, paragraphs: document.querySelectorAll('#doc p').length, scripts: document.querySelectorAll('#doc script').length }));
    await snap(print, 'print');
    await print.close();
    assert.ok(info.paragraphs >= 5);
    assert.equal(info.scripts, 0);
    return `${(await browser.pages()).length - before} new tab closed · ${info.paragraphs} paragraphs`;
  });

  await step('CSS inspector reads styles and shoots a single element', async () => {
    await page.bringToFront();
    await sv(`SV.runTool('inspect')`);
    await wait(150);
    await page.$eval('#card', (el) => el.scrollIntoView({ block: 'center' }));
    await wait(200);
    const card = await page.$('#card');
    const box = await card.boundingBox();
    await page.mouse.move(box.x + 20, box.y + 10, { steps: 4 });
    const text = await until(() => sv(`SV.root.querySelector('.css-card')?.textContent || ''`), { label: 'css card' }).catch(async (error) => {
      const debug = await sv(`({ active: SV.tools.inspect.active(), mode: SV.notch.mode?.id, view: SV.notch.view, layers: SV.root.querySelectorAll('.fonts-layer').length, at: document.elementFromPoint(${Math.round(box.x + 20)}, ${Math.round(box.y + 10)})?.id, vis: document.visibilityState })`);
      throw new Error(`${error.message} ${JSON.stringify(debug)}`);
    });
    assert.ok(text.includes('div#card.card'), text);
    await snap(page, 'inspect');
    const css = await sv(`SV.inspect.cssFor(document.querySelector('#card'))`);
    assert.ok(/border-radius: 12px/.test(css) && /background-color: #F4F0E8/i.test(css), css);
    await sv(`SV.inspect.stop()`);
    const pagesBefore = (await browser.pages()).length;
    await sv(`SV.inspect.shootElement(document.querySelector('#card'))`);
    const capture = await until(async () => (await browser.pages()).find((p) => p.url().includes('/pages/capture.html')), { label: 'capture tab', timeout: 8000 });
    await wait(800);
    await snap(capture, 'element-shot');
    const size = await capture.evaluate(() => document.querySelector('.size, .meta, header')?.textContent || document.body.innerText.slice(0, 120));
    await capture.close();
    await page.bringToFront();
    return `${css.split('\n').length - 2} declarations · capture: ${size.replace(/\s+/g, ' ').slice(0, 60)} · tabs ${pagesBefore}`;
  });

  await step('data panel finds the table, links and contacts', async () => {
    await page?.close();
    await worker.evaluate(() => chrome.storage.local.set({ language: 'en' }));
    await open(`${local}/data`);
    await sv(`SV.notch.openPanel('tables', { direct: true })`);
    const hint = await until(() => sv(`SV.root.querySelector('.data-card .hint')?.textContent || ''`), { label: 'table card' });

    assert.ok(/4 rows × 3 columns/.test(hint), hint);
    await snap(page, 'data-tables');
    await sv(`SV.root.querySelectorAll('.layer.panel .seg button')[1].click()`);
    const links = await until(() => sv(`[...SV.root.querySelectorAll('.link-row')].map((a) => a.href)`), { label: 'links' });
    assert.ok(links.includes('https://other.example/x?id=3'), links.join(' '));
    await sv(`SV.root.querySelectorAll('.layer.panel .seg button')[2].click()`);
    const contacts = await until(() => sv(`[...SV.root.querySelectorAll('.link-row .mono')].map((n) => n.textContent)`), { label: 'contacts' });
    assert.ok(contacts.includes('bookings@railway.example') && contacts.some((c) => c.includes('234 5678')), contacts.join(' | '));
    return `${hint} · ${links.length} links · ${contacts.join(', ')}`;
  });

  await step('media panel lists the video and the audio link', async () => {
    await sv(`SV.notch.openPanel('media', { direct: true })`);
    const rows = await until(() => sv(`[...SV.root.querySelectorAll('.media-row .hint')].map((n) => n.textContent)`), { label: 'media rows' });
    assert.equal(rows.length, 2, rows.join(' | '));
    await snap(page, 'media');
    return rows.join(' | ');
  });

  await step('translate panel reports how it will translate', async () => {
    await sv(`SV.notch.openPanel('translate', { direct: true })`);
    const info = await until(() => sv(`({ api: typeof Translator, status: SV.root.querySelector('.layer.panel .hint')?.textContent })`), { label: 'translate status' });
    await snap(page, 'translate');
    await sv('SV.notch.close()');
    return `Translator ${info.api} · ${info.status}`;
  });

  await step('Shelf hand-off reports a clear reason when the Mac app can’t take it', async () => {
    const reply = await sv(`SV.send('shelf:add', { kind: 'link', url: location.href, title: document.title }).then(() => 'ok', (e) => e.message)`);
    assert.ok(['ok', 'update', 'offline', 'missing'].includes(reply), reply);
    return `shelf:add → ${reply}`;
  });

  // MARK: Side panel

  let sb;
  await step('sidebar lists tabs, finds the duplicate and closes it', async () => {
    await worker.evaluate(async (urls) => { for (const url of urls) await chrome.tabs.create({ url, active: false }); }, [`${local}/second`, `${local}/second`]);
    sb = await sidebarPage();
    const dupes = await until(() => sb.evaluate(() => document.querySelector('.toolbar .count')?.textContent), { label: 'duplicate count' });
    assert.equal(dupes, '1');
    await snap(sb, 'sidebar-tabs');
    await sb.evaluate(() => [...document.querySelectorAll('.toolbar .btn')].find((b) => b.querySelector('.count')).click());
    await until(async () => (await worker.evaluate((u) => chrome.tabs.query({ url: u }), `${local}/second`)).length === 1, { label: 'one copy left' });
    return `duplicates ${dupes} → closed`;
  });

  await step('sidebar groups tabs by site and puts others to sleep', async () => {
    await worker.evaluate(async (url) => { await chrome.tabs.create({ url, active: false }); }, `${local}/article`);
    await wait(600);
    await sb.evaluate(() => [...document.querySelectorAll('.toolbar .btn')][0].click());
    const groups = await until(async () => {
      const list = await worker.evaluate(() => chrome.tabGroups.query({}));
      return list.length ? list : null;
    }, { label: 'tab group' });
    await until(() => sb.evaluate(() => document.querySelectorAll('.tgroup').length), { label: 'group rendered' });
    await snap(sb, 'sidebar-groups');
    await sb.evaluate(() => [...document.querySelectorAll('.toolbar .btn')].find((b) => b.textContent.includes('Sleep')).click());
    const asleep = await until(async () => (await worker.evaluate(() => chrome.tabs.query({ discarded: true }))).length, { label: 'discarded tabs', timeout: 8000 });
    return `${groups.length} group(s) “${groups[0].title}” · ${asleep} asleep`;
  });

  await step('auto-suspend puts idle tabs to sleep', async () => {
    const waked = await worker.evaluate(async (url) => (await chrome.tabs.create({ url, active: false })).id, `${local}/second`);
    await wait(2500);
    await worker.evaluate(async () => {
      await chrome.storage.local.set({ suspendAfter: 0.02 });
      await suspendIdle();
    });
    const tab = await until(async () => {
      const list = await worker.evaluate((url) => chrome.tabs.query({ url, discarded: true }), `${local}/second`);
      return list[0] || null;
    }, { label: 'auto discarded', timeout: 6000 });
    await worker.evaluate(() => chrome.storage.local.set({ suspendAfter: 0 }));
    return `tab ${tab.id} discarded after idle`;
  });

  await step('sessions save the window and restore it', async () => {
    await sb.evaluate(() => [...document.querySelectorAll('.sb-nav button')][1].click());
    await until(() => sb.evaluate(() => !!document.querySelector('.card.pad .btn.primary')), { label: 'sessions view' });
    await sb.evaluate(() => { document.querySelector('.card.pad input').value = 'Night trains research'; document.querySelector('.card.pad .btn.primary').click(); });
    const saved = await until(async () => (await worker.evaluate(() => chrome.storage.local.get('sessions'))).sessions?.[0], { label: 'saved session' });
    await until(() => sb.evaluate(() => document.querySelector('.session .name')?.textContent), { label: 'session card' });
    await snap(sb, 'sidebar-sessions');
    const windowsBefore = (await worker.evaluate(() => chrome.windows.getAll())).length;
    await sb.evaluate(() => document.querySelector('.session .btn.primary').click());
    await until(async () => (await worker.evaluate(() => chrome.windows.getAll())).length > windowsBefore, { label: 'restored window' });
    return `“${saved.name}” · ${saved.count} tabs restored into a new window`;
  });

  await step('bookmarks: add the current tab, search, find duplicates', async () => {
    await worker.evaluate(async (url) => {
      await chrome.bookmarks.create({ title: 'Fares A', url });
      await chrome.bookmarks.create({ title: 'Fares B', url });
    }, `${local}/data`);
    await sb.evaluate(() => [...document.querySelectorAll('.sb-nav button')][2].click());
    await until(() => sb.evaluate(() => !!document.querySelector('.search input')), { label: 'bookmarks view' });
    await sb.type('.search input', 'Fares');
    const found = await until(() => sb.evaluate(() => document.querySelectorAll('.item .title').length), { label: 'search results' });
    await sb.evaluate(() => { const i = document.querySelector('.search input'); i.value = ''; i.dispatchEvent(new Event('input')); });
    await sb.evaluate(() => [...document.querySelectorAll('.toolbar .btn')][0].click());
    const title = await until(() => sb.evaluate(() => [...document.querySelectorAll('.sb-body span')].map((s) => s.textContent).find((t) => /Duplicate bookmarks/.test(t))), { label: 'duplicates' });
    await snap(sb, 'sidebar-bookmarks');
    return `${found} found · ${title}`;
  });

  await step('notes view lists notes from every page', async () => {
    await worker.evaluate(async (url) => {
      await chrome.storage.local.set({ [`note:${url}`]: { scope: 'page', text: 'Compare with the Vienna sleeper.', url, host: 'localhost', title: 'Fares', created: Date.now(), updated: Date.now() } });
    }, `${local}/data`);
    await sb.evaluate(() => [...document.querySelectorAll('.sb-nav button')][3].click());
    const titles = await until(() => sb.evaluate(() => [...document.querySelectorAll('.list .item .title')].map((n) => n.textContent)), { label: 'notes list' });
    assert.ok(titles.some((t) => t.includes('Vienna sleeper')), titles.join(' | '));
    await snap(sb, 'sidebar-notes');
    return titles.join(' | ');
  });

  await step('AI view: setup, then a real SDK call reports a rejected key', async () => {
    await sb.evaluate(() => [...document.querySelectorAll('.sb-nav button')][4].click());
    await until(() => sb.evaluate(() => !!document.querySelector('input[type="password"]')), { label: 'AI setup card' });
    await snap(sb, 'sidebar-ai-setup');
    await sb.type('input[type="password"]', 'sk-ant-api03-invalid-test-key');
    await sb.evaluate(() => [...document.querySelectorAll('.btn.primary')].find((b) => b.textContent.includes('Save')).click());
    await until(() => sb.evaluate(() => !!document.querySelector('.composer textarea')), { label: 'composer' });
    await sb.evaluate(() => [...document.querySelectorAll('.seg button')][2].click());
    await wait(300);
    await sb.evaluate(() => [...document.querySelectorAll('.chip')][0].click());
    const error = await until(() => sb.evaluate(() => document.querySelector('.msg.error')?.textContent), { label: 'AI error', timeout: 30000 });
    const context = await sb.evaluate(() => document.querySelector('.msg.user .ctx')?.textContent);
    await snap(sb, 'sidebar-ai-error');
    assert.ok(/rejected the API key|Couldn’t reach/.test(error), error);
    await worker.evaluate(() => chrome.storage.local.remove('aiKey'));
    return `context “${context}” · ${error}`;
  });

  await step('sync: language follows the Mac app, an explicit choice wins', async () => {
    await open(`${local}/second`);
    const stored = await worker.evaluate(() => chrome.storage.local.get(['languageFollowsMac', 'appLanguage']));
    assert.equal(stored.languageFollowsMac, true, 'first install should follow the Mac app');
    // The live app keeps reporting its own language; hold it off and feed the sync by hand.
    await worker.evaluate(() => {
      globalThis.realSync ??= syncAppLanguage;
      globalThis.syncAppLanguage = () => {};
      return chrome.storage.local.set({ language: 'auto' });
    });
    await worker.evaluate(() => realSync({ app: { language: 'fr' } }));
    await until(() => sv(`SV_I18N.lang === 'fr'`), { label: 'page notch in French' });
    const menu = await until(() => worker.evaluate(() => I18N.lang), { label: 'worker language' });
    await worker.evaluate(() => chrome.storage.local.set({ language: 'uk' }));
    await until(() => sv(`SV_I18N.lang === 'uk'`), { label: 'explicit Ukrainian wins' });
    await worker.evaluate(() => chrome.storage.local.set({ language: 'auto' }));
    await until(() => sv(`SV_I18N.lang === 'fr'`), { label: 'back to the Mac language' });
    await worker.evaluate(() => realSync({ app: { language: 'en' } }));
    await until(() => sv(`SV_I18N.lang === 'en'`), { label: 'Mac switched to English' });
    await page.close();
    return `installed: follows Mac · Mac fr → page fr, menus ${menu} · explicit uk wins · auto → fr · Mac en → en (Mac reported ${stored.appLanguage || 'nothing'})`;
  });

  let welcome;
  const demoFrame = () => welcome.frames().find((f) => f.url().endsWith('/pages/demo.html'));
  const demoState = () => demoFrame().evaluate(() => globalThis.SAVISUL_DEMO?.state());

  await step('welcome page: English by default with a live, clickable demo', async () => {
    // From here on the test drives the Mac language itself; the real app may be running in any language.
    await worker.evaluate(async () => {
      globalThis.syncAppLanguage = () => {};
      await chrome.storage.local.set({ language: 'auto' });
      await chrome.storage.local.remove('appLanguage');
    });
    welcome = await browser.newPage();
    welcome.on('pageerror', (error) => problems.push(`pageerror on welcome: ${error.message}`));
    welcome.on('console', (message) => { if (message.type() === 'error') problems.push(`welcome console: ${message.text()}`); });
    await welcome.setViewport({ width: 1440, height: 900, deviceScaleFactor: 2 });
    await welcome.goto(`chrome-extension://${ID}/pages/options.html#welcome`, { waitUntil: 'load' });
    const heading = await until(() => welcome.evaluate(() => document.querySelector('.hero h1')?.textContent), { label: 'hero' });
    assert.equal(await welcome.evaluate(() => document.documentElement.lang), 'en');
    await until(() => demoFrame()?.evaluate(() => !!globalThis.SAVISUL_DEMO?.ready()), { label: 'demo notch', timeout: 10000 });
    await until(() => welcome.evaluate(() => document.querySelector('.demo-loading').hidden), { label: 'demo loaded' });
    const overflow = await welcome.evaluate(() => document.documentElement.scrollWidth - innerWidth);
    assert.ok(overflow <= 0, `page scrolls sideways by ${overflow}px`);
    await snap(welcome, 'welcome-hero');

    const click = (id) => welcome.evaluate((id) => {
      const button = document.querySelector(`.step[data-step="${id}"]`);
      button.scrollIntoView({ block: 'center' });
      button.click();
    }, id);
    const seen = [];
    await welcome.evaluate(() => document.getElementById('demo').scrollIntoView());
    await click('notch');
    await until(async () => (await demoState()).view === 'home', { label: 'demo home' });
    assert.equal(await welcome.evaluate(() => document.querySelector('.step[aria-pressed="true"]')?.dataset.step), 'notch');
    seen.push('notch → home');
    await snap(welcome, 'welcome-demo-notch');

    await click('reader');
    await until(async () => (await demoState()).reader, { label: 'demo reader' });
    seen.push('reader on');
    await snap(welcome, 'welcome-demo-reader');

    await click('data');
    await until(async () => (await demoState()).panel === 'tables', { label: 'demo data panel' });
    assert.equal((await demoState()).reader, false, 'reader should close for the data panel');
    const found = await until(() => demoFrame().evaluate(() => SV.root.querySelector('.layer.on')?.textContent.includes('Night trains, autumn 2026')), { label: 'fares table found' });
    seen.push(`data panel finds the fares table (${found})`);
    await snap(welcome, 'welcome-demo-data');

    await click('dark');
    await until(async () => (await demoState()).dark, { label: 'demo dark' });
    const darkSaved = await worker.evaluate(() => chrome.storage.local.get('darkSites'));
    assert.ok(!Object.keys(darkSaved.darkSites || {}).some((host) => /^[a-p]{32}$/.test(host)), 'demo dark must stay local');
    seen.push('dark on, not saved');
    await snap(welcome, 'welcome-demo-dark');

    await click('inspect');
    await until(async () => (await demoState()).inspect, { label: 'demo inspector' });
    seen.push('inspector on');
    await snap(welcome, 'welcome-demo-inspect');

    for (const id of ['translate', 'export', 'notes']) {
      await click(id);
      await until(async () => (await demoState()).panel === (id === 'notes' ? 'notes' : id), { label: `demo ${id}` });
      seen.push(id);
    }
    await snap(welcome, 'welcome-demo-notes');

    await welcome.evaluate(() => [...document.querySelectorAll('.demo-side .btn')].at(-1).click());
    await until(async () => demoFrame() && (await demoFrame().evaluate(() => !!globalThis.SAVISUL_DEMO?.ready())) && !(await demoState()).dark, { label: 'demo reset', timeout: 10000 });
    seen.push('reset');
    return `“${heading}” · ${seen.join(' · ')}`;
  });

  await step('welcome page follows the Mac language and the sync toggle', async () => {
    await welcome.evaluate(() => document.getElementById('top').scrollIntoView());
    await worker.evaluate(() => chrome.storage.local.set({ language: 'auto', appLanguage: 'fr' }));
    const french = await until(() => welcome.evaluate(() => document.documentElement.lang === 'fr' && document.querySelector('.hero h1')?.textContent), { label: 'welcome in French' });
    await until(() => demoFrame()?.evaluate(() => SV_I18N.lang === 'fr'), { label: 'demo notch in French' });
    const source = await welcome.evaluate(() => document.querySelector('#mac .status-value')?.textContent);
    assert.ok(source.includes('Français'), source);
    await snap(welcome, 'welcome-fr');
    await welcome.evaluate(() => document.getElementById('mac').scrollIntoView({ block: 'center' }));
    await snap(welcome, 'welcome-fr-mac');

    // Turning “Follow the Mac app” off pins the current language.
    await welcome.evaluate(() => document.querySelector('#mac .follow input, #mac .follow [role="switch"], #mac .follow button')?.click());
    const pinned = await until(async () => (await worker.evaluate(() => chrome.storage.local.get('language'))).language === 'fr' && 'fr', { label: 'pinned French' });
    await worker.evaluate(() => chrome.storage.local.set({ appLanguage: 'en' }));
    await wait(500);
    assert.equal(await welcome.evaluate(() => document.documentElement.lang), 'fr', 'pinned language should ignore the Mac');
    await worker.evaluate(() => chrome.storage.local.set({ language: 'auto' }));
    const back = await until(() => welcome.evaluate(() => document.documentElement.lang === 'en' && document.querySelector('.hero h1')?.textContent), { label: 'back to English' });
    await welcome.setViewport({ width: 1440, height: 900, deviceScaleFactor: 1 });
    await wait(400);
    await welcome.screenshot({ path: path.join(OUT, 'welcome-full.png'), fullPage: true });
    await welcome.setViewport({ width: 1440, height: 900, deviceScaleFactor: 2 });
    return `fr: “${french}” · source “${source}” · toggle pinned ${pinned} · auto → “${back}”`;
  });

  await step('welcome page on a phone-sized window', async () => {
    await welcome.setViewport({ width: 390, height: 844, deviceScaleFactor: 3, isMobile: false });
    await welcome.evaluate(() => scrollTo(0, 0));
    await wait(300);
    const overflow = await welcome.evaluate(() => document.documentElement.scrollWidth - innerWidth);
    const wide = await welcome.evaluate(() => [...document.querySelectorAll('#app *')].filter((el) => {
      const r = el.getBoundingClientRect();
      return r.width && r.right > innerWidth + 1 && !el.closest('.demo-steps');
    }).slice(0, 5).map((el) => `${el.tagName.toLowerCase()}.${el.className}`));
    await snap(welcome, 'welcome-phone-hero');
    await welcome.evaluate(() => document.getElementById('demo').scrollIntoView());
    await snap(welcome, 'welcome-phone-demo');
    await welcome.evaluate(() => document.getElementById('mac').scrollIntoView());
    await snap(welcome, 'welcome-phone-mac');
    assert.ok(overflow <= 0 && !wide.length, `overflow ${overflow}px: ${wide.join(', ')}`);
    return 'no sideways scroll at 390px';
  });
} finally {
  await browser.close().catch(() => {});
  server.close();
  await rm(profile, { recursive: true, force: true }).catch(() => {});
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
