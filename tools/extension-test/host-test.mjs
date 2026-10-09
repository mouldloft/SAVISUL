// Talks to the SAVISUL native messaging host the same way Chrome does.
// Usage: node host-test.mjs [path-to-SAVISUL-binary]
import { spawn, execFileSync } from 'node:child_process';
import { readFileSync, unlinkSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname } from 'node:path';
import assert from 'node:assert/strict';

const binary = process.argv[2] || '/Applications/SAVISUL.app/Contents/MacOS/SAVISUL';
const origin = 'chrome-extension://cfgamdkhojfgnkklaojekgbpiclaapig/';

function open() {
  const child = spawn(binary, [origin], { stdio: ['pipe', 'pipe', 'inherit'] });
  const waiters = new Map();
  const pushes = [];
  let buffer = Buffer.alloc(0);
  let seq = 0;
  child.stdout.on('data', (chunk) => {
    buffer = Buffer.concat([buffer, chunk]);
    while (buffer.length >= 4) {
      const length = buffer.readUInt32LE(0);
      if (buffer.length < 4 + length) break;
      const message = JSON.parse(buffer.subarray(4, 4 + length).toString('utf8'));
      buffer = buffer.subarray(4 + length);
      const waiter = waiters.get(message.id);
      if (waiter) { waiters.delete(message.id); waiter(message); } else pushes.push(message);
    }
  });
  const send = (object) => {
    const body = Buffer.from(JSON.stringify(object));
    const head = Buffer.alloc(4);
    head.writeUInt32LE(body.length);
    child.stdin.write(Buffer.concat([head, body]));
  };
  const request = (body, timeout = 8000) => new Promise((resolve, reject) => {
    const id = ++seq;
    const timer = setTimeout(() => { waiters.delete(id); reject(new Error(`timeout: ${body.type}`)); }, timeout);
    waiters.set(id, (message) => { clearTimeout(timer); resolve(message); });
    send({ ...body, id });
  });
  const exited = new Promise((resolve) => child.on('exit', (code, signal) => resolve({ code, signal })));
  return { child, request, pushes, exited, close: () => child.stdin.end() };
}

const results = [];
async function step(name, run) {
  const started = Date.now();
  try {
    const detail = await run();
    results.push({ name, ok: true, ms: Date.now() - started, detail });
  } catch (error) {
    results.push({ name, ok: false, ms: Date.now() - started, detail: error.message });
  }
}

const appRunning = () => {
  try { return execFileSync('pgrep', ['-f', 'SAVISUL.app/Contents/MacOS/SAVISUL$']).toString().trim().length > 0; } catch { return false; }
};

const host = open();

await step('hello returns app state', async () => {
  const reply = await host.request({ type: 'hello' });
  assert.equal(reply.state?.app?.running, true, JSON.stringify(reply));
  assert.ok(reply.state.app.version, 'version');
  assert.ok(['en', 'ru', 'uk', 'fr'].includes(reply.state.app.language));
  return `v${reply.state.app.version}, ${reply.state.app.language}`;
});

let state;
await step('state has every section', async () => {
  const reply = await host.request({ type: 'state' });
  state = reply.state;
  for (const key of ['app', 'lid', 'idle', 'audio', 'battery']) assert.ok(state[key], `missing ${key}`);
  assert.equal(typeof state.lid.on, 'boolean');
  assert.equal(typeof state.audio.hasVolume, 'boolean');
  assert.equal(typeof state.memory, 'number');
  return `lid=${state.lid.on} idle=${state.idle.on} audio=${state.audio.device ?? '-'} ${state.audio.volume?.toFixed?.(2) ?? ''} battery=${state.battery.present ? Math.round(state.battery.percent) + '%' : 'none'} cpu=${state.cpu?.toFixed?.(1) ?? '?'} mem=${state.memory.toFixed(0)}%`;
});

await step('mute set to its current value is a no-op', async () => {
  const reply = await host.request({ type: 'set', key: 'mute', value: !!state?.audio?.muted });
  assert.equal(reply.ok, true, JSON.stringify(reply));
  assert.equal(reply.state.audio.muted, !!state?.audio?.muted);
  return `muted stays ${reply.state.audio.muted}`;
});

await step('unknown request is rejected', async () => {
  const reply = await host.request({ type: 'nope' });
  assert.equal(reply.error, 'unknown');
});

await step('reveal refuses paths outside ~/Pictures/SAVISUL', async () => {
  const reply = await host.request({ type: 'reveal', path: '/etc/hosts' });
  assert.equal(reply.error, 'path');
});

await step('screenshot arrives in chunks and lands in ~/Pictures/SAVISUL', async () => {
  const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAFklEQVR4nGP8z8Dwn4GBgYGJAQoAAB0FAgFrUK1PAAAAAElFTkSuQmCC', 'base64');
  const token = `test-${Date.now()}`;
  const parts = [png.subarray(0, 30), png.subarray(30)];
  let reply;
  for (let index = 0; index < parts.length; index++) {
    reply = await host.request({ type: 'saveChunk', token, index, total: parts.length, name: 'SAVISUL bridge test/../x.png', data: parts[index].toString('base64') });
    assert.equal(reply.ok, true, JSON.stringify(reply));
  }
  assert.ok(reply.path?.endsWith('.png'), reply.path);
  assert.equal(dirname(reply.path), `${homedir()}/Pictures/SAVISUL`, 'stays inside the folder');
  assert.ok(readFileSync(reply.path).equals(png), 'bytes match');
  unlinkSync(reply.path);
  return reply.path.split('/').pop();
});

await step('bad chunk is rejected', async () => {
  const reply = await host.request({ type: 'saveChunk', token: 'x', index: 3, total: 2, data: 'AAAA' });
  assert.equal(reply.error, 'chunk');
});

await step('host exits when the browser closes the pipe', async () => {
  host.close();
  const result = await Promise.race([host.exited, new Promise((resolve) => setTimeout(() => resolve('still running'), 3000))]);
  assert.deepEqual(result, { code: 0, signal: null });
});

if (process.env.TEST_LAUNCH === '1') {
  await step('launch starts SAVISUL in the background', async () => {
    execFileSync('pkill', ['-TERM', '-f', 'SAVISUL.app/Contents/MacOS/SAVISUL$']);
    for (let i = 0; i < 40 && appRunning(); i++) await new Promise((r) => setTimeout(r, 100));
    assert.equal(appRunning(), false, 'app stopped');
    const second = open();
    const offline = await second.request({ type: 'state' });
    assert.equal(offline.state?.app?.running, false, JSON.stringify(offline));
    const started = Date.now();
    const reply = await second.request({ type: 'launch' }, 16000);
    assert.equal(reply.state?.app?.running, true, JSON.stringify(reply));
    second.close();
    return `running after ${Date.now() - started} ms`;
  });
}

for (const result of results) {
  console.log(`${result.ok ? 'PASS' : 'FAIL'}  ${result.name}  (${result.ms} ms)${result.detail ? `  — ${result.detail}` : ''}`);
}
process.exitCode = results.every((r) => r.ok) ? 0 : 1;
