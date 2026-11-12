/* Staged real-input browser check for the journey's timed-practice driver.
 * Run once per WIC_PRACTICE_DELAY: that delay is added before the trusted
 * Playwright key press, not to the game. The probe only publishes state.
 * Never publish the test-only browser pack. */
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require(process.env.WIC_PLAYWRIGHT || 'playwright');
const { drivePractice } = require('./practice_driver.cjs');
const root = process.env.WIC_PROBE_URL || 'http://127.0.0.1:8083/';
const out = process.env.WIC_SHEPHERD_OUT || 'build/shepherd-browser';
const delay = Number(process.env.WIC_PRACTICE_DELAY || 0);
if (!Number.isInteger(delay) || delay < 0 || delay > 1000) throw new Error('invalid WIC_PRACTICE_DELAY');
fs.mkdirSync(out, { recursive: true });
const filename = path.join(out, `practice-latency-${delay}.json`);
const result = { ok: false, delay, attempts: [], errors: [] };
const watchdog = setTimeout(() => {
  result.error = 'practice latency check timed out';
  fs.writeFileSync(filename, JSON.stringify(result, null, 2));
  process.exit(1);
}, 120000);

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

(async () => {
  const browser = await launch();
  try {
    const context = await browser.newContext({ viewport: { width: 1280, height: 720 },
      serviceWorkers: 'block' });
    const page = await context.newPage();
    page.on('pageerror', e => result.errors.push(e.message));
    page.on('console', m => { if (m.type() === 'error') result.errors.push(m.text()); });
    await page.goto(new URL('setpiece-probe.html?scene=practice', root).href,
      { waitUntil: 'load', timeout: 120000 });
    await page.waitForFunction(() => window.__setpieceProbe?.ready, null, { timeout: 120000 });
    // The standalone scene publishes faster than the journey probe. Mirror its
    // read-only state at the journey's 80 ms cadence, with the same shape.
    await page.evaluate(() => {
      window.__practiceLatency = { practice: window.__setpieceProbe };
      setInterval(() => {
        const v = window.__setpieceProbe;
        window.__practiceLatency = { practice: v && !v.done ? v : null };
      }, 80);
    });
    const original = page.keyboard.press.bind(page.keyboard);
    page.keyboard.press = async (...args) => {
      if (delay) await page.waitForTimeout(delay);
      return original(...args);
    };
    await drivePractice(page, '__practiceLatency', shot => result.attempts.push(shot));
    result.final = await page.evaluate(() => window.__setpieceProbe);
    if (!result.final?.done || result.final.hits !== 3 || result.errors.length) {
      throw new Error('practice did not complete with three real hits and no browser errors');
    }
    result.ok = true;
    console.log(`PASS real practice at ${delay} ms added key latency: ` +
      `${result.final.hits} hits, ${result.final.misses} misses`);
    await context.close();
  } finally { await browser.close(); }
})().catch(e => {
  result.error = String(e && e.stack ? e.stack : e);
  console.error(result.error);
}).finally(() => {
  clearTimeout(watchdog);
  fs.writeFileSync(filename, JSON.stringify(result, null, 2));
  if (!result.ok) process.exitCode = 1;
});
