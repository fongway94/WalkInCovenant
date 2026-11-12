/* Real UI/save regression on a disposable test-only pack. The initial completed
 * save is deliberately seeded; all subsequent buttons, dialogue, scene reloads
 * and browser reloads use the production code and real inputs. Touch is emulated,
 * not a physical-device playtest. Never publish the probe pack. */
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require(process.env.WIC_PLAYWRIGHT || 'playwright');
const root = process.env.WIC_PROBE_URL || 'http://127.0.0.1:8083/';
const out = process.env.WIC_SHEPHERD_OUT || 'build/shepherd-browser';
fs.mkdirSync(out, { recursive: true });
const result = { ok: false, checks: [], errors: [] };
function check(ok, message) {
  if (!ok) throw new Error(message);
  result.checks.push(message);
  console.log('PASS replay browser: ' + message);
}
async function launch() {
  const options = { headless: true, args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] };
  if (process.env.WIC_SPARTICUZ === '1') {
    const bundled = require('@sparticuz/chromium').default;
    options.executablePath = await bundled.executablePath();
    options.args = [...bundled.args, ...options.args];
  }
  return chromium.launch(options);
}
const state = page => page.evaluate(() => window.__journeySlotsProbe);
async function wait(page, fn, label, timeout = 45000) {
  try { await page.waitForFunction(fn, null, { timeout }); }
  catch (_) { throw new Error(`${label}: ${JSON.stringify(await state(page)).slice(0, 2500)}`); }
  return state(page);
}
async function tap(page, property) {
  const s = await state(page);
  const [x, y, w, h] = s[property];
  const canvas = await page.locator('canvas').boundingBox();
  await page.touchscreen.tap(canvas.x + (x + w / 2) * canvas.width / s.viewport[0],
    canvas.y + (y + h / 2) * canvas.height / s.viewport[1]);
  await page.waitForTimeout(180);
}
async function openBook(page) {
  await tap(page, 'journal_button');
  await wait(page, () => window.__journeySlotsProbe?.journal_open, 'opening the book');
}
async function confirmSwitch(page, from, to) {
  const previous = await state(page);
  await tap(page, 'journey_button');
  let s = await wait(page, () => window.__journeySlotsProbe?.confirming, 'asking to switch');
  check(s.slot === from && s.book_body.length > 1, `${from}: a separate explanation appears before switching`);
  await page.waitForTimeout(700);
  s = await state(page);
  check(s.slot === from && s.confirming, `${from}: one touch cannot also confirm`);
  await tap(page, 'journey_button');
  await wait(page, () => window.__journeySlotsProbe?.boot > 1 &&
    window.__journeySlotsProbe?.slot !== undefined && !window.__journeySlotsProbe?.journal_open,
  'reloading the selected journey');
  s = await state(page);
  check(s.boot > previous.boot && s.slot === to && !s.journey_error, `${from}: the confirmed switch opens ${to}`);
  return s;
}
async function finishOpeningConversation(page) {
  for (let i = 0; i < 38; i++) {
    const s = await state(page);
    if (s.talked_corin && !s.dialogue) return s;
    if (!s.talked_corin && !s.dialogue && s.target_kind !== 'npc') {
      throw new Error(`first person is not in reach: ${JSON.stringify(s)}`);
    }
    await page.keyboard.press('Space');
    await page.waitForTimeout(330);
  }
  throw new Error('could not finish the first real conversation: ' + JSON.stringify(await state(page)));
}

const watchdog = setTimeout(() => {
  result.error = 'replay browser test timed out';
  fs.writeFileSync(path.join(out, 'journey-slots-result.json'), JSON.stringify(result, null, 2));
  process.exit(1);
}, 240000);

(async () => {
  const browser = await launch();
  const context = await browser.newContext({ viewport: { width: 844, height: 390 },
    deviceScaleFactor: 1, hasTouch: true, isMobile: true, serviceWorkers: 'block' });
  const page = await context.newPage();
  page.on('pageerror', e => result.errors.push(e.message));
  page.on('console', m => { if (m.type() === 'error') result.errors.push(m.text()); });
  try {
    await page.goto(new URL('journey-slots-probe.html?seed=complete', root).href,
      { waitUntil: 'load', timeout: 120000 });
    let s = await wait(page, () => window.__journeySlotsProbe?.ready &&
      window.__journeySlotsProbe?.objective?.length > 0, 'booting completed journey', 120000);
    check(s.slot === 'original' && s.ended && s.act === 'done' && !s.runner_running,
      'a completed save boots into free roam, not a new mission');
    check(s.objective.includes('重玩') && s.original_keepsake && s.level === 3,
      'the completed objective points to replay and the original rewards remain');
    await page.waitForTimeout(3000);
    await page.screenshot({ path: path.join(out, 'replay-completed-phone.png') });
    await openBook(page);
    s = await state(page);
    check(s.journey_text === '从头重玩', 'the replay action is visible in the book');
    await page.screenshot({ path: path.join(out, 'replay-book-phone.png') });
    await tap(page, 'language_button');
    s = await wait(page, () => window.__journeySlotsProbe?.language === 'en', 'switching language with book open');
    check(s.journal_open && s.journey_text === 'Start replay' && s.book_body.some(t => t.includes('Story complete')),
      'the visible language switch translates the open book and objective');
    await tap(page, 'language_button');
    await wait(page, () => window.__journeySlotsProbe?.language === 'zh', 'restoring Chinese with book open');
    await tap(page, 'journey_button');
    await wait(page, () => window.__journeySlotsProbe?.confirming, 'opening confirmation');
    await tap(page, 'close_button');
    s = await state(page);
    check(s.journal_open && !s.confirming && s.slot === 'original' && !s.has_replay,
      'cancel returns to the book without creating or changing a save');
    s = await confirmSwitch(page, 'original', 'replay');
    check(!s.ended && s.level === 1 && !s.original_keepsake,
      'the new replay starts from the beginning, separately from the completed save');
    await page.waitForTimeout(3000);
    await page.screenshot({ path: path.join(out, 'replay-fresh-phone.png') });
    s = await finishOpeningConversation(page);
    check(s.talked_corin, 'a real opening conversation advances the replay');
    await tap(page, 'sound_button');
    s = await wait(page, () => window.__journeySlotsProbe?.sound_enabled === false, 'muting the replay');
    check(!s.music_enabled && s.sound_text === '静' && s.sfx_bus_muted && s.music_bus_muted,
      'the real sound button mutes the replay and its two audio buses');
    await openBook(page);
    s = await confirmSwitch(page, 'replay', 'original');
    check(s.ended && s.act === 'done' && s.original_keepsake && s.level === 3 &&
      s.words.includes('original_keepsake'), 'returning restores the original completion and rewards');
    check(s.sound_enabled && s.music_enabled && s.sound_text === '音' && !s.focus_muted &&
      !s.sfx_bus_muted && !s.music_bus_muted, 'switching restores the original sound and unmutes both buses');
    await openBook(page);
    s = await confirmSwitch(page, 'original', 'replay');
    check(s.talked_corin && !s.ended, 'returning to replay restores its own conversation progress');
    check(!s.sound_enabled && !s.music_enabled && s.sound_text === '静' &&
      s.sfx_bus_muted && s.music_bus_muted, 'switching back restores the replay mute on both buses');
    await page.waitForTimeout(2500);
    await page.reload({ waitUntil: 'load', timeout: 120000 });
    s = await wait(page, () => window.__journeySlotsProbe?.ready &&
      window.__journeySlotsProbe?.slot === 'replay', 'browser reload', 120000);
    check(s.talked_corin && !s.ended, 'a full browser reload resumes the selected replay');
    check(!s.sound_enabled && s.sfx_bus_muted && s.music_bus_muted,
      'a full browser reload also preserves the replay mute');
    await openBook(page);
    s = await confirmSwitch(page, 'replay', 'original');
    await page.waitForTimeout(2500);
    await page.reload({ waitUntil: 'load', timeout: 120000 });
    s = await wait(page, () => window.__journeySlotsProbe?.ready &&
      window.__journeySlotsProbe?.slot === 'original', 'original browser reload', 120000);
    check(s.ended && s.original_keepsake && s.level === 3, 'a browser reload also preserves the original journey');
    check(result.errors.length === 0, 'no page or console errors');
    result.ok = true;
  } catch (e) {
    result.error = String(e && e.stack ? e.stack : e);
    await page.screenshot({ path: path.join(out, 'replay-failure-phone.png') }).catch(() => {});
    console.error(result.error);
  } finally {
    await context.close().catch(() => {});
    await browser.close().catch(() => {});
  }

  // A separate browser context starts with deliberately unreadable original
  // bytes. It exercises the real boot, warning and automatic-save path, then
  // reloads the page to prove those original bytes were not replaced.
  if (result.ok) {
    result.ok = false;
    const recoveryBrowser = await launch();
    const recoveryContext = await recoveryBrowser.newContext({ viewport: { width: 844, height: 390 },
      deviceScaleFactor: 1, hasTouch: true, isMobile: true, serviceWorkers: 'block' });
    const recoveryPage = await recoveryContext.newPage();
    const expectedWarnings = [];
    let awaitingWarningLocation = false;
    recoveryPage.on('pageerror', e => result.errors.push(e.message));
    recoveryPage.on('console', m => {
      if (m.type() !== 'error') return;
      const text = m.text().trim();
      // Godot forwards push_warning to console.error as two messages. This
      // exact warning is expected only for the intentionally damaged fixture;
      // unexpected errors and unrelated warnings still fail the test.
      if (text === 'WARNING: GameState: saved journey is unreadable; autosaving is disabled to protect it') {
        expectedWarnings.push(text);
        awaitingWarningLocation = true;
      } else if (awaitingWarningLocation && text.startsWith('at: push_warning (')) {
        awaitingWarningLocation = false;
      } else {
        awaitingWarningLocation = false;
        result.errors.push(m.text());
      }
    });
    try {
      await recoveryPage.goto(new URL('journey-slots-probe.html?seed=corrupt', root).href,
        { waitUntil: 'load', timeout: 120000 });
      let s = await wait(recoveryPage, () => window.__journeySlotsProbe?.ready &&
        window.__journeySlotsProbe?.save_protected && window.__journeySlotsProbe?.journal_open,
      'booting the protected journey', 120000);
      check(s.corrupt_original_intact && s.journey_disabled &&
        s.book_body.some(t => t.includes('本次进度不会保存')),
      'an unreadable save opens a clear warning and disables journey switching');
      await recoveryPage.waitForTimeout(3000);
      await recoveryPage.screenshot({ path: path.join(out, 'replay-save-warning-phone.png') });
      await tap(recoveryPage, 'language_button');
      s = await wait(recoveryPage, () => window.__journeySlotsProbe?.language === 'en', 'translating save warning');
      check(s.journal_open && s.book_body.some(t => t.includes('progress this session will not be saved')),
        'the warning translates without closing the book');
      await tap(recoveryPage, 'close_button');
      await wait(recoveryPage, () => !window.__journeySlotsProbe?.journal_open, 'closing the warning');
      await recoveryPage.waitForTimeout(4000);
      s = await state(recoveryPage);
      check(s.save_protected && s.corrupt_original_intact,
        'ordinary timed autosaves do not overwrite unreadable original bytes');
      await recoveryPage.reload({ waitUntil: 'load', timeout: 120000 });
      s = await wait(recoveryPage, () => window.__journeySlotsProbe?.ready &&
        window.__journeySlotsProbe?.journal_open, 'reloading the protected journey', 120000);
      check(s.save_protected && s.corrupt_original_intact && s.journey_disabled,
        'a full browser reload keeps the original bytes and shows the warning again');
      check(expectedWarnings.length >= 2, 'the deliberately unreadable save is reported on each boot');
      result.expected_recovery_warnings = expectedWarnings.length;
      check(result.errors.length === 0, 'no unexpected browser page or console errors during recovery');
      result.ok = true;
    } catch (e) {
      result.error = String(e && e.stack ? e.stack : e);
      await recoveryPage.screenshot({ path: path.join(out, 'replay-recovery-failure-phone.png') }).catch(() => {});
      console.error(result.error);
    } finally {
      await recoveryContext.close().catch(() => {});
      await recoveryBrowser.close().catch(() => {});
    }
  }
})().catch(e => { result.error = String(e && e.stack ? e.stack : e); console.error(result.error); })
  .finally(() => {
    clearTimeout(watchdog);
    fs.writeFileSync(path.join(out, 'journey-slots-result.json'), JSON.stringify(result, null, 2));
    if (!result.ok) process.exitCode = 1;
  });
