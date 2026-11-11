/* Browser smoke test of the separately hosted temporary field preview.
 * Run with PUBLIC_PREVIEW_URL and NODE_PATH pointing at playwright + pngjs.
 * It validates the public URL, keyboard/touch movement and the flock counter;
 * it does not deploy or exercise the production game.
 */
'use strict';

const { chromium } = require('playwright');
const { PNG } = require('pngjs');

const url = process.env.PUBLIC_PREVIEW_URL;
if (!url) throw new Error('PUBLIC_PREVIEW_URL is required');

function changedPixels(a, b) {
  const first = PNG.sync.read(a), second = PNG.sync.read(b);
  if (first.width !== second.width || first.height !== second.height) throw new Error('Screenshot sizes differ');
  let changed = 0;
  for (let i = 0; i < first.data.length; i += 4) {
    if (Math.max(...[0, 1, 2].map(channel => Math.abs(first.data[i + channel] - second.data[i + channel]))) > 35) changed++;
  }
  return changed;
}

async function trial(browser, mobile) {
  const name = mobile ? 'mobile' : 'desktop';
  const context = await browser.newContext({
    viewport: mobile ? { width: 812, height: 375 } : { width: 1280, height: 720 },
    deviceScaleFactor: 1, hasTouch: mobile, isMobile: mobile,
  });
  const page = await context.newPage();
  const errors = [], downloads = [];
  page.on('pageerror', error => errors.push(String(error).slice(0, 300)));
  page.on('console', msg => {
    if (msg.type() === 'error') errors.push(msg.text().slice(0, 300));
  });
  page.on('response', response => {
    if (response.url().includes('/git/blobs/')) downloads.push(response.status());
  });
  try {
    const response = await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 120000 });
    if (!response || response.status() !== 200) throw new Error('Preview page returned HTTP ' + (response && response.status()));
    await page.waitForFunction(() => window.__prototypeReady === 640 ||
      document.getElementById('message')?.textContent?.startsWith('Could not open'), null, { timeout: 180000 });
    const ready = await page.evaluate(() => ({ready: window.__prototypeReady, message: document.getElementById('message')?.textContent}));
    if (ready.ready !== 640) throw new Error(ready.message || 'Prototype did not become ready');
    const beforeControl = await page.locator('#touch').isVisible();
    if (mobile && !beforeControl) await page.locator('#touch.visible').waitFor({ state: 'visible', timeout: 30000 });
    if (!mobile && beforeControl) throw new Error('Touch controls unexpectedly visible on desktop');

    let cdp;
    async function holdLeft(ms, untilMoved = false) {
      if (mobile) {
        const box = await page.locator('#touch .left').boundingBox();
        if (!box) throw new Error('Touch control is not visible');
        cdp = cdp || await context.newCDPSession(page);
        await cdp.send('Input.dispatchTouchEvent', {type: 'touchStart', touchPoints: [{x: box.x + box.width / 2, y: box.y + box.height / 2, id: 7}]});
      } else {
        await page.locator('canvas').focus();
        await page.keyboard.down('ArrowLeft');
      }
      if (untilMoved) await page.waitForFunction(() => window.__prototypeMoved === true, null, {timeout: 30000});
      await page.waitForTimeout(ms);
      if (mobile) await cdp.send('Input.dispatchTouchEvent', {type: 'touchEnd', touchPoints: []});
      else await page.keyboard.up('ArrowLeft');
    }
    await holdLeft(500, true);
    const clip = mobile ? {x: 700, y: 7, width: 16, height: 25} : {x: 1068, y: 24, width: 20, height: 35};
    let difference = 0;
    for (let attempt = 0; attempt < 3 && difference < 10; attempt++) {
      if (attempt) await holdLeft(350);
      await page.waitForTimeout(1800);
      const before = await page.screenshot({clip});
      if (mobile) await page.locator('#touch .count').tap();
      else await page.keyboard.press('Space');
      await page.waitForTimeout(350);
      difference = changedPixels(before, await page.screenshot({clip}));
    }
    if (difference < 10) throw new Error('Counting a nearby sheep did not update the HUD');
    if (errors.length) throw new Error('Browser errors: ' + errors.join(' | '));
    return {name, ready: true, moved: true, counterChangedPixels: difference, downloads, errors};
  } catch (error) {
    const status = await page.locator('body').innerText().catch(() => '');
    throw new Error(name + ': ' + error.message + '; page: ' + status.slice(0, 400) + '; errors: ' + errors.join(' | '));
  } finally {
    await context.close();
  }
}

(async () => {
  let browser;
  try {
    browser = await chromium.launch({headless: true, args: [
      '--no-sandbox', '--disable-dev-shm-usage', '--use-gl=angle', '--use-angle=swiftshader',
      '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--enable-webgl',
    ]});
    const result = {browser: browser.version(), trials: []};
    result.trials.push(await trial(browser, false));
    await browser.close();
    browser = await chromium.launch({headless: true, args: [
      '--no-sandbox', '--disable-dev-shm-usage', '--use-gl=angle', '--use-angle=swiftshader',
      '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--enable-webgl',
    ]});
    result.trials.push(await trial(browser, true));
    console.log('PUBLIC_PREVIEW ' + JSON.stringify(result));
  } catch (error) {
    console.error('PUBLIC_PREVIEW_FAIL ' + String(error));
    process.exitCode = 1;
  } finally {
    if (browser) await browser.close();
  }
})();
