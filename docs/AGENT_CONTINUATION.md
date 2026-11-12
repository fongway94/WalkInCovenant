# Replay and chapter art — continuation

## Scope, approval and deployment

The user chose the **painterly shepherd-field prototype** as the benchmark (`docs/art-reset/user_selected_reference.png`) and clarified that the **whole playable chapter**, including character size, proportions and detail, should approach the supplied sunset-field image. They rejected repeated meadow clusters and requested inspection of the rendered game. Only the David/Goliath chapter is playable; it is not a finished multi-campaign game.

The user explicitly authorized **one public phone-playtest publication of this fixed chapter-wide pass**. This is not human art approval or blanket permission for future deployments. The publication target is https://fongway94.github.io/WalkInCovenant/ . The earlier public artifact was `260d47c9ce5a4087529dcb4cde1b0ac21f99bc92` ([CI 43134363922](https://github.com/fongway94/WalkInCovenant/actions/runs/43134363922), [publication 43155162173](https://github.com/fongway94/WalkInCovenant/actions/runs/43155162173)); do not assume that remains the latest deployment. A manual dispatch previously returned 403, so an approved one-shot push workflow downloaded and verified the **exact passing CI artifact** before deploying, then was removed. Ordinary pushes to the active working branch build but do not deploy; `main` retains its automatic-release policy. Do not merge or publish a later build without permission.

The active branch is `arena/905f79d4-walkincovenant`, based on `cec25b525d44dff3b96970415fa2232a13e9d676`. Inspect CI and Pages for the **exact** revision before making claims about a later build. Automated public-browser checks do not establish physical-device appearance, audible quality or art approval.

## Current chapter-wide reference pass

The 1024×576 attachment (`tools/art/sources/user_reference_1024.webp`) registers to the same painting as the earlier 740×413 attachment; it is not proven to be a higher-resolution master. `tools/proto/build_reference_field.py` restores its pixels over 87.1% of the field at >94% opacity, retains old inpaint around two people/five sheep and the repainted right edge, and rebuilds aligned tree, fence and foreground layers. The original isolated prototype remains unchanged. Feathered seams and approximate collision/depth still need human review.

`build_reference_world.py` blends one generated meadow per region into new map-aligned `world_*_reference.png` textures, protecting water/crossings and retaining the old terrain where masked. The map JSON remains authoritative. Six camp tents select four cosmetic silhouettes, including the open royal tent; Bethlehem has a second house; broadened structure shadows ground their isometric bases. Practice jars and selectable brook stones use painted sprites with the same timing, positions and hit areas. The 20 prior painted props retain their 3× canvases and old world footprints.

`build_reference_characters.py` produces **27 views / 108 layers** for the witness, Corin, elder, woman, boy, seated Samuel, Jesse, Eliab and Saul. Left mirrors right. Samuel's stool and figure remain one stationary, bottom-anchored layer. Jesse, Eliab and Saul no longer borrow tinted elder/Corin rigs; the generic soldier remains a fallback. Eliab is also spawned as a non-interactable story-only figure at the brothers' post, with an idempotent spawn on errand resume, and uses his own dialogue portrait. Cutout feet are procedural, not authored walk cycles. Generated angles and continuity still need human review.

The previous tent hid Saul's lower body. `Region.gd` now selects an open-front tent at the same authored footprint and sorts its back wall behind him while retaining its visual base and shadow. The render probe exercises both sides, the real king spawn, and a negative control with the old occluding tent. In the real browser journey the nearby woman's natural chatter was also found covering Saul; bubble placement now avoids all visible people and suppresses optional chatter if no safe place exists. The fixture verifies this, and the previous bubble placement fails its negative control. The real browser journey approaches and talks to Saul, and checks the woman's natural chatter. Players can still walk directly over actors because people do not have rigid collision.

[Quality review and framebuffer captures](art-reset/QUALITY_REVIEW.md) records actual staged and browser views. Local checks: full fresh browser journey to the ending, replay/recovery **34**, layout/bilingual/emulated touch **36** (DPR-2 1688×780 backing at 844×390 CSS), strict release **30/30**; no unexpected browser errors/warnings. Headless stage **54**, resume **24**, painted **116**, slots **38**, context **35**, audio **21**, deep **144**, smoke/content passed. Native software OpenGL rendered **18 frames**, and the isolated prototype passed at **1280×720**. Its earlier exploratory 1000×450 run failed viewport-specific assertions and is not a valid pass. No baselines were replaced. Local Web and Android-preset release PCKs each had **844** indexed resources, the separate disposable probe pack **947**. A PCK is not an Android APK; no physical-phone, listening or human art approval is implied. Immediate-shutdown ObjectDB/resource warnings remain.

During this session port 8103 serves the local release export under `build/final-check/web/`; its `/__probe__/` path is a disposable test pack, **never a release**. `build/` and local servers are ephemeral, and the preview is not the public phone link.

## Current implementation

- The book offers a confirmed replay in `user://replay.json`, separate from the existing `user://save.json`; `user://journey_slot.json` selects the last active slot. Switching captures the live world and saves both independently. A completed save opens into free roam rather than replaying its aftermath. The book and objective are bilingual.
- Saves and selectors are written through verified temporary files with independent backups. An unreadable destination is not overwritten. An unreadable selected replay falls back to the original; an unreadable original with no usable backup is protected from autosaves and opens a bilingual unsaved-progress warning. These are **local**, not cloud, saves; clearing browser data can delete them.
- New replays inherit the original settings. Thereafter, each journey may have different settings; `AudioDirector` re-applies the destination settings on `game_loaded` so both persistent audio buses agree with the HUD. Focus mute still takes precedence.
- Elah and Bethlehem have map-aligned painted ground and painted resources for every actual map prop; sheep, tent, camp fire, altar, fold, trough, staff, wheat, bush, wool and signpost have been added or revised. Props remain separate nodes with original tile footprints. Actors and most props sort at their feet; the open royal tent sorts at its back wall. The field uses its own shadow treatment and separately restored reference backdrop. The classic theme is reversible.
- The older `tools/art/build_world_ground.py` ground remains the base; `build_reference_world.py` places a single new meadow per region on top, with tile masks and water protection. Its source paving still repeats; tents now have four silhouettes, but other instances can still repeat. Human review remains necessary, especially around Bethlehem and at different camera positions.
- The field retains its own camera, collision, independent hired boy, flock, context actions and save flags. David and supporting actors use a procedural cutout gait, not authored walk cycles. The generic soldier still shares a tinted rig, generated turns require human review, and the fig currently reuses the olive tree.
- `Web` and `Android` exclude `tests/*` and `build/*`. `Web Test Only` is solely a disposable browser-test pack. `tools/build_browser_probes.py` builds its copy separately and validates the logical PCK index. **Never publish the probe pack.** The Android resource PCK is not an APK or device run.

## Earlier local verification (published v7 build)

- Chromium/SwiftShader started from a fresh save and used real keyboard input through the witness, Bethlehem, anointing, shepherd field, one-sheep save/reload, flock, practice, provisions, brothers, Saul's armour, brook, duel and ending: **33 checks passed**, no page/console errors. A field exit interrupting a live sheep return was a **separate staged** check, not normal story timing.
- The replay/recovery browser suite passed **34 checks** using a deliberately seeded completed original and emulated touch. It covered cancel/confirmation, original/replay progress and reloads, independent sound settings and real audio-bus mute state, bilingual book text, and a deliberately unreadable original. Only that exact expected warning was allowed; no unexpected errors occurred. The isolated destructive slot suite passed **38 checks**, including backups and write/rename failure paths.
- The browser layout suite passed **35 checks**, including field resizing, emulated stick/A input, HUD controls during dialogue, bilingual objectives and brook feedback. The strict production Web export passed **30/30** browser checks with no console, page or request errors. Its duel/ending use separately seeded saves; the fresh journey above is the end-to-end run. Emulated touch and WebAudio telemetry are not a physical-device or listening test.
- Native software OpenGL/Xvfb rendered **18 frames**, with the real transition sampled at alpha 0.45 and allowed to finish. Existing coarse baselines were **not** replaced and are not art approval. Headless context **35/35**, shepherd stage **51/51**, shepherd resume **24/24**, painted world **68/68**, audio contract **21/21**, smoke and deep **144** passed, as did content validation.
- Lint, xref, engine API, export, font, audio-file, art-layout, pack unittest **8/8** and seeded-boot unittest **8/8** passed. The rebuilt font maps all **850** required codepoints. Web and Android-preset release PCKs each had **602** indexed resources without tests/build entries; the disposable browser pack had **700**. Sixteen generated ground/prop outputs were regenerated into a scratch directory and matched byte-for-byte.
- [Run 43034724118](https://github.com/fongway94/WalkInCovenant/actions/runs/43034724118) had no Python in its Godot image, so static checks were skipped and a later pack test exited 127. Python setup succeeded in [run 43131983489](https://github.com/fongway94/WalkInCovenant/actions/runs/43131983489), but its static checks then found 27 false missing-class errors because the pinned offline Godot reference lacked some classes and the runner could not fetch them. The missing Godot 4.7 class documents and ancestor chain are now pinned; cold-cache/no-network regressions still catch deliberately invalid members and classes.
- [Run 43132741234](https://github.com/fongway94/WalkInCovenant/actions/runs/43132741234) passed for `1acc56a`, including static, save, painted-world, audio and browser journey tests; deployment was skipped. Its passing static output was nevertheless emitted as a red error annotation. The reporting step now emits a notice on success and prefixes all check statuses before any truncated details; its cases passed locally and [run 43134363922](https://github.com/fongway94/WalkInCovenant/actions/runs/43134363922) passed for `260d47c` with a notice rather than a false error.
- Audio remains unreviewed by ear. The contract checks bus/player state and releases nine retired playbacks while running, not audible quality. Immediate engine shutdown still sometimes reports WAV/playback/ObjectDB resources; a delayed shutdown avoids one reproduction, but does not prove all leaks absent. The native visual run also reports shutdown resources. No Android APK or new physical-device test has been performed.

## Files and reproducibility

- `scripts/autoload/GameState.gd`, `scripts/ui/Journal.gd`, `scripts/main/Main.gd`, `data/ui.json`: slot safety, switching and bilingual recovery UI. `tests/journey_slots.*` intentionally destroys save fixtures; **always use a separate `XDG_DATA_HOME`**.
- `tools/art/sources/` holds source paintings; `.gdignore` excludes them from Godot imports. The field, `build_reference_world.py`, `build_reference_characters.py`, `build_reference_variants.py` and existing prop builders require Pillow 13.0.0 for checked reproducibility. `python3 tests/proto/check_quality_assets.py` rebuilds assets in memory or a temporary directory without touching production. The 108 runtime character layers live in `art/characters_reference/`.
- `tests/reference_visual_probe.tscn` stages the real Region, actors and full-screen setpieces and saves actual framebuffers under `build/reference-pass-captures/`; it is not a playthrough. Current review images are retained in `docs/art-reset/chapter-reference-review/`; earlier captures remain in `docs/art-reset/world-review/` and `quality-review/`. `tests/browser/journey_slots*`, `shepherd_journey.cjs`, `chapter_layout.cjs` and `validate.cjs` exercise different test/release packs. Temporary logs/exports under `build/` are snapshot-excluded.

## Useful commands

```sh
# With Godot 4.7.2 and Web export templates installed:
export PATH="$PWD/build/godot-local:$PATH"  # local provision, if present
mkdir -p build/web && touch build/.gdignore
python3 tools/gd_lint.py && python3 tools/xref_check.py && python3 tools/api_check.py
python3 tools/check_export.py && python3 tools/check_font.py
python3 -m unittest discover -s tests -p 'test_pack_contents.py' -v
python3 -m unittest discover -s tests -p 'test_api_reference.py' -v
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
