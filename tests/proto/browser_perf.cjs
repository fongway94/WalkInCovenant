/* Real, isolated Godot Web prototype in headless Chromium/SwiftShader.
 * Four short, sequential moving trials (320, 640, 640, 320 logical width).
 * This measures draw-active requestAnimationFrame cadence, not device FPS;
 * canvas_items still renders both at the same 1280x720 browser canvas size.
 * The test-only launcher and override are created beside a downloaded export.
 */
'use strict';

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { chromium } = require('playwright');

const output = process.env.PROTO_OUT || 'build/proto-browser';
const baseUrl = process.env.PROTO_URL || 'http://127.0.0.1:8081/proto.html';
fs.mkdirSync(output, { recursive: true });
const result = {
  renderer: 'Chromium headless / ANGLE SwiftShader (software)',
  limitation: 'Draw-active browser animation-frame cadence, capped by the browser; not native/mobile FPS.',
  cpu: (os.cpus()[0] || {}).model || 'unknown',
  canvas: '1280x720, deviceScaleFactor=1; canvas_items stretch in both trials',
  chromium: null,
  trials: [],
  errors: [],
};

const instrument = () => {
  window.__prototypeProbe = { draws: 0, renderer: null };
  const getContext = HTMLCanvasElement.prototype.getContext;
  HTMLCanvasElement.prototype.getContext = function (type, ...args) {
    const gl = getContext.call(this, type, ...args);
    if (!gl || !/^(webgl2?|experimental-webgl)$/.test(type)) return gl;
    const info = gl.getExtension('WEBGL_debug_renderer_info');
    window.__prototypeProbe.renderer = info ? gl.getParameter(info.UNMASKED_RENDERER_WEBGL) : gl.getParameter(gl.RENDERER);
    const proto = Object.getPrototypeOf(gl);
    for (const name of ['clear', 'drawArrays', 'drawElements', 'drawArraysInstanced', 'drawElementsInstanced']) {
      if (typeof proto[name] !== 'function' || proto['__prototype_' + name]) continue;
      const original = proto[name];
      proto['__prototype_' + name] = true;
      proto[name] = function (...values) {
        window.__prototypeProbe.draws++;
        return original.apply(this, values);
      };
    }
    return gl;
  };
};

async function sample(page, durationMs) {
  return page.evaluate(duration => new Promise(resolve => {
    const probe = window.__prototypeProbe;
    const intervals = [];
    let start = null;
    let firstDraw = null;
    let lastDraw = null;
    let previousDraws = probe.draws;
    let rafs = 0;
    const tick = now => {
      if (start === null) start = now;
      rafs++;
      if (probe.draws > previousDraws) {
        if (lastDraw !== null) intervals.push(now - lastDraw);
        else firstDraw = now;
        lastDraw = now;
        previousDraws = probe.draws;
      }
      if (now - start >= duration) {
        intervals.sort((a, b) => a - b);
        const count = intervals.length;
        const span = lastDraw === null || firstDraw === null ? 0 : lastDraw - firstDraw;
        resolve({
          drawActiveFrames: count,
          drawActiveFps: span > 0 ? +(count * 1000 / span).toFixed(1) : 0,
          p95IntervalMs: count ? +intervals[Math.floor((count - 1) * 0.95)].toFixed(1) : null,
          maxIntervalMs: count ? +intervals[count - 1].toFixed(1) : null,
          rafCallbacks: rafs,
          elapsedMs: Math.round(now - start),
          draws: probe.draws,
          glRenderer: probe.renderer,
          moved: window.__prototypeMoved === true,
        });
      } else requestAnimationFrame(tick);
    };
    requestAnimationFrame(tick);
  }), durationMs);
}

async function trial(browser, width, index) {
  const context = await browser.newContext({ viewport: { width: 1280, height: 720 }, deviceScaleFactor: 1 });
  await context.addInitScript(instrument);
  const page = await context.newPage();
  page.on('pageerror', error => result.errors.push(`trial ${index} page: ${String(error).slice(0, 250)}`));
  page.on('console', message => {
    if (message.type() === 'error' && /SCRIPT ERROR|Parse Error|Failed loading scene/i.test(message.text())) {
      result.errors.push(`trial ${index} script: ${message.text().slice(0, 250)}`);
    }
  });
  try {
    await page.goto(`${baseUrl}?width=${width}`, { waitUntil: 'domcontentloaded', timeout: 120000 });
    // This marker is set only by the isolated scene when the requested logical
    // width is actually applied; it prevents measuring the production scene.
    await page.waitForFunction(w => window.__prototypeReady === w && window.__prototypeProbe.draws > 40,
      width, { timeout: 120000 });
    await page.waitForTimeout(2000);
    await page.locator('canvas').focus();
    await page.keyboard.down('ArrowRight');
    const stats = await sample(page, 6000);
    await page.keyboard.up('ArrowRight');
    stats.width = width;
    stats.canvasSize = await page.locator('canvas').evaluate(c => [c.width, c.height]);
    if (!stats.moved || stats.drawActiveFrames < 10 || stats.draws < 40) {
      throw new Error(`probe did not establish movement/drawing: ${JSON.stringify(stats)}`);
    }
    await page.screenshot({ path: path.join(output, `browser_${width}.png`) });
    result.trials.push(stats);
    console.log('PROTOBROWSER trial ' + JSON.stringify(stats));
  } finally {
    await context.close();
  }
}

(async () => {
  let browser;
  try {
    browser = await chromium.launch({ headless: true, args: [
      '--no-sandbox', '--disable-dev-shm-usage', '--use-gl=angle', '--use-angle=swiftshader',
      '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--enable-webgl',
      '--disable-features=WebGLDraftExtensions',
    ] });
    result.chromium = browser.version();
    const widths = [320, 640, 640, 320];
    for (let i = 0; i < widths.length; i++) await trial(browser, widths[i], i + 1);
    if (result.errors.length) throw new Error('browser page/script errors were reported');
    result.ok = true;
  } catch (error) {
    result.ok = false;
    result.fatal = String(error).slice(0, 600);
    console.error('PROTOBROWSER FAIL ' + result.fatal);
    process.exitCode = 1;
  } finally {
    if (browser) await browser.close();
    fs.writeFileSync(path.join(output, 'result.json'), JSON.stringify(result));
    console.log('PROTOBROWSER RESULT ' + JSON.stringify(result));
  }
})();
