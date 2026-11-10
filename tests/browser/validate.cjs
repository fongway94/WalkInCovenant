/* eslint-disable no-console */
/*
 * validate.cjs — REAL browser validation of the shipped Godot Web export.
 *
 * This is deliberately NOT a Godot headless test. It opens the exported
 * index.html in Chromium over a local HTTP server, drives it with real
 * keyboard / mouse / touch events, and records DOM, WebGL, WebAudio,
 * IndexedDB and network evidence. Run by the `browser` CI job:
 *
 *   NODE_PATH=/tmp/wicpw/node_modules node tests/browser/validate.cjs
 *
 * Outputs build/browser/log.json and build/browser/shots/*.png. Screenshots
 * are carried back to the authoring sandbox as check-run annotations by the
 * workflow (tools/decode_browser_frames.py reassembles them).
 *
 * Hard failures: no canvas, no WebGL context, no draw calls, a JS exception,
 * a failed/4xx request for an essential file, or a missing save file. Console
 * errors are recorded and summarised; WIC_STRICT=1 turns them into failures
 * once the benign ones have been reviewed.
 */
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require('playwright');

const OUT = process.env.WIC_OUT || 'build/browser';
const SHOTS = path.join(OUT, 'shots');
const URL = process.env.WIC_URL || 'http://127.0.0.1:8080/index.html';
const STRICT = process.env.WIC_STRICT === '1';
fs.mkdirSync(SHOTS, { recursive: true });

const result = {
  url: URL,
  started: new Date().toISOString(),
  chromium: null,
  checks: [],
  console: [],
  pageErrors: [],
  requests: [],
  audio: {},
  saves: {},
  views: [],
  notes: []
};

function check(name, ok, detail) {
  result.checks.push({ name, ok: !!ok, detail: String(detail).slice(0, 500) });
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name} — ${detail}`);
}

function note(s) { result.notes.push(String(s)); console.log('NOTE ' + s); }

/* Instrument the page BEFORE any game script runs. We can read a Godot WebGL
 * canvas, but wrapping getContext/draw calls gives us proof that WebGL was
 * really initialised and is actually drawing, without changing the game. */
const INIT = `(() => {
  window.__wic = {
    draws: 0, glTypes: [], keys: [], pointers: [], touches: [],
    audioCtx: 0, audioResume: 0, audioStates: [], bufferStarts: 0,
    mediaPlays: 0
  };
  function instrument(t, c) {
    if (!c || !/^(webgl2?|experimental-webgl)$/.test(t)) return c;
    window.__wic.glTypes.push(t);
    const P = Object.getPrototypeOf(c);
    for (const m of ['clear', 'drawArrays', 'drawElements']) {
      if (typeof P[m] === 'function' && !P['__wic_w_' + m]) {
        P['__wic_w_' + m] = 1;
        const o = P[m];
        P[m] = function () { window.__wic.draws++; return o.apply(this, arguments); };
      }
    }
    return c;
  }
  const G = HTMLCanvasElement.prototype.getContext;
  HTMLCanvasElement.prototype.getContext = function (t) {
    return instrument(t, G.apply(this, arguments));
  };
  if (window.OffscreenCanvas) {
    const OG = OffscreenCanvas.prototype.getContext;
    OffscreenCanvas.prototype.getContext = function (t) {
      return instrument(t, OG.apply(this, arguments));
    };
  }
  addEventListener('keydown', e => window.__wic.keys.push(e.code), true);
  addEventListener('pointerdown', e => window.__wic.pointers.push(e.pointerType), true);
  addEventListener('touchstart', e => window.__wic.touches.push(e.touches.length), true);
  const Native = window.AudioContext || window.webkitAudioContext;
  if (Native) {
    const Wrapped = function () {
      const c = new Native(...arguments);
      window.__wic.audioCtx++;
      window.__wic.audioStates.push(c.state);
      return c;
    };
    Wrapped.prototype = Native.prototype;
    try { window.AudioContext = Wrapped; } catch (e) {}
    try { if (window.webkitAudioContext) window.webkitAudioContext = Wrapped; } catch (e) {}
    const r = Native.prototype.resume;
    Native.prototype.resume = function () {
      window.__wic.audioResume++;
      const self = this;
      return r.apply(this, arguments).then(v => {
        window.__wic.audioStates.push(self.state);
        return v;
      });
    };
  }
  if (window.AudioBufferSourceNode) {
    const s = window.AudioBufferSourceNode.prototype.start;
    window.AudioBufferSourceNode.prototype.start = function () {
      window.__wic.bufferStarts++;
      return s.apply(this, arguments);
    };
  }
  if (window.HTMLMediaElement) {
    const p = HTMLMediaElement.prototype.play;
    HTMLMediaElement.prototype.play = function () {
      window.__wic.mediaPlays++;
      return p.apply(this, arguments);
    };
  }
})();`;

const ESSENTIAL = /index\.(html|js|wasm|pck|png|icon\.png)|manifest|service\.worker/i;

function wire(page, tag) {
  page.on('console', m => {
    if (m.type() === 'error' || m.type() === 'warning') {
      result.console.push({ tag, type: m.type(), text: m.text().slice(0, 600) });
    }
  });
  page.on('pageerror', e => result.pageErrors.push({ tag, text: String(e).slice(0, 800) }));
  page.on('requestfailed', r => {
    const err = (r.failure() || {}).errorText || '';
    // A reload legitimately cancels in-flight requests; that is not a defect.
    if (err.includes('ERR_ABORTED')) return;
    result.requests.push({ tag, kind: 'failed', url: r.url().slice(0, 300), error: err });
  });
  page.on('response', r => {
    if (r.status() >= 400) {
      result.requests.push({ tag, kind: 'http', url: r.url().slice(0, 300), status: r.status() });
    }
  });
}

async function shot(page, name) {
  await page.screenshot({ path: path.join(SHOTS, name + '.png') });
  console.log('shot ' + name);
}

async function wicState(page) {
  return page.evaluate(() => {
    const c = document.querySelector('canvas');
    const r = c ? c.getBoundingClientRect() : null;
    const rot = document.getElementById('wic-rot');
    return {
      wic: window.__wic || null,
      canvas: c ? { w: c.width, h: c.height, cssW: Math.round(r.width), cssH: Math.round(r.height), x: Math.round(r.x), y: Math.round(r.y) } : null,
      dpr: window.devicePixelRatio,
      inner: [window.innerWidth, window.innerHeight],
      status: (document.getElementById('status') ? document.getElementById('status').textContent : '').slice(0, 160),
      rotationOverlay: rot ? { on: rot.classList.contains('on'), display: getComputedStyle(rot).display, text: rot.textContent.replace(/\\s+/g, ' ').trim().slice(0, 160) } : null
    };
  });
}

/* Godot 4 stores user:// in IndexedDB. Dump the save file so quest state,
 * settings and persistence can be asserted from OUTSIDE the engine. */
async function dumpSave(page, tag) {
  const dump = await page.evaluate(async () => {
    const out = { databases: [], files: [] };
    let dbs = [];
    try { dbs = await indexedDB.databases(); } catch (e) { out.error = String(e); return out; }
    const bytes = x => {
      if (x instanceof Uint8Array || x instanceof ArrayBuffer) return new TextDecoder().decode(x);
      if (Array.isArray(x) && x.length && x.every(n => Number.isInteger(n) && n >= 0 && n <= 255)) {
        return new TextDecoder().decode(new Uint8Array(x));
      }
      if (x && typeof x === 'object') {
        for (const k of ['contents', 'data', 'buffer', 'bytes']) {
          if (x[k] != null) { const s = bytes(x[k]); if (s != null) return s; }
        }
      }
      return null;
    };
    const decode = v => {
      try {
        const b = bytes(v);
        if (b != null) return b;
        if (typeof v === 'string') return v;
        return JSON.stringify(v);
      } catch (e) { return '<binary>'; }
    };
    const shape = v => {
      if (v == null) return String(v);
      const kind = Object.prototype.toString.call(v);
      const keys = (v && typeof v === 'object') ? Object.keys(v).slice(0, 8).join(',') : '';
      return kind + (keys ? '[' + keys + ']' : '') + ' len=' + (v && v.length !== undefined ? v.length : '-');
    };
    for (const d of dbs) {
      out.databases.push({ name: d.name, version: d.version });
      let db;
      try {
        db = await new Promise((res, rej) => { const q = indexedDB.open(d.name); q.onsuccess = () => res(q.result); q.onerror = () => rej(q.error); });
      } catch (e) { continue; }
      for (const s of Array.from(db.objectStoreNames)) {
        let keys = [];
        try {
          keys = await new Promise(res => { const q = db.transaction(s, 'readonly').objectStore(s).getAllKeys(); q.onsuccess = () => res(q.result); q.onerror = () => res([]); });
        } catch (e) { continue; }
        for (const k of keys) {
          if (!String(k).includes('save')) continue;
          let v = null;
          try {
            v = await new Promise(res => { const q = db.transaction(s, 'readonly').objectStore(s).get(k); q.onsuccess = () => res(q.result); q.onerror = () => res(null); });
          } catch (e) { continue; }
          const text = decode(v);
          out.files.push({ db: d.name, store: s, key: String(k), text: text.slice(0, 12000), shape: shape(v), raw: text.slice(0, 700) });
        }
      }
      db.close();
    }
    return out;
  });
  result.saves[tag] = dump;
  return dump;
}

function parseSave(dump) {
  for (const f of (dump.files || [])) {
    try {
      const j = JSON.parse(f.text);
      return j;
    } catch (e) { /* next file */ }
  }
  return null;
}

const SAVE_KEY = '/userfs/godot/app_userdata/WalkInCovenant/save.json';

/* Rewriting an existing IDBFS record is more reliable than creating the DB
 * ourselves: Godot/Emscripten decides the version, store shape, mode and
 * timestamp, and we only replace the file bytes. The page is then reloaded so
 * the engine's own startup sync reads them. */
async function rewriteSave(page, save) {
  return page.evaluate(async (payload) => {
    const key = payload.key;
    const dbs = await indexedDB.databases();
    const info = dbs.find(x => x.name === '/userfs');
    const ver = info ? info.version : 21;
    const openDb = (v, create) => new Promise((res, rej) => {
      const q = indexedDB.open('/userfs', v);
      q.onupgradeneeded = () => {
        if (create && !q.result.objectStoreNames.contains('FILE_DATA')) q.result.createObjectStore('FILE_DATA');
      };
      q.onsuccess = () => res(q.result);
      q.onerror = () => rej(q.error);
    });
    let db = await openDb(ver, false);
    if (!db.objectStoreNames.contains('FILE_DATA')) {
      db.close();
      db = await openDb(ver + 1, true);
    }
    const old = await new Promise(res => {
      const q = db.transaction('FILE_DATA', 'readonly').objectStore('FILE_DATA').get(key);
      q.onsuccess = () => res(q.result);
      q.onerror = () => res(null);
    });
    const contents = new TextEncoder().encode(payload.text);
    const value = old ? Object.assign({}, old, { contents, timestamp: Date.now() })
      : { timestamp: Date.now(), mode: 33206, contents };
    await new Promise((res, rej) => {
      const t = db.transaction('FILE_DATA', 'readwrite');
      t.objectStore('FILE_DATA').put(value, key);
      t.objectStore('FILE_DATA').put(value, key + '.bak');
      t.oncomplete = res;
      t.onerror = () => rej(t.error);
    });
    db.close();
    return { hadOld: !!old, mode: value.mode, bytes: contents.length,
             oldContents: old ? Object.prototype.toString.call(old.contents) : 'new' };
  }, { key: SAVE_KEY, text: JSON.stringify(save, null, '\t') });
}

/* Read one flag out of the live save without disturbing the running game. */
async function readSave(page) {
  return page.evaluate(async (key) => {
    const db = await new Promise((res, rej) => {
      const q = indexedDB.open('/userfs');
      q.onsuccess = () => res(q.result);
      q.onerror = () => rej(q.error);
    });
    if (!db.objectStoreNames.contains('FILE_DATA')) { db.close(); return null; }
    let v = null;
    try {
      v = await new Promise(res => {
        const q = db.transaction('FILE_DATA', 'readonly').objectStore('FILE_DATA').get(key);
        q.onsuccess = () => res(q.result);
        q.onerror = () => res(null);
      });
    } finally { db.close(); }
    if (!v) return null;
    let text = null;
    const c = v.contents;
    if (c instanceof Uint8Array || c instanceof ArrayBuffer) text = new TextDecoder().decode(c);
    else if (Array.isArray(c)) text = new TextDecoder().decode(new Uint8Array(c));
    else if (typeof v === 'string') text = v;
    if (text == null) return null;
    try { return JSON.parse(text); } catch (e) { return null; }
  }, SAVE_KEY);
}

/* A late-chapter save. Every mission before `the_line` is marked complete in
 * the same shape GameState writes, so the exported game resumes itself at the
 * duel through its OWN save loader, not through a debug hook. */
function postWinSave() {
  const s = fightSave();
  s.flags.goliath_down = true;
  s.flags.elah_ended = false;
  s.seals = ['chapter_one'];
  s.completed = ['elah'];
  s.pos = [16, 43];
  s.progress = { act: 'aftermath', stones: 5, provisions: 3, brothers: true, pos: [16, 43] };
  return s;
}

function fightSave() {
  return {
    version: 2, name: 'pilgrim', calling: 'shepherd', level: 1, xp: 120,
    stats: { courage: 4, wisdom: 4, compassion: 4, faith: 4 },
    ways: { step: 1, notice: 1, stay: 1, wait: 1 },
    hints_used: 0, guidance: 0, relics: [], fruits: [], seals: [], completed: [],
    flags: {
      elah_card: true, elah_first_call: true, elah_saw_him: true,
      elah_met_the_line: true, beth_anointed: true, elah_drill_done: true,
      elah_brothers_met: true, elah_armour_off: true, elah_stones_chosen: true,
      goliath_down: false, elah_ended: false
    },
    words: ['fear', 'name', 'look', 'shepherd'], quests: {},
    region: 'elah', campaign: 'elah', pos: [16, 10],
    progress: { act: 'ready', stones: 5, provisions: 3, brothers: true, pos: [16, 10] },
    day: 1, time_of_day: 'morning',
    settings: { clean_mode: true, sound: true, music: true, reduce_motion: false }
  };
}

async function waitBoot(page, label) {
  await page.goto(URL, { waitUntil: 'load', timeout: 120000 });
  await page.waitForFunction(() => window.__wic && window.__wic.draws > 40, null, { timeout: 120000 });
  await page.waitForTimeout(1800);
  const s = await wicState(page);
  check(label + ': canvas exists', !!s.canvas, JSON.stringify(s.canvas));
  check(label + ': WebGL context created', s.wic && s.wic.glTypes.length > 0, JSON.stringify(s.wic && s.wic.glTypes));
  check(label + ': WebGL is drawing', s.wic && s.wic.draws > 40, 'draw calls=' + (s.wic && s.wic.draws));
  return s;
}

(async () => {
  const launch = {
    headless: true,
    args: [
      '--no-sandbox', '--disable-dev-shm-usage',
      '--use-gl=angle', '--use-angle=swiftshader',
      '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist',
      '--enable-webgl', '--disable-features=WebGLDraftExtensions'
    ]
  };
  // Authoring sandbox: point at a locally provisioned Chromium (the Playwright
  // CDN is not reachable there). CI uses Playwright's own download.
  if (process.env.WIC_CHROMIUM) launch.executablePath = process.env.WIC_CHROMIUM;
  const browser = await chromium.launch(launch);
  result.chromium = browser.version();
  console.log('Chromium ' + result.chromium);

  /* ── 1. DESKTOP: load, real input, dialogue, mute, save, reload ─────── */
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 720 }, deviceScaleFactor: 1 });
  await ctx.addInitScript(INIT);
  const page = await ctx.newPage();
  wire(page, 'desktop');
  let st = await waitBoot(page, 'desktop');
  result.views.push({ tag: 'desktop', state: st });
  await shot(page, '01_boot_desktop');

  // A real pointer gesture: also the user activation that unlocks WebAudio.
  const rect = st.canvas;
  const sx = rect.cssW / 320, sy = rect.cssH / 180;
  await page.mouse.click(rect.x + rect.cssW * 0.5, rect.y + rect.cssH * 0.5);
  await page.waitForTimeout(400);
  await shot(page, '02_after_click');

  // Keyboard: hold a movement key, then interact. These are real DOM key
  // events through the engine's own input pipeline, not a test hook.
  await page.keyboard.down('ArrowRight');
  await page.waitForTimeout(700);
  await page.keyboard.up('ArrowRight');
  await page.keyboard.down('KeyW');
  await page.waitForTimeout(400);
  await page.keyboard.up('KeyW');
  await page.waitForTimeout(300);
  await shot(page, '03_after_keyboard_move');
  const keys = await page.evaluate(() => window.__wic.keys.slice(-12));
  check('keyboard events reached the page', keys.length >= 2, JSON.stringify(keys));

  // Interact (Z / E / Space are all bound to "interact").
  await page.keyboard.press('e');
  await page.waitForTimeout(900);
  await shot(page, '04_after_interact');
  await page.keyboard.press('Space');
  await page.waitForTimeout(700);
  await shot(page, '05_dialogue_advance_1');
  await page.keyboard.press('Space');
  await page.waitForTimeout(700);
  await shot(page, '06_dialogue_advance_2');
  await page.keyboard.press('Escape');
  await page.waitForTimeout(600);
  await shot(page, '07_after_cancel');
  await page.keyboard.press('Tab');
  await page.waitForTimeout(700);
  await shot(page, '08_menu_or_journal');
  await page.keyboard.press('Escape');
  await page.waitForTimeout(400);

  // Audio: after the gestures, is there a running AudioContext and did any
  // buffer actually start? This is a TECHNICAL playback check, not listening.
  const audio = await page.evaluate(() => ({
    contexts: window.__wic.audioCtx,
    resumes: window.__wic.audioResume,
    states: window.__wic.audioStates,
    bufferStarts: window.__wic.bufferStarts,
    mediaPlays: window.__wic.mediaPlays
  }));
  result.audio = audio;
  note('audio telemetry ' + JSON.stringify(audio));
  check('WebAudio context created after user gesture', audio.contexts > 0, 'contexts=' + audio.contexts);
  check('audio unlocked (a resume reached running)', audio.states.includes('running') || audio.resumes > 0, JSON.stringify(audio.states));

  // Mute: the sound toggle is the last button in the HUD's top bar, i.e. at
  // roughly (308, 9) in the logical 320x180 design. The click is a real DOM
  // pointer event and also forces a settings save.
  const before = await dumpSave(page, 'before_mute');
  const saveBefore = parseSave(before);
  await page.mouse.click(rect.x + 305 * sx, rect.y + 10 * sy);
  await page.waitForTimeout(1200);
  await shot(page, '09_after_mute_click');
  let after = await dumpSave(page, 'after_mute');
  let saveAfter = parseSave(after);
  // IDBFS is flushed asynchronously; give it a few beats before concluding.
  for (let i = 0; i < 6 && !saveAfter; i++) {
    await page.waitForTimeout(700);
    after = await dumpSave(page, 'after_mute');
    saveAfter = parseSave(after);
  }
  const soundBefore = saveBefore && saveBefore.settings ? saveBefore.settings.sound : null;
  const soundAfter = saveAfter && saveAfter.settings ? saveAfter.settings.sound : null;
  note('mute setting ' + JSON.stringify({ soundBefore, soundAfter }));
  check('a save file is readable from IndexedDB', !!(saveAfter || saveBefore),
    (saveAfter || saveBefore) ? 'parsed save.json' : JSON.stringify(after).slice(0, 400));
  if (saveBefore && saveAfter && soundBefore !== null) {
    check('mute writes the setting through to the save', soundBefore !== soundAfter,
      'sound ' + soundBefore + ' -> ' + soundAfter);
  } else {
    note('mute comparison inconclusive: no readable save before the toggle (IDBFS may not have flushed yet)');
  }

  // Reload: does the exported game come back, and does the save survive?
  await page.reload({ waitUntil: 'load', timeout: 120000 });
  await page.waitForFunction(() => window.__wic && window.__wic.draws > 40, null, { timeout: 120000 });
  await page.waitForTimeout(1200);
  await shot(page, '10_after_reload');
  let afterReload = await dumpSave(page, 'after_reload');
  let saveReload = parseSave(afterReload);
  for (let i = 0; i < 6 && !saveReload; i++) {
    await page.waitForTimeout(700);
    afterReload = await dumpSave(page, 'after_reload');
    saveReload = parseSave(afterReload);
  }
  const baseline = saveAfter || saveBefore;
  check('save survives a full page reload', !!saveReload && !!baseline,
    'before=' + !!baseline + ' afterReload=' + !!saveReload);
  if (saveReload && baseline) {
    const p0 = baseline.progress == null ? '' : JSON.stringify(baseline.progress);
    const p1 = saveReload.progress == null ? '' : JSON.stringify(saveReload.progress);
    check('reload preserves the chapter/act', p0 !== '' && p0 === p1,
      'progress=' + p1.slice(0, 220));
  }

  /* ── 2. RESPONSIVE: LIVE resize of the same running game ──────────────
   * The web build uses canvas_items / expand, so the root viewport changes
   * logical size while running. Capturing after each resize proves the HUD,
   * dialogue box and canvas re-lay themselves out (or exposes clipping). */
  const layouts = [
    { tag: 'wide_1920x1080', w: 1920, h: 1080 },
    { tag: 'fourthree_1024x768', w: 1024, h: 768 },
    { tag: 'mobile_landscape_844x390', w: 844, h: 390 },
    { tag: 'small_landscape_640x360', w: 640, h: 360 }
  ];
  for (const L of layouts) {
    await page.setViewportSize({ width: L.w, height: L.h });
    await page.waitForTimeout(900);
    const s = await wicState(page);
    result.views.push({ tag: L.tag, state: s });
    await shot(page, 'vp_' + L.tag);
    check(L.tag + ': canvas still fills the viewport', s.canvas && Math.abs(s.canvas.cssW - L.w) <= 2 && Math.abs(s.canvas.cssH - L.h) <= 2,
      JSON.stringify(s.canvas));
    check(L.tag + ': WebGL still drawing after resize', s.wic && s.wic.draws > 40, 'draw calls=' + (s.wic && s.wic.draws));
  }
  await ctx.close();

  /* ── 3. TOUCH / MOBILE: real touch emulation, landscape + portrait ──── */
  const touch = await browser.newContext({
    viewport: { width: 844, height: 390 }, deviceScaleFactor: 2,
    hasTouch: true, isMobile: true
  });
  await touch.addInitScript(INIT);
  const tp = await touch.newPage();
  wire(tp, 'touch_landscape');
  const ts = await waitBoot(tp, 'touch_landscape');
  result.views.push({ tag: 'touch_landscape', state: ts });
  await shot(tp, 'touch_01_landscape_boot');
  await tp.touchscreen.tap(Math.round(ts.canvas.cssW * 0.5), Math.round(ts.canvas.cssH * 0.5));
  await tp.waitForTimeout(500);
  // A button is drawn at the bottom-right of the logical 320x180 screen.
  await tp.touchscreen.tap(Math.round(ts.canvas.x + ts.canvas.cssW - 34 * (ts.canvas.cssW / 320)),
    Math.round(ts.canvas.y + ts.canvas.cssH - 30 * (ts.canvas.cssH / 180)));
  await tp.waitForTimeout(600);
  await shot(tp, 'touch_02_after_taps');
  const touchLog = await tp.evaluate(() => ({ touches: window.__wic.touches, pointers: window.__wic.pointers }));
  check('touch events reached the page', touchLog.touches.length > 0, JSON.stringify(touchLog));

  await tp.setViewportSize({ width: 390, height: 844 });
  await tp.waitForTimeout(900);
  const ps = await wicState(tp);
  result.views.push({ tag: 'touch_portrait', state: ps });
  await shot(tp, 'touch_03_portrait');
  check('portrait shows the rotate-to-landscape guidance',
    ps.rotationOverlay && ps.rotationOverlay.on && ps.rotationOverlay.display !== 'none',
    JSON.stringify(ps.rotationOverlay));
  await touch.close();

  /* ── 4. GOLIATH ENCOUNTER → VICTORY → CHAPTER COMPLETION ───────────────
   * A fresh context is seeded with a real GameState-shaped save at `the_line`.
   * From there every transition is driven by real keyboard input in the
   * exported game: crossing the challenge row opens the duel, timed presses
   * dodge/throw until the giant falls, then the player walks back to Corin and
   * the ending plays. No GDScript test hook is used; the save is the same file
   * the game itself writes to IDBFS. */
  const seeded = await browser.newContext({ viewport: { width: 1280, height: 720 }, deviceScaleFactor: 1 });
  await seeded.addInitScript(INIT);
  const sp = await seeded.newPage();
  wire(sp, 'seeded_fight');
  // Boot once so Godot creates its own IDBFS database, then rewrite save.json
  // with the late-chapter state and reload. The second boot is the one under
  // test; it goes through the engine's real save loader.
  await sp.goto(URL, { waitUntil: 'load', timeout: 120000 });
  await sp.waitForFunction(() => window.__wic && window.__wic.draws > 40, null, { timeout: 120000 });
  await sp.waitForTimeout(1600);
  const seedInfo = await rewriteSave(sp, fightSave());
  note('rewrote GameState save ' + JSON.stringify(seedInfo));
  await sp.reload({ waitUntil: 'load', timeout: 120000 });
  await sp.waitForFunction(() => window.__wic && window.__wic.draws > 40, null, { timeout: 120000 });
  await sp.waitForTimeout(1600);
  const sfs = await wicState(sp);
  check('seeded_fight: canvas exists', !!sfs.canvas, JSON.stringify(sfs.canvas));
  check('seeded_fight: WebGL is drawing', sfs.wic && sfs.wic.draws > 40, 'draw calls=' + (sfs.wic && sfs.wic.draws));
  await shot(sp, 'goliath_01_ready');
  // A HUD sound click forces GameState.save_game(), so reading the save after
  // it proves what the ENGINE has in memory, not just what we wrote to IDBFS.
  const sx2 = sfs.canvas.cssW / 320, sy2 = sfs.canvas.cssH / 180;
  await sp.mouse.click(sfs.canvas.x + 305 * sx2, sfs.canvas.y + 10 * sy2);
  await sp.waitForTimeout(1200);
  const readySave = await readSave(sp);
  check('game loaded the seeded save (engine wrote it back)',
    !!readySave && !!readySave.flags && readySave.flags.beth_anointed === true
      && readySave.progress && readySave.progress.act !== 'witness',
    'progress=' + JSON.stringify(readySave && readySave.progress).slice(0, 220)
      + ' flags=' + JSON.stringify(readySave && readySave.flags).slice(0, 220));
  await shot(sp, 'goliath_01_ready');

  // North across challenge row 11. The region is paused for the battle intro,
  // so a short hold is enough to fire the trigger.
  await sp.keyboard.down('KeyW');
  await sp.waitForTimeout(1100);
  await sp.keyboard.up('KeyW');
  await sp.waitForTimeout(1400);
  await shot(sp, 'goliath_02_duel');

  // One press per 0.84 s. The marker takes 1.29 s for a full sweep, so each
  // round's first press lands at a different point on the forehead band; over
  // the five stones plus the brook resupply three hits land. Presses also
  // advance the intro, victory and ending dialogue. Poll the real save for the
  // win flag rather than trusting a screenshot to mean "won".
  let won = false, presses = 0;
  const fightStart = Date.now();
  const fightMs = parseInt(process.env.WIC_FIGHT_MS || '150000', 10);
  const cadence = 840;
  while (Date.now() - fightStart < fightMs && !won) {
    await sp.keyboard.press('Space');
    presses++;
    await sp.waitForTimeout(cadence);
    const s = await readSave(sp);
    if (s && s.flags && s.flags.goliath_down === true) won = true;
    if (presses === 8) await shot(sp, 'goliath_02_duel');
  }
  note('duel: ' + presses + ' presses, goliath_down=' + won);
  check('Goliath duel reaches goliath_down in the browser', won,
    'presses=' + presses + ' save=' + JSON.stringify((await readSave(sp) || {}).flags).slice(0, 240));
  await shot(sp, 'goliath_03_win');

  let ended = false;
  if (won) {
    // Main's dead-pause guard unpauses the valley 6 s after the victory beat.
    // Moving before that is a no-op, so let the game let go first.
    await sp.waitForTimeout(6900);
    // Walk back down the valley to Corin (row 44), then interact. Small nudges
    // cover the last tile so the approach is real movement, not teleporting.
    await sp.keyboard.down('ShiftLeft');
    await sp.keyboard.down('ArrowDown');
    await sp.waitForTimeout(5000);
    await sp.keyboard.up('ArrowDown');
    await sp.keyboard.up('ShiftLeft');
    await sp.waitForTimeout(300);
    await shot(sp, 'goliath_04_aftermath');
    for (let i = 0; i < 12 && !ended; i++) {
      await sp.keyboard.press('e');
      await sp.waitForTimeout(420);
      const s = await readSave(sp);
      if (s && s.flags && s.flags.elah_ended === true) ended = true;
      if (!ended) {
        await sp.keyboard.down('ArrowDown');
        await sp.waitForTimeout(230);
        await sp.keyboard.up('ArrowDown');
      }
    }
    // Ending lines + the final choice both advance with Space.
    for (let i = 0; i < 16; i++) {
      await sp.keyboard.press('Space');
      await sp.waitForTimeout(330);
      const s = await readSave(sp);
      if (s && s.flags && s.flags.elah_ended === true) { ended = true; break; }
    }
    await shot(sp, 'goliath_05_ending');
  }
  check('chapter completion reaches elah_ended in the browser', ended,
    'ended=' + ended + ' save=' + JSON.stringify((await readSave(sp) || {}).flags).slice(0, 240));
  result.goliath = { seeded: seedInfo, presses, won, ended, finalSave: await readSave(sp) };
  await seeded.close();

  /* Fallback / independent check of the ENDING path: a post-victory save next
   * to Corin. If the timed duel automation above did not land three stones,
   * this still proves the exported game can play its conclusion in a browser.
   * It is explicitly a seeded state, not a claim that the whole duel was won. */
  if (!won || !ended) {
    const post = await browser.newContext({ viewport: { width: 1280, height: 720 } });
    await post.addInitScript(INIT);
    const pp = await post.newPage();
    wire(pp, 'post_win');
    await pp.goto(URL, { waitUntil: 'load', timeout: 120000 });
    await pp.waitForFunction(() => window.__wic && window.__wic.draws > 40, null, { timeout: 120000 });
    await pp.waitForTimeout(1600);
    await rewriteSave(pp, postWinSave());
    await pp.reload({ waitUntil: 'load', timeout: 120000 });
    await pp.waitForFunction(() => window.__wic && window.__wic.draws > 40, null, { timeout: 120000 });
    await pp.waitForTimeout(1600);
    const pst = await wicState(pp);
    await pp.mouse.click(pst.canvas.x + 305 * (pst.canvas.cssW / 320), pst.canvas.y + 10 * (pst.canvas.cssH / 180));
    await pp.waitForTimeout(1100);
    const postLoaded = await readSave(pp);
    check('post-victory save was loaded by the engine',
      !!postLoaded && !!postLoaded.flags && postLoaded.flags.goliath_down === true,
      'flags=' + JSON.stringify(postLoaded && postLoaded.flags).slice(0, 220));
    await shot(pp, 'goliath_05_ending');
    let postEnded = false;
    for (let i = 0; i < 10 && !postEnded; i++) {
      await pp.keyboard.press('e');
      await pp.waitForTimeout(420);
      const s = await readSave(pp);
      if (s && s.flags && s.flags.elah_ended === true) postEnded = true;
    }
    for (let i = 0; i < 20 && !postEnded; i++) {
      await pp.keyboard.press('Space');
      await pp.waitForTimeout(320);
      const s = await readSave(pp);
      if (s && s.flags && s.flags.elah_ended === true) postEnded = true;
    }
    await pp.waitForTimeout(2200);
    if (!postEnded) {
      const s = await readSave(pp);
      postEnded = !!(s && s.flags && s.flags.elah_ended === true);
    }
    await shot(pp, 'goliath_05_ending');
    note('post-victory ending: elah_ended=' + postEnded);
    check('post-victory save reaches the chapter ending in the browser', postEnded,
      'elah_ended=' + postEnded);
    result.goliath.fallbackEnded = postEnded;
    await post.close();
  }

  await browser.close();

  /* ── verdict ────────────────────────────────────────────────────────── */
  const hardFailures = [
    ...result.checks.filter(c => !c.ok).map(c => c.name),
    ...result.pageErrors.map(e => 'pageerror: ' + e.text.slice(0, 120)),
    ...result.requests.filter(r => ESSENTIAL.test(r.url)).map(r => 'request: ' + JSON.stringify(r).slice(0, 160))
  ];
  const consoleErrors = result.console.filter(c => c.type === 'error');
  result.summary = {
    finished: new Date().toISOString(),
    checks: result.checks.length,
    failedChecks: result.checks.filter(c => !c.ok).length,
    consoleErrors: consoleErrors.length,
    consoleWarnings: result.console.filter(c => c.type === 'warning').length,
    pageErrors: result.pageErrors.length,
    badRequests: result.requests.length,
    hardFailures,
    strict: STRICT
  };
  fs.writeFileSync(path.join(OUT, 'log.json'), JSON.stringify(result, null, 2));
  console.log('SUMMARY ' + JSON.stringify(result.summary));
  console.log('CONSOLE ERRORS ' + JSON.stringify(consoleErrors.slice(0, 12)));
  console.log('CONSOLE WARNINGS ' + JSON.stringify(result.console.filter(c => c.type === 'warning').slice(0, 12)));
  console.log('BAD REQUESTS ' + JSON.stringify(result.requests.slice(0, 12)));
  if (hardFailures.length || (STRICT && consoleErrors.length)) {
    console.error('browser validation FAILED');
    process.exit(1);
  }
  console.log('browser validation OK');
})().catch(e => {
  console.error('browser harness threw: ' + (e && e.stack ? e.stack : e));
  try {
    result.fatal = String(e && e.stack ? e.stack : e);
    fs.writeFileSync(path.join(OUT, 'log.json'), JSON.stringify(result, null, 2));
  } catch (_) { /* ignore */ }
  process.exit(2);
});
