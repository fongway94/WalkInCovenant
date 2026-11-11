'use strict';

/* Seed IDBFS only while no game page is running. A live Godot page may flush
 * its old in-memory save during reload and overwrite the seed. Keep the real
 * engine/save assertions: a bounded retry only succeeds when readSave confirms
 * that the newly opened game actually loaded the expected state. */
function makeSeededBoot({ url, seedUrl, wire, rewriteSave, wicState, readSave, note }) {
  return async function bootSeeded(context, save, { tag, label, isLoaded, maxAttempts = 3 }) {
    if (!Number.isInteger(maxAttempts) || maxAttempts < 1) throw new Error('maxAttempts must be positive');
    if (!save.settings || save.settings.sound !== true) throw new Error('seed must start with sound enabled');
    for (let attempt = 1; attempt <= maxAttempts; attempt++) {
      const boot = await context.newPage();
      wire(boot, tag + '_boot');
      try {
        await boot.goto(url, { waitUntil: 'load', timeout: 120000 });
        await boot.waitForFunction(() => window.__wic && window.__wic.draws > 40, null, { timeout: 120000 });
        await boot.waitForTimeout(1600);
      } finally {
        await boot.close();
      }

      // The manifest is same-origin but never starts the game or its IDBFS.
      const writer = await context.newPage();
      let seedInfo;
      try {
        await writer.goto(seedUrl, { waitUntil: 'load', timeout: 120000 });
        seedInfo = await rewriteSave(writer, save);
      } finally {
        await writer.close();
      }

      const page = await context.newPage();
      wire(page, tag);
      let state, loaded;
      try {
        await page.goto(url, { waitUntil: 'load', timeout: 120000 });
        await page.waitForFunction(() => window.__wic && window.__wic.draws > 40, null, { timeout: 120000 });
        await page.waitForTimeout(1600);
        state = await wicState(page);
        if (!state.canvas) throw new Error(label + ': no canvas after seeded boot');
        const sx = state.canvas.cssW / 320, sy = state.canvas.cssH / 180;
        // A real settings click makes the engine write its loaded state back.
        await page.mouse.click(state.canvas.x + 305 * sx, state.canvas.y + 10 * sy);
        await page.waitForTimeout(1200);
        loaded = await readSave(page);
      } catch (error) {
        await page.close();
        throw error;
      }
      // The injected seed starts with sound on. Requiring the saved toggle
      // proves the running engine wrote it back, rather than merely rereading
      // the injected bytes before the engine's own IDBFS flush completed.
      const writtenBack = !!loaded && !!loaded.settings && loaded.settings.sound === false;
      const accepted = writtenBack && !!isLoaded(loaded);
      const status = accepted ? 'loaded' : (attempt === maxAttempts ? 'failed' : 'retry');
      const progressText = JSON.stringify(loaded && loaded.progress) || 'null';
      note(label + ' boot attempt ' + attempt + ': ' + status + ' writtenBack=' + writtenBack
        + ' progress=' + progressText.slice(0, 180));
      if (accepted || attempt === maxAttempts) return { page, state, loaded, seedInfo, accepted, attempts: attempt };
      await page.close();
    }
    throw new Error('unreachable seeded boot');
  };
}

function isPostVictorySave(save) {
  const progress = save && save.progress;
  const pos = progress && progress.pos;
  return !!save && !!save.flags && save.flags.goliath_down === true
    && !!progress && progress.act === 'aftermath' && Array.isArray(pos)
    && Number.isFinite(pos[0]) && Number.isFinite(pos[1])
    && Math.abs(pos[0] - 17) <= 1 && Math.abs(pos[1] - 44) <= 1;
}

module.exports = { makeSeededBoot, isPostVictorySave };
