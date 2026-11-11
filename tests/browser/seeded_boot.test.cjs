'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { makeSeededBoot, isPostVictorySave } = require('./seeded_boot.cjs');

function harness(savedStates) {
  const events = [];
  const pages = [];
  const seed = { flags: { goliath_down: true }, settings: { sound: true } };
  let reads = 0;
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
        mouse: { async click(x, y) { events.push(`${id}:click:${x},${y}`); } },
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
      assert.equal(data, seed);
      events.push(`${page.id}:rewrite`);
      return { bytes: 123 };
    },
    wicState: async () => ({ canvas: { x: 10, y: 20, cssW: 1280, cssH: 720 } }),
    readSave: async page => { events.push(`${page.id}:read`); return savedStates[reads++]; },
    note: message => events.push('note:' + message),
  });
  return { boot, context, seed, pages, events };
}

test('seed is written from a non-game page after the game closes, then a fresh page verifies it', async () => {
  const valid = { flags: { goliath_down: true }, progress: { act: 'aftermath', pos: [17, 44] }, settings: { sound: false } };
  const h = harness([{ flags: { elah_card: true }, progress: { act: 'witness', pos: [16, 45] }, settings: { sound: false } }, valid]);
  const result = await h.boot(h.context, h.seed, { tag: 'post_win', label: 'post-victory', isLoaded: isPostVictorySave });
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
    assert.ok(index(`${game}:click:1230,60`) < index(`${game}:read`));
  }
  assert.equal(h.pages[2].closed, true, 'the rejected game page is closed before retry');
  assert.ok(h.events.indexOf('3:close') < h.events.indexOf('4:new'));
  assert.ok(h.events.some(e => e.includes('attempt 1: retry')));
  assert.ok(h.events.some(e => e.includes('attempt 2: loaded')));
});

test('a matching injected save is rejected until the engine writes the settings toggle', async () => {
  const stale = { flags: { goliath_down: true }, progress: { act: 'aftermath', pos: [17, 44] }, settings: { sound: true } };
  const written = { ...stale, settings: { sound: false } };
  const h = harness([stale, written]);
  const result = await h.boot(h.context, h.seed, { tag: 'post_win', label: 'post-victory', isLoaded: isPostVictorySave });
  assert.equal(result.accepted, true);
  assert.equal(result.attempts, 2);
  assert.equal(result.loaded, written);
  assert.ok(h.events.some(e => e.includes('attempt 1: retry writtenBack=false')));
  assert.ok(h.events.some(e => e.includes('attempt 2: loaded writtenBack=true')));
});

test('exhausting retries remains a failure and leaves the final page for diagnostic checks', async () => {
  const h = harness([null, {}, null]);
  const result = await h.boot(h.context, h.seed, { tag: 'post_win', label: 'post-victory', isLoaded: isPostVictorySave });
  assert.equal(result.accepted, false);
  assert.equal(result.attempts, 3);
  assert.equal(result.page.id, 9);
  assert.equal(result.page.closed, false);
  assert.equal(h.pages[2].closed, true);
  assert.equal(h.pages[5].closed, true);
  assert.ok(h.events.some(e => e.includes('attempt 3: failed')));
});

test('a seed without an enabled sound marker is rejected before opening a page', async () => {
  const h = harness([]);
  h.seed.settings.sound = false;
  await assert.rejects(h.boot(h.context, h.seed, {
    tag: 'post_win', label: 'post-victory', isLoaded: isPostVictorySave,
  }), /seed must start with sound enabled/);
  assert.equal(h.pages.length, 0);
});

test('post-victory predicate rejects a fresh or misplaced save', () => {
  assert.equal(isPostVictorySave(null), false);
  assert.equal(isPostVictorySave({ flags: { elah_card: true }, progress: { act: 'witness', pos: [16, 45] } }), false);
  assert.equal(isPostVictorySave({ flags: { goliath_down: true }, progress: { act: 'aftermath', pos: [30, 44] } }), false);
  assert.equal(isPostVictorySave({ flags: { goliath_down: true }, progress: { act: 'aftermath', pos: [17, 44] } }), true);
});
