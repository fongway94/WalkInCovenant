# Replay and chapter art — continuation

## Scope, approval and deployment

The user approved the **painterly shepherd-field prototype** as the visual benchmark (`docs/art-reset/user_selected_reference.png`). That is not approval of the later chapter-wide art or the full game. The current task is a safe replay and a closer painterly treatment for the rest of the available David/Goliath chapter; only Elah/David is playable, not a finished multi-campaign game. The user rejected repeated ground and old-style object fallbacks in the wider world.

The user gave **one-time approval** to publish the then-current build for a phone playtest. https://fongway94.github.io/WalkInCovenant/ still serves game commit `b134e10`, deployed by [run 43034457177](https://github.com/fongway94/WalkInCovenant/actions/runs/43034457177), deployment `7712095017`. No merge happened. Future deployments need separate approval. Ordinary pushes to the active working branch build but do not deploy; `main` retains its automatic-release policy. A manual dispatch and Pages policy change previously returned 403 until the user adjusted the Pages environment/source.

The current working branch is `arena/905f79d4-walkincovenant`, based on `cec25b525d44dff3b96970415fa2232a13e9d676`. [Run 43026072545](https://github.com/fongway94/WalkInCovenant/actions/runs/43026072545) passed for `b134e10`, **not** the later replay/art changes. After pushing new work, inspect the run for that exact commit before claiming CI passed or considering publication.

## Current implementation

- The book offers a confirmed replay in `user://replay.json`, separate from the existing `user://save.json`; `user://journey_slot.json` selects the last active slot. Switching captures the live world and saves both independently. A completed save opens into free roam rather than replaying its aftermath. The book and objective are bilingual.
- Saves and selectors are written through verified temporary files with independent backups. An unreadable destination is not overwritten. An unreadable selected replay falls back to the original; an unreadable original with no usable backup is protected from autosaves and opens a bilingual unsaved-progress warning. These are **local**, not cloud, saves; clearing browser data can delete them.
- New replays inherit the original settings. Thereafter, each journey may have different settings; `AudioDirector` re-applies the destination settings on `game_loaded` so both persistent audio buses agree with the HUD. Focus mute still takes precedence.
- Elah and Bethlehem have map-aligned painted ground and painted resources for every actual map prop; sheep, tent, camp fire, altar, fold, trough, staff, wheat, bush, wool and signpost have been added or revised. Props remain separate nodes with original tile footprints. The enlarged actors/props sort at their feet; an independent world shadow treatment leaves the approved field unchanged. The classic theme is reversible.
- To avoid the conspicuous repeated flower bed in earlier versions, `tools/art/build_world_ground.py` joins two distinct large meadow sections per region. The generated paving source itself repeats, so the builder mixes smaller overlapping crops; individual tents and other repeated props still share sprites. Human review is still required, especially for texture scale and consistency around the Bethlehem well. `docs/art-reset/WORLD_REVIEW.md` links staged, phone-shaped rendered views.
- The field retains its own camera, collision, independent hired boy, flock, context actions and save flags. David and several supporting actors use generated directional images with a procedural cutout gait, not authored walk cycles. Some actors share tinted rigs and the fig currently reuses the olive tree.
- `Web` and `Android` exclude `tests/*` and `build/*`. `Web Test Only` is solely a disposable browser-test pack. `tools/build_browser_probes.py` builds its copy separately and validates the logical PCK index. **Never publish the probe pack.** The Android resource PCK is not an APK or device run.

## Latest local verification (v7 working tree)

- Chromium/SwiftShader started from a fresh save and used real keyboard input through the witness, Bethlehem, anointing, shepherd field, one-sheep save/reload, flock, practice, provisions, brothers, Saul's armour, brook, duel and ending: **33 checks passed**, no page/console errors. A field exit interrupting a live sheep return was a **separate staged** check, not normal story timing.
- The replay/recovery browser suite passed **34 checks** using a deliberately seeded completed original and emulated touch. It covered cancel/confirmation, original/replay progress and reloads, independent sound settings and real audio-bus mute state, bilingual book text, and a deliberately unreadable original. Only that exact expected warning was allowed; no unexpected errors occurred. The isolated destructive slot suite passed **38 checks**, including backups and write/rename failure paths.
- The browser layout suite passed **35 checks**, including field resizing, emulated stick/A input, HUD controls during dialogue, bilingual objectives and brook feedback. The strict production Web export passed **30/30** browser checks with no console, page or request errors. Its duel/ending use separately seeded saves; the fresh journey above is the end-to-end run. Emulated touch and WebAudio telemetry are not a physical-device or listening test.
- Native software OpenGL/Xvfb rendered **18 frames**, with the real transition sampled at alpha 0.45 and allowed to finish. Existing coarse baselines were **not** replaced and are not art approval. Headless context **35/35**, shepherd stage **51/51**, shepherd resume **24/24**, painted world **68/68**, audio contract **21/21**, smoke and deep **144** passed, as did content validation.
- Lint, xref, engine API, export, font, audio-file, art-layout, pack unittest **8/8** and seeded-boot unittest **8/8** passed. The rebuilt font maps all **850** required codepoints. Web and Android-preset release PCKs each had **602** indexed resources without tests/build entries; the disposable browser pack had **700**. Sixteen generated ground/prop outputs were regenerated into a scratch directory and matched byte-for-byte.
- The previous attempt [run 43034724118](https://github.com/fongway94/WalkInCovenant/actions/runs/43034724118) had no Python in its Godot image, so static checks were skipped and a later pack test exited 127. The updated workflow sets up Python and fails closed, but that change must itself be checked in CI.
- Audio remains unreviewed by ear. The contract checks bus/player state and releases nine retired playbacks while running, not audible quality. Immediate engine shutdown still sometimes reports WAV/playback/ObjectDB resources; a delayed shutdown avoids one reproduction, but does not prove all leaks absent. The native visual run also reports shutdown resources. No Android APK or new physical-device test has been performed.

## Files and reproducibility

- `scripts/autoload/GameState.gd`, `scripts/ui/Journal.gd`, `scripts/main/Main.gd`, `data/ui.json`: slot safety, switching and bilingual recovery UI. `tests/journey_slots.*` intentionally destroys save fixtures; **always use a separate `XDG_DATA_HOME`**.
- `tools/art/sources/` holds the source paintings; `.gdignore` excludes them from Godot imports. `tools/art/build_world_ground.py` and `tools/art/build_reference_props.py` require Pillow. `art/scenes_painted/` and `art/props_painted/` are the generated game assets.
- `tests/browser/journey_slots*`, `shepherd_journey.cjs`, `chapter_layout.cjs` and `validate.cjs` exercise different test/release packs. Seven staged map screenshots and replay screenshots are retained in `docs/art-reset/world-review/`; temporary logs/exports under `build/` are snapshot-excluded.

## Useful commands

```sh
# With Godot 4.7.2 and Web export templates installed:
export PATH="$PWD/build/godot-local:$PATH"  # local provision, if present
mkdir -p build/web && touch build/.gdignore
python3 tools/gd_lint.py && python3 tools/xref_check.py && python3 tools/api_check.py
python3 tools/check_export.py && python3 tools/check_font.py
python3 -m unittest discover -s tests -p 'test_pack_contents.py' -v
node --test tests/browser/seeded_boot.test.cjs
godot --headless --path . --import
godot --headless --path . --script tests/run_all.gd
for t in context shepherd_stage shepherd_resume painted_world audio_contract journey_slots smoke deep; do
  XDG_DATA_HOME="$PWD/build/test-data/$t" godot --headless --path . "res://tests/$t.tscn"
done
# Requires Xvfb and Mesa software OpenGL; saves review frames in build/frames/.
LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe \
  xvfb-run -a -s '-screen 0 1280x720x24' godot --path . \
  --rendering-driver opengl3 --audio-driver Dummy res://tests/visual.tscn
godot --headless --path . --export-release Web build/web/index.html
python3 tools/inject_pwa.py build/web
python3 tools/check_pack_contents.py release build/web/index.pck
# Pack boundary only: this does NOT create or test an Android APK.
mkdir -p build/android-pack-check
godot --headless --path . --export-pack Android build/android-pack-check/index.pck
python3 tools/check_pack_contents.py release build/android-pack-check/index.pck
python3 tools/build_browser_probes.py --godot godot
python3 -m http.server 8083 --bind 127.0.0.1 --directory build/web-probes
# In a second shell, with Playwright installed:
WIC_FRESH_JOURNEY=1 WIC_FULL_JOURNEY=1 WIC_PROBE_URL=http://127.0.0.1:8083/ \
  node tests/browser/shepherd_journey.cjs
WIC_PROBE_URL=http://127.0.0.1:8083/ node tests/browser/chapter_layout.cjs
WIC_PROBE_URL=http://127.0.0.1:8083/ node tests/browser/journey_slots.cjs
```

Local sandbox Chromium may need `WIC_PLAYWRIGHT=playwright-core`, `WIC_SPARTICUZ=1`, `NODE_PATH="$PWD/build/preview_deps/node_modules"` and the bundled library path. CI installs regular Playwright and builds test packs separately. A local HTTP server is not a public deployment.
