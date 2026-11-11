'use strict';

/* Seed IDBFS only while no game page is running. A live Godot page may flush
 * its old in-memory save during reload and overwrite the seed. A bounded retry
 * accepts a boot only after the engine writes back the expected story state. */
function makeSeededBoot({ url, seedUrl, wire, rewriteSave, wicState, readSave, note }) {
  return async function bootSeeded(context, save, { tag, label, isLoaded, maxAttempts = 3 }) {
    if (!Number.isInteger(maxAttempts) || maxAttempts < 1) throw new Error('maxAttempts must be positive');
    if (!Number.isSafeInteger(save.version) || save.version < 1) throw new Error('seed must have a numeric save version');

    // GameState.load_game() accepts a numeric string, then writes SAVE_VERSION
    // as a number. Until that happens, merely reading the injected bytes cannot
    // masquerade as an engine-written save. This changes no story state.
    const seed = { ...save, version: String(save.version) };
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
        seedInfo = await rewriteSave(writer, seed);
      } finally {
        await writer.close();
      }

      const page = await context.newPage();
      wire(page, tag);
      let state, loaded, writtenBack = false, accepted = false;
      try {
        await page.goto(url, { waitUntil: 'load', timeout: 120000 });
        await page.waitForFunction(() => window.__wic && window.__wic.draws > 40, null, { timeout: 120000 });
        await page.waitForTimeout(1600);
        state = await wicState(page);
        if (!state.canvas) throw new Error(label + ': no canvas after seeded boot');
        // Autosave and IDBFS flushing are asynchronous. Poll a bounded window;
        // never click the HUD while an opening dialogue may own mouse input.
        for (let poll = 0; poll < 12; poll++) {
          loaded = await readSave(page);
          writtenBack = !!loaded && loaded.version === save.version;
          accepted = writtenBack && !!isLoaded(loaded);
          if (accepted) break;
          if (poll < 11) await page.waitForTimeout(500);
        }
      } catch (error) {
        await page.close();
        throw error;
      }
      const status = accepted ? 'loaded' : (attempt === maxAttempts ? 'failed' : 'retry');
      const progressText = JSON.stringify(loaded && loaded.progress) || 'null';
      note(label + ' boot attempt ' + attempt + ': ' + status + ' writtenBack=' + writtenBack
        + ' version=' + JSON.stringify(loaded && loaded.version) + ' progress=' + progressText.slice(0, 180));
      if (accepted || attempt === maxAttempts) return { page, state, loaded, seedInfo, accepted, attempts: attempt };
      await page.close();
    }
    throw new Error('unreachable seeded boot');
  };
}

function nearTile(pos, x, y) {
  return Array.isArray(pos) && Number.isFinite(pos[0]) && Number.isFinite(pos[1])
    && Math.abs(pos[0] - x) <= 1 && Math.abs(pos[1] - y) <= 1;
}

function isFightSave(save) {
  const flags = save && save.flags;
  const progress = save && save.progress;
  return !!flags && flags.beth_anointed === true && flags.goliath_down === false
    && flags.elah_ended === false && !!progress && progress.act === 'ready'
    && nearTile(progress.pos, 16, 14);
}

function isPostVictorySave(save) {
  const flags = save && save.flags;
  const progress = save && save.progress;
  return !!flags && flags.goliath_down === true && flags.elah_ended === false
    && flags['talked:elah:corin'] !== true && !!progress && progress.act === 'aftermath'
    && nearTile(progress.pos, 17, 44);
}

module.exports = { makeSeededBoot, isFightSave, isPostVictorySave };
