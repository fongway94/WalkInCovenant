'use strict';

/* Drive the real timed practice with trusted Playwright key presses. The
 * browser-only probe is read-only and publishes at intervals, so a slow WebGL
 * frame or Playwright round-trip can put the real marker past its reported
 * position. Lead the sweep and adapt only after a registered miss; do not set
 * the marker, score, time or input handler. The caller must wait for practice
 * to appear before calling this function. */
async function drivePractice(page, probeKey, onShot = () => {}) {
  const leads = [0.08, 0.16, 0.24, 0.32, 0.04, 0.12, 0.20, 0.28, 0.36];
  let leadIndex = 0;
  const attempts = [];
  const read = () => page.evaluate(k => window[k], probeKey);
  const waitClosed = () => page.waitForFunction(k => window[k] && !window[k].practice,
    probeKey, { timeout: 15000, polling: 20 });

  for (let i = 0; i < 30; i++) {
    const lead = leads[leadIndex % leads.length];
    await page.waitForFunction(({ key, distance }) => {
      const v = window[key];
      if (!v) return false;
      if (!v.practice || v.practice.hits >= 3) return true;
      const q = v.practice;
      const target = 0.5 - Math.sign(q.direction) * distance;
      return q.phase === 0 && Math.abs(q.marker - target) <= 0.05;
    }, { key: probeKey, distance: lead }, { timeout: 30000, polling: 20 });
    const current = await read();
    if (!current.practice) return attempts;
    if (current.practice.hits >= 3) {
      await waitClosed();
      return attempts;
    }
    if (current.practice.phase !== 0) continue;
    const before = current.practice;
    await page.keyboard.press('Space');
    // A shot must actually register. In particular, a blocked or lost key may
    // not be counted as an attempt just because the marker crossed the band.
    await page.waitForFunction(({ key, hits, misses }) => {
      const v = window[key];
      return v && (!v.practice || v.practice.hits > hits || v.practice.misses > misses);
    }, { key: probeKey, hits: before.hits, misses: before.misses }, { timeout: 5000, polling: 20 });
    const next = await read();
    const after = next.practice;
    const shot = { lead, before, after };
    attempts.push(shot);
    onShot(shot);
    if (!after) return attempts;
    if (after.misses > before.misses) leadIndex++;
    if (after.hits >= 3) {
      await waitClosed();
      return attempts;
    }
  }
  throw new Error('practice did not reach three real hits: ' + JSON.stringify(attempts));
}

module.exports = { drivePractice };
