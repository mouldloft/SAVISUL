import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import test from 'node:test';

const require = createRequire(import.meta.url);
const { cleanUrl, normalizeUrl, hostOf, isTracker } = require('../shared/urlclean.js');

test('utm parameters go, the real query stays', () => {
  const cleaned = cleanUrl('https://example.com/a?id=7&utm_source=news&utm_medium=email');
  assert.equal(cleaned.removed, 2);
  assert.equal(cleaned.url.includes('utm_'), false);
  assert.equal(cleaned.url.includes('id=7'), true);
});

test('fbclid and gclid go on any site', () => {
  const cleaned = cleanUrl('https://shop.test/item?fbclid=abc&gclid=def&color=red');
  assert.equal(cleaned.removed, 2);
  assert.match(cleaned.url, /color=red/);
  assert.equal(cleaned.url.includes('fbclid'), false);
  assert.equal(cleaned.url.includes('gclid'), false);
});

test('a useful query is not a tracker', () => {
  const cleaned = cleanUrl('https://example.com/search?q=savisul');
  assert.equal(cleaned.removed, 0);
  assert.match(cleaned.url, /q=savisul/);
});

test('mailto and junk are left alone', () => {
  assert.deepEqual(cleanUrl('mailto:hi@example.com?subject=Hi'), { url: 'mailto:hi@example.com?subject=Hi', removed: 0 });
  assert.equal(cleanUrl('not a url').removed, 0);
  assert.equal(cleanUrl('').removed, 0);
});

test('amazon tag and ref path go', () => {
  const cleaned = cleanUrl('https://www.amazon.com/dp/B00TEST/ref=sr_1_1?tag=savisul-20&psc=1');
  assert.ok(cleaned.removed >= 2);
  assert.equal(cleaned.url.includes('tag='), false);
  assert.equal(cleaned.url.includes('/ref='), false);
  assert.match(cleaned.url, /\/dp\/B00TEST/);
});

test('google search noise goes, the query stays', () => {
  const cleaned = cleanUrl('https://www.google.com/search?q=savisul&ved=abc&ei=xyz');
  assert.equal(cleaned.url.includes('ved='), false);
  assert.equal(cleaned.url.includes('ei='), false);
  assert.match(cleaned.url, /q=savisul/);
});

test('si is a tracker only on youtube, spotify and instagram', () => {
  assert.equal(isTracker('si', 'youtube.com'), true);
  assert.equal(isTracker('si', 'open.spotify.com'), true);
  assert.equal(isTracker('si', 'example.com'), false);
  assert.equal(isTracker('SI', 'music.youtube.com'), true);
});

test('utm hash and text-fragment hash go, an anchor stays', () => {
  assert.equal(cleanUrl('https://example.com/doc#utm_source=x').url.includes('#'), false);
  assert.equal(cleanUrl('https://example.com/doc#:~:text=hello').url.includes('#'), false);
  assert.match(cleanUrl('https://example.com/doc#install').url, /#install/);
});

test('normalize drops a trailing slash, www is kept in the host of the url but hostOf strips it', () => {
  const normalized = normalizeUrl('HTTPS://WWW.Example.com/path/?utm_source=a');
  assert.equal(normalized.startsWith('https://www.example.com/path'), true);
  assert.equal(normalized.endsWith('/'), false);
  assert.equal(normalized.includes('utm_'), false);
  assert.equal(hostOf('https://www.example.com/a'), 'example.com');
  assert.equal(hostOf('not a url'), '');
});

test('a hash router survives normalize', () => {
  const normalized = normalizeUrl('https://app.example.com/#/inbox');
  assert.match(normalized, /#\/inbox/);
});

test('empty and repeated tracker names are counted', () => {
  const cleaned = cleanUrl('https://example.com/?utm_a=1&utm_a=2&ok=1');
  assert.equal(cleaned.removed, 2);
  assert.match(cleaned.url, /ok=1/);
});
