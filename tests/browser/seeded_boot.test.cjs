'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { makeSeededBoot, isFightSave, isPostVictorySave } = require('./seeded_boot.cjs');

function harness(attemptStates) {
  const events = [];
  const pages = [];
  const seed = { version: 2, flags: { goliath_down: true }, settings: { sound: true } };
  const reads = new Map();
  const context = {
    async newPage() {
      const id = pages.length + 1;
      const page = {
        id,
        closed: false,
        async goto(url) { events.push(`${id}:goto:${url}`); },
        async waitForFunction() { events.push(`${id}:draw-ready`); },
        async waitForTimeout() { events.push(`${id}:wait`); },
        async close() { this.closed = true; events.push(`${id}:close`); },
      };
      pages.push(page);
      events.push(`${id}:new`);
      return page;
    },
  };
  const boot = makeSeededBoot({
    url: 'http://game/index.html',
    seedUrl: 'http://game/index.manifest.json',
    wire: (page, tag) => events.push(`${page.id}:wire:${tag}`),
    rewriteSave: async (page, data) => {
      assert.notEqual(data, seed);
      assert.deepEqual(data, { ...seed, version: '2' });
      events.push(`${page.id}:rewrite`);
      return { bytes: 123 };
    },
    wicState: async () => ({ canvas: { x: 10, y: 20, cssW: 1280, cssH: 720 } }),
    readSave: async page => {
      events.push(`${page.id}:read`);
      const states = attemptStates[page.id / 3 - 1] || [null];
      const index = reads.get(page.id) || 0;
      reads.set(page.id, index + 1);
      const state = states[Math.min(index, states.length - 1)];
      if (state instanceof Error) throw state;
      return state;
    },
    note: message => events.push('note:' + message),
  });
  return { boot, context, seed, pages, events };
}

const post = (version = 2) => ({
  version,
  flags: { goliath_down: true, elah_ended: false },
  progress: { act: 'aftermath', pos: [17, 44] },
});
const fight = () => ({
  version: 2,
  flags: { beth_anointed: true, goliath_down: false, elah_ended: false },
  progress: { act: 'ready', pos: [16, 14] },
});

const options = { tag: 'post_win', label: 'post-victory', isLoaded: isPostVictorySave };

test('seed is written from a non-game page after the game closes, then a fresh page verifies it', async () => {
  const wrong = { version: 2, flags: { elah_card: true }, progress: { act: 'witness', pos: [16, 45] } };
  const valid = post();
  const h = harness([[wrong], [valid]]);
  const result = await h.boot(h.context, h.seed, options);
  assert.equal(result.accepted, true);
  assert.equal(result.attempts, 2);
  assert.equal(result.page.id, 6);
  assert.equal(result.page.closed, false);
  assert.equal(result.loaded, valid);
  assert.deepEqual(result.seedInfo, { bytes: 123 });
  for (const [boot, writer, game] of [[1, 2, 3], [4, 5, 6]]) {
    const index = value => h.events.indexOf(value);
    assert.ok(index(`${boot}:close`) < index(`${writer}:goto:http://game/index.manifest.json`));
    assert.ok(index(`${writer}:goto:http://game/index.manifest.json`) < index(`${writer}:rewrite`));
    assert.ok(index(`${writer}:rewrite`) < index(`${writer}:close`));
    assert.ok(index(`${writer}:close`) < index(`${game}:goto:http://game/index.html`));
    assert.ok(index(`${game}:goto:http://game/index.html`) < index(`${game}:read`));
  }
  assert.equal(h.pages[2].closed, true, 'the rejected game page is closed before retry');
  assert.ok(h.events.indexOf('3:close') < h.events.indexOf('4:new'));
  assert.ok(h.events.some(e => e.includes('attempt 1: retry writtenBack=true')));
  assert.ok(h.events.some(e => e.includes('attempt 2: loaded writtenBack=true')));
});

test('matching injected bytes do not count until the engine normalizes the save version', async () => {
  const stale = post('2');
  const written = post(2);
  const h = harness([[stale], [written]]);
  const result = await h.boot(h.context, h.seed, options);
  assert.equal(result.accepted, true);
  assert.equal(result.attempts, 2);
  assert.equal(result.loaded, written);
  assert.ok(h.events.some(e => e.includes('attempt 1: retry writtenBack=false version="2"')));
  assert.ok(h.events.some(e => e.includes('attempt 2: loaded writtenBack=true version=2')));
});

test('a delayed IDBFS write is polled on the same page rather than triggering a retry', async () => {
  const written = post();
  const h = harness([[post('2'), post('2'), written]]);
  const result = await h.boot(h.context, h.seed, options);
  assert.equal(result.accepted, true);
  assert.equal(result.attempts, 1);
  assert.equal(result.loaded, written);
  assert.equal(h.events.filter(e => e === '3:read').length, 3);
  assert.equal(h.pages.length, 3);
});

test('exhausting retries remains a failure and leaves the final page for diagnostics', async () => {
  const h = harness([[null], [{}], [null]]);
  const result = await h.boot(h.context, h.seed, options);
  assert.equal(result.accepted, false);
  assert.equal(result.attempts, 3);
  assert.equal(result.page.id, 9);
  assert.equal(result.page.closed, false);
  assert.equal(h.pages[2].closed, true);
  assert.equal(h.pages[5].closed, true);
  assert.ok(h.events.some(e => e.includes('attempt 3: failed')));
});

test('a read error closes the game page rather than leaving it alive', async () => {
  const h = harness([[new Error('read failed')]]);
  await assert.rejects(h.boot(h.context, h.seed, options), /read failed/);
  assert.ok(h.pages.every(page => page.closed));
});

test('a seed without a numeric save version is rejected before opening a page', async () => {
  const h = harness([]);
  h.seed.version = '2';
  await assert.rejects(h.boot(h.context, h.seed, options), /seed must have a numeric save version/);
  assert.equal(h.pages.length, 0);
});

test('post-victory predicate rejects a fresh, misplaced or already-finished save', () => {
  assert.equal(isPostVictorySave(null), false);
  assert.equal(isPostVictorySave({ flags: { elah_card: true }, progress: { act: 'witness', pos: [16, 45] } }), false);
  assert.equal(isPostVictorySave({ ...post(), progress: { act: 'aftermath', pos: [30, 44] } }), false);
  assert.equal(isPostVictorySave({ ...post(), flags: { goliath_down: true, elah_ended: true } }), false);
  assert.equal(isPostVictorySave({ ...post(), flags: { goliath_down: true, elah_ended: false, 'talked:elah:corin': true } }), false);
  assert.equal(isPostVictorySave(post()), true);
});

test('fight predicate requires the unwon encounter at the south-of-line start', () => {
  assert.equal(isFightSave(fight()), true);
  assert.equal(isFightSave({ ...fight(), flags: { ...fight().flags, goliath_down: true } }), false);
  assert.equal(isFightSave({ ...fight(), progress: { act: 'ready', pos: [16, 10] } }), false);
  assert.equal(isFightSave({ ...fight(), progress: { act: 'witness', pos: [16, 14] } }), false);
});
