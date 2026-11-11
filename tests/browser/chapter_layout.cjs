/* Rendered layout regressions against the disposable browser-test pack.
 * The shepherd fixture stages the field; resizes happen in one live page and
 * emulated touch moves David and counts one sheep. The world fixture leaves
 * ambient chatter on its normal cooldown. A real HUD click switches language,
 * then we observe every page of an authored line. A staged brook fixture also
 * checks the rendered feedback contrast in both languages. These are not a
 * playthrough; shepherd_journey.cjs covers progression.
 *
 * WIC_PROBE_URL=http://127.0.0.1:8083/ node tests/browser/chapter_layout.cjs
 * Local sandboxes may also set WIC_PLAYWRIGHT=playwright-core, WIC_SPARTICUZ=1,
 * NODE_PATH and LD_LIBRARY_PATH as described in docs/AGENT_CONTINUATION.md.
 */
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require(process.env.WIC_PLAYWRIGHT || 'playwright');
const root = process.env.WIC_PROBE_URL || 'http://127.0.0.1:8083/';
const out = process.env.WIC_SHEPHERD_OUT || 'build/shepherd-browser';
const result = { ok: false, viewports: [], touch: null, chatter: [], brook: [], errors: [] };
fs.mkdirSync(out, { recursive: true });

function assert(ok, message) {
  if (!ok) throw new Error(message);
  console.log('PASS ' + message);
}

function overlaps([x, y, w, h], [a, b, c, d]) {
  return x < a + c && x + w > a && y < b + d && y + h > b;
}

function checkBubble(state, bubble) {
  const [x, y, w, h] = bubble.rect;
  const [vw, vh] = state.viewport;
  return x >= 1 && x + w <= vw - 1 && y >= 59.9 && y + h <= vh - 44.9 &&
    bubble.panel_width <= 112 && bubble.text_width <= bubble.label_width + 0.1 &&
    !overlaps(bubble.rect, bubble.speaker_rect) && !overlaps(bubble.rect, bubble.player_rect);
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
  page.on('pageerror', e => result.errors.push(`${label}: ${e.message}`));
  page.on('console', m => { if (m.type() === 'error') result.errors.push(`${label}: ${m.text()}`); });
  return { context, page };
}

async function fieldResize(browser) {
  const { context, page } = await makePage(browser, 'field');
  try {
    await page.goto(new URL('shepherd-probe.html', root).href, { waitUntil: 'load', timeout: 120000 });
    await page.waitForFunction(() => window.__shepherdProbe?.ready, null, { timeout: 120000 });
    for (const [width, height] of [[1280, 720], [960, 540], [1024, 768], [844, 390], [1280, 720]]) {
      await page.setViewportSize({ width, height });
      // Wait for both the browser canvas and Godot's logical aspect/zoom to
      // catch up; a stale pre-resize telemetry sample must not pass.
      await page.waitForFunction(({ width: w, height: h }) => {
        const s = window.__shepherdProbe;
        const canvas = document.querySelector('canvas');
        if (!s?.field || !canvas) return false;
        const r = canvas.getBoundingClientRect();
        const [vw, vh] = s.viewport, [, , bw, bh] = s.field_bounds;
        const expected = Math.max(0.9, (vw + 2) / bw, (vh + 2) / bh);
        return Math.abs(r.width - w) < 2 && Math.abs(r.height - h) < 2 &&
          Math.abs(vw / vh - w / h) < 0.015 && Math.abs(s.camera_zoom - expected) < 0.01;
      }, { width, height }, { timeout: 20000 });
      await page.waitForTimeout(250);
      const s = await page.evaluate(() => window.__shepherdProbe);
      const [vw, vh] = s.viewport, [cx, cy] = s.camera;
      const [bx, by, bw, bh] = s.field_bounds, z = s.camera_zoom;
      const covered = cx - vw / (2 * z) >= bx - 0.6 && cx + vw / (2 * z) <= bx + bw + 0.6 &&
        cy - vh / (2 * z) >= by - 0.6 && cy + vh / (2 * z) <= by + bh + 0.6;
      assert(covered, `live resize ${width}x${height} keeps the field covered`);
      result.viewports.push({ width, height, viewport: s.viewport, zoom: z, covered });
      await page.screenshot({ path: path.join(out, `layout_resize_${width}x${height}.png`) });
    }
  } catch (e) {
    await page.screenshot({ path: path.join(out, 'layout_field_failure.png') }).catch(() => {});
    throw e;
  } finally {
    await context.close();
  }
}

// Touch is emulated by Chromium, not a physical-device test. CDP sends an
// actual touch drag to the floating stick; the on-screen A is tapped separately.
async function touchField(browser) {
  const context = await browser.newContext({ viewport: { width: 844, height: 390 },
    deviceScaleFactor: 2, hasTouch: true, isMobile: true, serviceWorkers: 'block' });
  const page = await context.newPage();
  page.on('pageerror', e => result.errors.push(`touch: ${e.message}`));
  page.on('console', m => { if (m.type() === 'error') result.errors.push(`touch: ${m.text()}`); });
  let lastState = null;
  try {
    const cdp = await context.newCDPSession(page);
    await page.goto(new URL('shepherd-probe.html', root).href, { waitUntil: 'load', timeout: 120000 });
    await page.waitForFunction(() => window.__shepherdProbe?.ready, null, { timeout: 120000 });
    const state = async () => {
      lastState = await page.evaluate(() => window.__shepherdProbe);
      return lastState;
    };
    async function drag(direction, ms) {
      const origin = { x: 115, y: 230 };
      const [dx, dy] = { left: [-90, 0], right: [90, 0], up: [0, -90], down: [0, 90] }[direction];
      await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ ...origin, id: 1 }] });
      try {
        await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove',
          touchPoints: [{ x: origin.x + dx, y: origin.y + dy, id: 1 }] });
        await page.waitForTimeout(ms);
      } finally {
        await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
      }
      await page.waitForTimeout(120);
    }
    const initial = await state();
    assert(initial.count === 0 && initial.animals.length === 3, 'the touch fixture begins with three sheep');
    await drag('left', 350);
    let s = await state();
    const distanceMoved = Math.hypot(s.player[0] - initial.player[0], s.player[1] - initial.player[1]);
    assert(distanceMoved > 2, 'an emulated touch drag moves the shepherd');
    let previous = null, blocked = 0, tapped = '', directBefore = 0;
    for (let i = 0; i < 100 && tapped === ''; i++) {
      if (s.paused) throw new Error('touch field unexpectedly paused');
      if (s.target_kind === 'flock') {
        const target = s.target;
        const claimedBefore = new Set(s.claimed.map(a => a.id));
        directBefore = s.claimed.filter(a => !a.guided).length;
        const [vw, vh] = s.viewport;
        const canvas = await page.locator('canvas').boundingBox();
        await page.touchscreen.tap(canvas.x + (vw - 30) * canvas.width / vw,
          canvas.y + (vh - 26) * canvas.height / vh);
        await page.waitForTimeout(350);
        s = await state();
        const newlyCounted = s.claimed.filter(a => !a.guided && !claimedBefore.has(a.id));
        if (newlyCounted.length) {
          assert(newlyCounted.length === 1 && newlyCounted[0].id === target,
            'the on-screen A counts the selected sheep, rather than guiding it');
          tapped = target;
          break;
        }
      } else {
        // Herding is a valid separate mechanic: another animal may reach the
        // fold while the touch driver approaches. Continue until an A tap is
        // proven by the selected sheep's non-guided pickup flag.
        const animal = s.animals.map(a => ({ ...a,
          distance: Math.hypot(a.pos[0] - s.player[0], a.pos[1] - s.player[1]) }))
          .sort((a, b) => a.distance - b.distance)[0];
        if (!animal) throw new Error('touch field has no selectable sheep');
        const dx = animal.pos[0] - s.player[0], dy = animal.pos[1] - s.player[1];
        let direction = Math.abs(dx) > Math.abs(dy) ? (dx < 0 ? 'left' : 'right')
          : (dy < 0 ? 'up' : 'down');
        blocked = previous && Math.hypot(s.player[0] - previous[0], s.player[1] - previous[1]) < 2
          ? blocked + 1 : 0;
        if (blocked >= 3) {
          direction = Math.abs(dx) > Math.abs(dy) ? (dy < 0 ? 'up' : 'down')
            : (dx < 0 ? 'left' : 'right');
          blocked = 0;
        }
        previous = s.player;
        await drag(direction, 450);
        s = await state();
      }
    }
    assert(tapped !== '', 'a real touch action counted a sheep');
    await page.waitForTimeout(1000);
    s = await state();
    assert(s.claimed.filter(a => !a.guided).length === directBefore + 1,
      'one touch does not directly count a second sheep');
    result.touch = { viewport: [844, 390], distance_moved: distanceMoved, counted: tapped,
      count: s.count, claimed: s.claimed };
    await page.screenshot({ path: path.join(out, 'layout_touch_sheep.png') });
  } catch (e) {
    if (lastState) result.touch_failure_state = { player: lastState.player, count: lastState.count,
      target: lastState.target, target_kind: lastState.target_kind, claimed: lastState.claimed,
      animals: lastState.animals, paused: lastState.paused };
    await page.screenshot({ path: path.join(out, 'layout_touch_failure.png') }).catch(() => {});
    throw e;
  } finally {
    await context.close();
  }
}

// Read a screenshot in a separate browser canvas, so this measures rendered
// pixels rather than a colour claimed by the production script. Median is the
// panel background; the 99th percentile samples the bright text strokes.
async function screenshotContrast(page, screenshot, boxes) {
  return page.evaluate(async ({ png, boxes: rects }) => {
    const image = new Image();
    image.src = 'data:image/png;base64,' + png;
    await image.decode();
    const scratch = document.createElement('canvas');
    scratch.width = image.naturalWidth;
    scratch.height = image.naturalHeight;
    const context = scratch.getContext('2d', { willReadFrequently: true });
    context.drawImage(image, 0, 0);
    const sx = scratch.width / window.innerWidth, sy = scratch.height / window.innerHeight;
    const luminance = (r, g, b) => {
      const linear = c => { c /= 255; return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4; };
      return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b);
    };
    return rects.map(rect => {
      const x = Math.max(0, Math.floor(rect.x * sx)), y = Math.max(0, Math.floor(rect.y * sy));
      const w = Math.min(scratch.width - x, Math.ceil(rect.w * sx));
      const h = Math.min(scratch.height - y, Math.ceil(rect.h * sy));
      if (w < 2 || h < 2) throw new Error('empty screenshot sample');
      const pixels = context.getImageData(x, y, w, h).data;
      const light = [];
      for (let i = 0; i < pixels.length; i += 4)
        light.push(luminance(pixels[i], pixels[i + 1], pixels[i + 2]));
      light.sort((a, b) => a - b);
      const background = light[Math.floor(light.length * 0.50)];
      const foreground = light[Math.floor(light.length * 0.99)];
      return { background, foreground, ratio: (foreground + 0.05) / (background + 0.05) };
    });
  }, { png: screenshot.toString('base64'), boxes });
}

async function brookFeedback(browser, width, height, language) {
  const { context, page } = await makePage(browser, `brook-${language}`);
  try {
    await page.setViewportSize({ width, height });
    const url = new URL('setpiece-probe.html', root);
    url.searchParams.set('scene', 'brook');
    url.searchParams.set('lang', language);
    await page.goto(url.href, { waitUntil: 'load', timeout: 120000 });
    await page.waitForFunction(() => window.__setpieceProbe?.ready, null, { timeout: 120000 });
    for (let count = 1; count <= 5; count++) {
      await page.keyboard.press('ArrowRight');
      await page.keyboard.press('Space');
      await page.waitForFunction(n => window.__setpieceProbe?.chosen === n, count, { timeout: 10000 });
    }
    const s = await page.evaluate(() => window.__setpieceProbe);
    const expected = language === 'zh' ? '手里有五块了。就要这些？' : 'Five in your hand. Keep these?';
    assert(s.full && s.language === language && s.message === expected,
      `brook shows the authored ${language} feedback after five keyboard selections`);
    const canvas = await page.locator('canvas').boundingBox();
    const [vw, vh] = s.viewport, [x, y, w, h] = s.message_rect;
    const [hx, hy, hw, hh] = s.hint_rect;
    const cssRect = (a, b, c, d) => ({ x: canvas.x + a * canvas.width / vw,
      y: canvas.y + b * canvas.height / vh, w: c * canvas.width / vw, h: d * canvas.height / vh });
    const screenshot = await page.screenshot({ path: path.join(out, `layout_brook_${language}.png`) });
    const [message, hint] = await screenshotContrast(page, screenshot,
      [cssRect(x, y, w, h), cssRect(hx, hy, hw, hh)]);
    assert(message.ratio >= 4.5, `brook ${language} feedback has rendered text contrast`);
    assert(hint.ratio >= 4.5, `brook ${language} instruction has rendered text contrast`);
    result.brook.push({ language, viewport: [width, height], message, hint });
  } catch (e) {
    await page.screenshot({ path: path.join(out, `layout_brook_${language}_failure.png`) }).catch(() => {});
    throw e;
  } finally {
    await context.close();
  }
}

async function ordinaryChatter(browser) {
  const { context, page } = await makePage(browser, 'chatter');
  try {
    await page.goto(new URL('world-probe.html?place=spawn', root).href,
      { waitUntil: 'load', timeout: 120000 });
    await page.waitForFunction(() => window.__worldProbe?.ready, null, { timeout: 120000 });
    let s = await page.evaluate(() => window.__worldProbe);
    if (s.language !== 'en') {
      // Click the real language button; telemetry supplies its logical rect.
      const [x, y, w, h] = s.language_button;
      const canvas = await page.locator('canvas').boundingBox();
      await page.mouse.click(canvas.x + (x + w / 2) * canvas.width / s.viewport[0],
        canvas.y + (y + h / 2) * canvas.height / s.viewport[1]);
      await page.waitForFunction(() => window.__worldProbe?.language === 'en', null, { timeout: 10000 });
    }
    assert((await page.evaluate(() => window.__worldProbe.language)) === 'en',
      'the real language button selects English');
    // Corin's first line was previously clipped after "day". It appears by
    // the production timer, without a test calling emote or altering cooldowns.
    await page.waitForFunction(() => window.__worldProbe?.bubbles?.some(
      b => b.id === 'corin' && b.page === 0), null, { timeout: 45000 });
    s = await page.evaluate(() => window.__worldProbe);
    const first = s.bubbles.find(b => b.id === 'corin');
    assert(first.pages > 1, 'long ambient chatter has more than one page');
    for (let index = 0; index < first.pages; index++) {
      if (index > 0) {
        await page.waitForFunction(i => window.__worldProbe?.bubbles?.some(
          b => b.id === 'corin' && b.page === i), index, { timeout: 10000 });
      }
      s = await page.evaluate(() => window.__worldProbe);
      const bubble = s.bubbles.find(b => b.id === 'corin' && b.page === index);
      assert(!!bubble && checkBubble(s, bubble), `ambient chatter page ${index + 1} fits and clears both actors`);
      result.chatter.push(bubble);
      await page.screenshot({ path: path.join(out, `layout_chatter_${index + 1}.png`) });
    }
    assert(result.chatter.map(b => b.text).join(' ') === '“The ink ran out on day nineteen.”',
      'natural chatter displays the complete authored line');
  } catch (e) {
    await page.screenshot({ path: path.join(out, 'layout_chatter_failure.png') }).catch(() => {});
    throw e;
  } finally {
    await context.close();
  }
}

async function runIsolated(test) {
  const browser = await launch();
  try { await test(browser); } finally { await browser.close(); }
}

// An unresolved browser promise must not let Node exit successfully without a
// verdict. The CI step has its own timeout; this also protects local runners.
const watchdog = setTimeout(() => {
  result.error = 'layout browser harness timed out before producing a verdict';
  fs.writeFileSync(path.join(out, 'layout-result.json'), JSON.stringify(result, null, 2));
  console.error(result.error);
  process.exit(1);
}, 300000);

(async () => {
  await runIsolated(fieldResize);
  await runIsolated(touchField);
  await runIsolated(ordinaryChatter);
  await runIsolated(browser => brookFeedback(browser, 1280, 720, 'zh'));
  await runIsolated(browser => brookFeedback(browser, 844, 390, 'en'));
  assert(result.errors.length === 0, 'no browser page or console errors in the layout probes');
  result.ok = true;
})().catch(e => {
  result.error = String(e && e.stack ? e.stack : e);
  console.error(result.error);
}).finally(() => {
  clearTimeout(watchdog);
  fs.writeFileSync(path.join(out, 'layout-result.json'), JSON.stringify(result, null, 2));
  if (!result.ok) process.exitCode = 1;
});
