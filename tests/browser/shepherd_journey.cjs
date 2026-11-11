/* Real-input Web regression. By default it starts from a seeded shepherd save,
 * skipping witness/Bethlehem. WIC_FRESH_JOURNEY=1 starts with an empty browser
 * save and walks those chapters too. WIC_FULL_JOURNEY=1 continues through the
 * ending. The one deliberate reload checks flock persistence; a second,
 * explicitly staged probe interrupts a return tween to test cleanup.
 *
 *   WIC_PROBE_URL=http://127.0.0.1:8083/ node tests/browser/shepherd_journey.cjs
 *   WIC_FRESH_JOURNEY=1 WIC_FULL_JOURNEY=1 node tests/browser/shepherd_journey.cjs
 *
 * CI installs `playwright`; local sandboxes can set WIC_PLAYWRIGHT=playwright-core
 * and WIC_SPARTICUZ=1 when using the bundled Chromium/SwiftShader package.
 */
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require(process.env.WIC_PLAYWRIGHT || 'playwright');
const root = process.env.WIC_PROBE_URL || 'http://127.0.0.1:8083/';
const out = process.env.WIC_SHEPHERD_OUT || 'build/shepherd-browser';
const errors = [];
const results = {};
fs.mkdirSync(out, { recursive: true });

function assert(ok, message) {
  if (!ok) throw new Error(message);
  console.log('PASS ' + message);
}

async function launch() {
  const options = { headless: true, args: ['--use-gl=angle', '--use-angle=swiftshader',
    '--enable-unsafe-swiftshader'] };
  if (process.env.WIC_SPARTICUZ === '1') {
    const bundled = require('@sparticuz/chromium').default;
    options.executablePath = await bundled.executablePath();
    options.args = [...bundled.args, ...options.args];
  }
  return chromium.launch(options);
}

async function makePage(browser, label) {
  const context = await browser.newContext({ viewport: { width: 1280, height: 720 },
    serviceWorkers: 'block' });
  const page = await context.newPage();
  page.on('pageerror', e => errors.push(`${label}: ${e.message}`));
  page.on('console', m => { if (m.type() === 'error') errors.push(`${label}: ${m.text()}`); });
  return { context, page };
}

const pause = (p, ms) => p.waitForTimeout(ms);
const state = (p, key) => p.evaluate(k => window[k], key);
async function press(p) { await p.keyboard.press('Space'); await pause(p, 420); }

async function waitState(p, key, label, predicate, handleDialogue = false, timeout = 70000) {
  const deadline = Date.now() + timeout;
  let s;
  while (Date.now() < deadline) {
    s = await state(p, key);
    if (s && predicate(s)) return s;
    if (handleDialogue && s?.dialogue) await press(p);
    else await pause(p, 180);
  }
  const { map, exits, ...detail } = s || {};
  throw new Error(`${label} timed out: ${JSON.stringify(detail).slice(0, 3000)}`);
}

// Follow moving sheep with short real key holds. The simple detour handles the
// field's fence/rock edges; it never sets the player's position from the probe.
async function countSheep(p, key, count) {
  let last = null, blocked = 0;
  for (let i = 0; i < 100; i++) {
    const s = await state(p, key);
    if (s.count >= count || s.cleanup?.verified) return s;
    if (s.dialogue) { await press(p); continue; }
    if (s.paused) { await pause(p, 200); continue; }
    if (s.target_kind === 'flock') {
      await p.keyboard.press('Space');
      await pause(p, 220);
      continue;
    }
    if (!s.animals.length) throw new Error(`no sheep while count is ${s.count}/${count}`);
    const a = s.animals.map(v => ({ ...v, distance: Math.hypot(v.pos[0] - s.player[0], v.pos[1] - s.player[1]) }))
      .sort((x, y) => x.distance - y.distance)[0];
    const dx = a.pos[0] - s.player[0], dy = a.pos[1] - s.player[1];
    let direction = Math.abs(dx) > Math.abs(dy) ? (dx < 0 ? 'ArrowLeft' : 'ArrowRight')
      : (dy < 0 ? 'ArrowUp' : 'ArrowDown');
    blocked = last && Math.hypot(s.player[0] - last[0], s.player[1] - last[1]) < 2 ? blocked + 1 : 0;
    if (blocked >= 3) {
      direction = Math.abs(dx) > Math.abs(dy) ? (dy < 0 ? 'ArrowUp' : 'ArrowDown')
        : (dx < 0 ? 'ArrowLeft' : 'ArrowRight');
      blocked = 0;
    }
    last = s.player;
    await p.keyboard.down(direction);
    await pause(p, 450);
    await p.keyboard.up(direction);
    await pause(p, 100);
  }
  throw new Error(`could not count sheep ${count}: ${JSON.stringify(await state(p, key)).slice(0, 1800)}`);
}

async function playPractice(p, key) {
  await waitState(p, key, 'sling practice', s => !!s.practice, true);
  for (let attempt = 0; attempt < 14; attempt++) {
    await p.waitForFunction(k => {
      const v = window[k];
      return v && (!v.practice || (v.practice.phase === 0 && Math.abs(v.practice.marker - 0.5) < 0.09));
    }, key, { timeout: 30000 });
    const s = await state(p, key);
    if (!s.practice) break;
    await p.keyboard.press('Space');
    await pause(p, 350);
  }
}

// Plan over the Region's read-only collision map, then send only real keyboard
// holds. This tests the walk rather than teleporting between chapter beats.
function findRoute(map, position, goal, range) {
  const start = [Math.floor(position[0] / 16), Math.floor(position[1] / 16)];
  const passable = (x, y) => y >= 0 && y < map.length && x >= 0 && x < map[y].length && map[y][x] === '.';
  if (!passable(...start)) throw new Error(`player started in a solid tile ${start}`);
  const key = (x, y) => `${x},${y}`;
  const queue = [start], previous = new Map([[key(...start), null]]);
  let end = null;
  for (let i = 0; i < queue.length; i++) {
    const [x, y] = queue[i];
    if (Math.hypot(x * 16 + 8 - goal[0], y * 16 + 8 - goal[1]) < range) { end = [x, y]; break; }
    for (const [dx, dy] of [[0, -1], [1, 0], [0, 1], [-1, 0]]) {
      const nx = x + dx, ny = y + dy, k = key(nx, ny);
      if (passable(nx, ny) && !previous.has(k)) { previous.set(k, [x, y]); queue.push([nx, ny]); }
    }
  }
  if (!end) throw new Error(`no route to ${goal} (radius ${range})`);
  const route = [];
  for (let cur = end; cur; cur = previous.get(key(...cur))) route.push(cur);
  return route.reverse();
}

async function walkTo(p, key, label, goal, range, done) {
  let last = null, still = 0, lastKey = '';
  for (let i = 0; i < 600; i++) {
    const s = await state(p, key);
    if (done(s)) return s;
    if (s.dialogue) { await press(p); last = null; continue; }
    if (s.paused) { await pause(p, 200); last = null; continue; }
    // Patrolling/following people can move while we walk. Resolve their
    // current position from read-only telemetry on every step.
    const destination = typeof goal === 'function' ? goal(s) : goal;
    if (!destination) throw new Error(`${label}: destination disappeared`);
    const route = findRoute(s.map, s.player, destination, range);
    const cur = route[0], next = route[1] || route[0];
    const centre = [cur[0] * 16 + 8, cur[1] * 16 + 8];
    let dx = next[0] * 16 + 8 - s.player[0], dy = next[1] * 16 + 8 - s.player[1];
    // Centre across the travel axis before squeezing past a solid tile.
    if (next[0] !== cur[0] && Math.abs(s.player[1] - centre[1]) > 3.5) dx = 0;
    else if (next[1] !== cur[1] && Math.abs(s.player[0] - centre[0]) > 3.5) dy = 0;
    if (next[0] !== cur[0]) dy = dx === 0 ? centre[1] - s.player[1] : 0;
    else if (next[1] !== cur[1]) dx = dy === 0 ? centre[0] - s.player[0] : 0;
    if (route.length === 1) {
      dx = destination[0] - s.player[0];
      dy = destination[1] - s.player[1];
      if (Math.hypot(dx, dy) < 3.0) { await pause(p, 180); continue; }
    }
    const horizontal = Math.abs(dx) > Math.abs(dy);
    const amount = horizontal ? dx : dy;
    if (Math.abs(amount) < 1.0) { await pause(p, 120); continue; }
    const direction = horizontal ? (amount < 0 ? 'ArrowLeft' : 'ArrowRight')
      : (amount < 0 ? 'ArrowUp' : 'ArrowDown');
    if (last && lastKey === direction && Math.hypot(s.player[0] - last[0], s.player[1] - last[1]) < 0.8) still++;
    else still = 0;
    if (still >= 5) throw new Error(`${label}: blocked at ${s.player}, path ${JSON.stringify(route.slice(0, 4))}`);
    last = s.player;
    lastKey = direction;
    await p.keyboard.down(direction);
    await pause(p, Math.max(75, Math.min(260, Math.abs(amount) * 13)));
    await p.keyboard.up(direction);
    await pause(p, 100);
  }
  throw new Error(`${label}: navigation did not finish`);
}

async function speakTo(p, key, id, completed) {
  for (let attempt = 0; attempt < 5; attempt++) {
    // Wait out the prior tap lock before approaching: a patrolling person can
    // move beyond the talk radius if we wait after reaching them.
    await pause(p, 550);
    await walkTo(p, key, id, s => s.people.find(n => n.id === id)?.pos, 14, s => {
      const person = s.people.find(n => n.id === id);
      return person && s.target_kind === 'npc' && s.target === id
        && Math.hypot(person.pos[0] - s.player[0], person.pos[1] - s.player[1]) < 13;
    });
    await press(p);
    const s = await waitState(p, key, `${id} dialogue closes`, v => !v.dialogue && !v.paused,
      true, 120000);
    if (completed(s)) return s;
    console.log(`retry ${id}: target moved or interaction was locked`);
  }
  throw new Error(`${id}: interaction did not complete after retries`);
}

async function takeRoad(p, key, to) {
  const s = await state(p, key);
  const exit = s.exits.find(e => e.to === to);
  if (!exit) throw new Error(`no road from ${s.region} to ${to}`);
  const goal = [exit.at[0] * 16 + 8, exit.at[1] * 16 + 8];
  await walkTo(p, key, `road to ${to}`, goal, 9,
    v => v.target_kind === 'exit' && v.target === to);
  await pause(p, 550);
  await press(p);
  return waitState(p, key, `arrival in ${to}`, v => v.region === to && !v.dialogue && !v.paused,
    true, 120000);
}

// The same read-only probe may be opened with no seed in a fresh browser
// context. In this mode every story flag is earned through keyboard input.
async function freshOpening(p, key) {
  let s = await waitState(p, key, 'fresh witness', v => v.region === 'elah' && v.act === 'witness'
    && !v.dialogue && !v.paused, true);
  assert(s.word_count === 0 && !s.met_line && !s.beth_anointed,
    'fresh browser begins as the witness without story flags');
  for (const id of ['corin', 'boy', 'woman', 'elder']) {
    const before = s.word_count;
    s = await speakTo(p, key, id, v => v.word_count > before);
    console.log(`spoke to ${id}: ${s.word_count}/4 verses`);
  }
  assert(s.word_count >= 4, 'four camp conversations supply the witness verses');
  const sight = [16 * 16 + 8, 13 * 16 + 8];
  await walkTo(p, key, 'first sight', sight, 9, v => v.saw_giant);
  s = await waitState(p, key, 'first sight finishes', v => v.saw_giant && !v.dialogue && !v.paused, true);
  const line = [16 * 16 + 8, s.challenge_row * 16 + 8];
  s = await walkTo(p, key, 'witness line', line, 9, v => v.met_line);
  s = await waitState(p, key, 'road opens', v => v.met_line && !v.dialogue && !v.paused, true);
  assert(s.saw_giant && !s.beth_anointed, 'the first sight and witness line precede Bethlehem');
  await p.screenshot({ path: path.join(out, '00_witness_line.png') });
  s = await takeRoad(p, key, 'bethlehem');
  assert(s.mission === 'beth_gate', 'walking south reaches Bethlehem and its first mission');
  s = await speakTo(p, key, 'elder', v => v.beth_elder);
  s = await speakTo(p, key, 'samuel', v => v.beth_sons);
  s = await speakTo(p, key, 'david', v => v.beth_called);
  s = await speakTo(p, key, 'samuel', v => v.beth_anointed);
  assert(s.beth_elder && s.beth_sons && s.beth_called && s.beth_anointed,
    'Bethlehem conversations lead to David’s anointing');
  await p.screenshot({ path: path.join(out, '00_bethlehem.png') });
  s = await takeRoad(p, key, 'elah');
  s = await waitState(p, key, 'the field after returning', v => v.flock_active && v.field
    && !v.dialogue && !v.paused, true, 120000);
  assert(s.beth_anointed && s.count === 0 && s.act === 'shepherd',
    'the walk home becomes David in the shepherd field after the anointing');
  results.opening = { words: s.word_count, saw_giant: s.saw_giant, met_line: s.met_line,
    beth_elder: s.beth_elder, beth_sons: s.beth_sons, beth_called: s.beth_called,
    beth_anointed: s.beth_anointed, act: s.act };
}

async function continueChapter(p, key) {
  let s = await state(p, key);
  for (let i = 0; i < 8 && s.provisions < 3; i++) {
    const choices = s.pickups.filter(x => x.kind === 'provision')
      .map(x => ({ ...x, d: Math.hypot(x.pos[0] - s.player[0], x.pos[1] - s.player[1]) }))
      .sort((a, b) => a.d - b.d);
    if (!choices.length) throw new Error(`missing provisions at ${s.provisions}/3`);
    const item = choices[0], before = s.provisions;
    s = await walkTo(p, key, item.id, item.pos, 9, v => v.provisions > before || v.act !== 'errand');
    console.log(`walked to ${item.id}: provisions ${s.provisions}/3`);
  }
  assert(s.provisions === 3, 'walked to and collected all three provisions');
  const brothers = [s.brothers_at[0] * 16 + 8, s.brothers_at[1] * 16 + 8];
  s = await walkTo(p, key, 'brothers', brothers, 18, v => v.brothers_met);
  assert(s.brothers_met, 'walking to the brothers advances their story beat');
  s = await waitState(p, key, 'Saul in camp', v => v.act === 'saul' && !v.dialogue && !v.paused
    && v.people.some(n => n.id === 'saul'), true);
  const king = s.people.find(n => n.id === 'saul');
  await walkTo(p, key, 'Saul', king.pos, 14, v => v.target_kind === 'npc' && v.target === 'saul');
  await press(p);
  s = await waitState(p, key, 'wearing armour', v => v.act === 'armour' && v.armour
    && !v.dialogue && !v.paused, true, 90000);
  assert(s.armour_visible && s.armour_painted && Math.abs(s.speed_scale - 0.42) < 0.001,
    'Saul equips visible painted armour at the reduced walk speed');
  await p.screenshot({ path: path.join(out, '05_armour.png') });
  await p.keyboard.down('ArrowRight');
  await waitState(p, key, 'armour stumble', v => v.dialogue, false, 15000);
  await p.keyboard.up('ArrowRight');
  s = await waitState(p, key, 'brook mission', v => v.act === 'stones' && v.armour_off
    && !v.armour && !v.dialogue && !v.paused, true, 90000);
  assert(Math.abs(s.speed_scale - 1) < 0.001, 'walking in armour starts the stumble and restores normal speed');
  const brook = [s.brook_at[0] * 16 + 8, s.brook_at[1] * 16 + 8];
  s = await walkTo(p, key, 'brook', brook, 18, v => !!v.stone_choice);
  assert(s.stone_choice.chosen === 0, 'walking to the brook opens an empty stone choice');
  for (let i = 0; i < 5; i++) {
    await p.keyboard.press('ArrowRight');
    await pause(p, 100);
    await p.keyboard.press('Space');
    await pause(p, 280);
  }
  s = await state(p, key);
  assert(s.stone_choice?.chosen === 5 && s.stone_choice.full, 'keyboard selects five distinct stones');
  await p.screenshot({ path: path.join(out, '06_five_stones.png') });
  await press(p);
  s = await waitState(p, key, 'ready for line', v => v.act === 'ready' && v.stones === 5
    && !v.dialogue && !v.paused, true, 90000);
  const line = [16 * 16 + 8, s.challenge_row * 16 + 8];
  await walkTo(p, key, 'challenge line', line, 10, v => !!v.fight);
  assert(!!(await state(p, key)).fight, 'walking to the line opens the duel');
  let bestHits = 0, lastPress = 0;
  const deadline = Date.now() + 150000;
  while (Date.now() < deadline) {
    s = await state(p, key);
    if (s.goliath_down && s.act === 'aftermath' && !s.fight) break;
    const fight = s.fight;
    if (fight) bestHits = Math.max(bestHits, fight.hits);
    if (s.dialogue && (!fight || fight.phase === 4)) { await press(p); continue; }
    if (fight && Date.now() - lastPress > 300 && ((fight.phase === 1 && fight.strike < 0.55)
        || (fight.phase === 2 && Math.abs(fight.marker) < fight.band * 0.55))) {
      await p.keyboard.press('Space');
      lastPress = Date.now();
    }
    await pause(p, 70);
  }
  s = await state(p, key);
  assert(bestHits >= 3 && s.goliath_down && s.act === 'aftermath' && !s.fight,
    'real duel input lands three hits and returns to the aftermath');
  await p.screenshot({ path: path.join(out, '07_aftermath.png') });
  s = await waitState(p, key, 'aftermath control', v => !v.dialogue && !v.paused, true);
  const corin = s.people.find(n => n.id === 'corin');
  if (!corin) throw new Error('Corin missing after victory');
  await walkTo(p, key, 'Corin', corin.pos, 14, v => v.target_kind === 'npc' && v.target === 'corin');
  await press(p);
  s = await waitState(p, key, 'chapter ending', v => v.ended && !v.dialogue && !v.paused, true, 120000);
  assert(s.talked_corin && s.ended && s.act === 'done', 'Corin and the ending finish the chapter in this same journey');
  await p.screenshot({ path: path.join(out, '08_ending.png') });
  results.continuation = { provisions: s.provisions, brothers_met: s.brothers_met,
    armour_off: s.armour_off, stones: s.stones, duel_hits: bestHits,
    goliath_down: s.goliath_down, talked_corin: s.talked_corin, ended: s.ended };
}

async function resumeJourney() {
  const browser = await launch();
  const key = '__shepherdResumeProbe';
  let page;
  try {
    ({ page } = await makePage(browser, 'resume'));
    const fresh = process.env.WIC_FRESH_JOURNEY === '1';
    await page.goto(new URL(`shepherd-resume-probe.html${fresh ? '' : '?seed=1'}`, root).href,
      { waitUntil: 'load', timeout: 120000 });
    await page.waitForFunction(k => window[k]?.ready, key, { timeout: 120000 });
    if (fresh) await freshOpening(page, key);
    if (fresh && process.env.WIC_OPENING_ONLY === '1') return;
    let s = await waitState(page, key, 'active field', v => v.flock_active && v.field && !v.dialogue && !v.paused, true);
    const initial = s.animals.map(a => a.id);
    assert(s.count === 0 && initial.length === 3, 'the shepherd has three uncounted sheep');
    s = await countSheep(page, key, 1);
    const missing = initial.filter(id => !s.animals.some(a => a.id === id));
    assert(s.count === 1 && missing.length === 1, 'one sheep is counted exactly once');
    s = await waitState(page, key, 'field reaction', v => !!v.bubble?.rect, false, 5000);
    const [x, y, w, h] = s.bubble.rect;
    const [px, py, pw, ph] = s.bubble.player_rect;
    assert(!(x < px + pw && x + w > px && y < py + ph && y + h > py),
      'the hired boy’s reaction does not cover the player');
    const counted = missing[0];
    await page.screenshot({ path: path.join(out, '01_counted.png') });
    await pause(page, 2600); // allow Godot's IDBFS write to flush before navigating
    await page.goto(new URL('shepherd-resume-probe.html', root).href,
      { waitUntil: 'load', timeout: 120000 });
    await page.waitForFunction(k => window[k]?.ready, key, { timeout: 120000 });
    s = await waitState(page, key, 'reloaded field', v => v.flock_active && v.field && !v.dialogue && !v.paused, true);
    assert(s.count === 1 && s.animals.length === 2 && !s.animals.some(a => a.id === counted),
      'reload restores 1/3 without respawning the counted sheep');
    await page.screenshot({ path: path.join(out, '02_reloaded.png') });
    await countSheep(page, key, 2);
    s = await countSheep(page, key, 3);
    assert(s.count === 3 && s.flock_done, 'remaining sheep complete the flock');
    await playPractice(page, key);
    s = await waitState(page, key, 'errand', v => v.act === 'errand' && !v.field && v.drill_done
      && !v.dialogue && !v.paused && v.provision_count > 0, true, 90000);
    assert(s.provision_count === 3 && s.provisions === 0, 'practice hands back to the errand with three provisions');
    await page.screenshot({ path: path.join(out, '03_errand.png') });
    results.resume = { counted, restored: 1, flock: s.count, drill_done: s.drill_done,
      provisions_available: s.provision_count, act: s.act };
    if (process.env.WIC_FULL_JOURNEY === '1') await continueChapter(page, key);
  } catch (err) {
    if (page && !page.isClosed()) {
      await page.screenshot({ path: path.join(out, 'failure_journey.png') }).catch(() => {});
      const last = await state(page, key).catch(() => null);
      if (last) {
        const { map, exits, ...detail } = last;
        results.failureState = detail;
      }
    }
    throw err;
  } finally { await browser.close(); }
}

async function interruptedReturn() {
  const browser = await launch();
  try {
    const { page } = await makePage(browser, 'cleanup');
    const key = '__shepherdProbe';
    await page.goto(new URL('shepherd-probe.html?leave_on_return=1', root).href,
      { waitUntil: 'load', timeout: 120000 });
    await page.waitForFunction(k => window[k]?.ready, key, { timeout: 120000 });
    await countSheep(page, key, 1);
    const s = await waitState(page, key, 'interrupted return', v => v.cleanup?.verified, false, 20000);
    const q = s.cleanup;
    assert(q.return_was_live && q.had_shadow && q.queued && !q.alive_after,
      'a live sheep return is removed when the staged field exit interrupts it');
    assert(!s.field && s.count === 1 && q.field_pickups === 0 && q.sheep_shadows === 0 && q.saved,
      'field exit leaves no sheep or shadow and retains its counted flag');
    await page.screenshot({ path: path.join(out, '04_interrupted_return.png') });
    results.cleanup = q;
  } finally { await browser.close(); }
}

(async () => {
  try {
    await resumeJourney();
    await interruptedReturn();
    assert(errors.length === 0, 'no browser page or console errors');
    results.ok = true;
  } catch (err) {
    results.ok = false;
    results.error = String(err.stack || err);
    console.error(results.error);
    process.exitCode = 1;
  } finally {
    results.browserErrors = errors;
    fs.writeFileSync(path.join(out, 'result.json'), JSON.stringify(results, null, 2));
  }
})();
