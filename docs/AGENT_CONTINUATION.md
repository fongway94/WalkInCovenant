# Replay and chapter art — continuation

## Scope, approval and deployment

The user approved the **painterly shepherd-field prototype** as the visual benchmark (`docs/art-reset/user_selected_reference.png`). That is not approval of the later chapter-wide art or the full game. The current task is a safe replay and a closer painterly treatment for the rest of the available David/Goliath chapter; only Elah/David is playable, not a finished multi-campaign game. The user rejected repeated ground and old-style object fallbacks in the wider world.

The user separately approved publishing the replay and proposed wider-world art for a phone playtest; this is **not** art approval or approval for future deployments. https://fongway94.github.io/WalkInCovenant/ now serves the tested release artifact from commit `260d47c9ce5a4087529dcb4cde1b0ac21f99bc92` ([full CI run 43134363922](https://github.com/fongway94/WalkInCovenant/actions/runs/43134363922)). The approved one-time [publication run 43155162173](https://github.com/fongway94/WalkInCovenant/actions/runs/43155162173) used that exact passing artifact, checked the live PCK byte-for-byte, verified the service-worker stamp, and play-checked the public URL in Chromium. Pages deployment `7728461013` succeeded; the previous `b134e10` deployment `7712095017` was replaced. No merge occurred. A manual dispatch returned 403, so the one-shot push-triggered publication workflow was removed after use. Ordinary pushes to the active working branch build but do not deploy; `main` retains its automatic-release policy. Future deployments require separate user approval.

The current working branch is `arena/905f79d4-walkincovenant`, based on `cec25b525d44dff3b96970415fa2232a13e9d676`. After future code changes, inspect CI for their exact commit before claiming it passed or considering publication. The public browser check is automated and is not a physical-device or listening test.

## Unpublished quality pass after phone feedback

The user reports the published game is less HD/detailed than the original sunset-field image. The working branch now restores registered pixels from the user's full 740×413 attachment over most of the integrated shepherd-field backdrop, while preserving the previous inpaint around the two people/five sheep and the repainted right edge. Its tree, fence and foreground depth masks are rebuilt from the resulting backdrop. The original approved isolated prototype is unchanged. No new high-resolution master was obtained; the attachment and reproducible Pillow builder are `tools/proto/sources/user_sunset_field.png` and `tools/proto/build_reference_field.py`. Approximate collision/masks and feathered seams still require human review.

All 20 existing painted prop textures were rebuilt at three times their former canvas density directly from their existing source images. `ArtDirection.PAINTED_PROP_DETAIL_FACTOR` compensates the visual scale in `Region` and `FlockSheep`; prior world sizes, feet and collision remain unchanged. `tests/fixtures/painted_prop_geometry.json` records the earlier sizes/bounds, and `tests/proto/check_quality_assets.py` verifies regeneration, actor exclusions and mask alignment. The two map ground images were NOT changed: increasing their texture density alone showed only a modest difference, and a new three-band candidate was not adopted. Source-limited cutout sheep and other actors cannot gain unavailable detail.

[Quality review and staged before/after captures](art-reset/QUALITY_REVIEW.md) contains the limits and browser/native evidence. Current local tests: browser fresh full journey **33**, replay/recovery **34**, layout/bilingual/emulated touch **36** (DPR-2 canvas 1688×780 at 844×390 CSS), strict release **30/30**; no unexpected browser errors/warnings. Headless stage **54**, resume **24**, painted **70**, slots **38**, context **35**, audio **21**, deep **144**, smoke/content passed. Native software-rendered **18 frames** and the isolated prototype passed; no old baselines replaced. Web and Android-preset release boundaries had **610** indexed resources, disposable browser pack **709**. Ground regenerated unchanged pixel-for-pixel. The PCK is not an Android APK and none of these is a physical-phone, listening or human art-approval test. Existing immediate-shutdown ObjectDB/resource warnings remain. No new public deployment has been authorized.

## Current implementation

- The book offers a confirmed replay in `user://replay.json`, separate from the existing `user://save.json`; `user://journey_slot.json` selects the last active slot. Switching captures the live world and saves both independently. A completed save opens into free roam rather than replaying its aftermath. The book and objective are bilingual.
- Saves and selectors are written through verified temporary files with independent backups. An unreadable destination is not overwritten. An unreadable selected replay falls back to the original; an unreadable original with no usable backup is protected from autosaves and opens a bilingual unsaved-progress warning. These are **local**, not cloud, saves; clearing browser data can delete them.
- New replays inherit the original settings. Thereafter, each journey may have different settings; `AudioDirector` re-applies the destination settings on `game_loaded` so both persistent audio buses agree with the HUD. Focus mute still takes precedence.
- Elah and Bethlehem have map-aligned painted ground and painted resources for every actual map prop; sheep, tent, camp fire, altar, fold, trough, staff, wheat, bush, wool and signpost have been added or revised. Props remain separate nodes with original tile footprints. Actors/props sort at their feet; the field uses its own shadow treatment and separately restored reference backdrop. The classic theme is reversible.
- To avoid the conspicuous repeated flower bed in earlier versions, `tools/art/build_world_ground.py` joins two distinct large meadow sections per region. The generated paving source itself repeats, so the builder mixes smaller overlapping crops; individual tents and other repeated props still share sprites. Human review is still required, especially for texture scale and consistency around the Bethlehem well. `docs/art-reset/WORLD_REVIEW.md` links staged, phone-shaped rendered views.
- The field retains its own camera, collision, independent hired boy, flock, context actions and save flags. David and several supporting actors use generated directional images with a procedural cutout gait, not authored walk cycles. Some actors share tinted rigs and the fig currently reuses the olive tree.
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
- `tools/art/sources/` holds the source paintings; `.gdignore` excludes them from Godot imports. `tools/art/build_world_ground.py`, `tools/art/build_reference_props.py`, `tools/art/build_painted_props.py` and `tools/proto/build_reference_field.py` require Pillow 13.0.0 for checked reproducibility. `art/scenes_painted/` and `art/props_painted/` are the generated game assets; `python3 tests/proto/check_quality_assets.py` rebuilds them in memory or a temporary directory without touching production.
- `tests/browser/journey_slots*`, `shepherd_journey.cjs`, `chapter_layout.cjs` and `validate.cjs` exercise different test/release packs. Seven staged map screenshots and replay screenshots are retained in `docs/art-reset/world-review/`; temporary logs/exports under `build/` are snapshot-excluded.

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
