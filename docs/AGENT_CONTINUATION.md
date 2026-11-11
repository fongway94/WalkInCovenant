# Chapter art and gameplay — continuation

## Approval and deployment

The user played and approved the **painterly shepherd-field prototype's art direction**. That approval does not cover the subsequently generated chapter art or the current full build. **Do not deploy this build or dispatch `publish_preview` without separate approval.** Ordinary pushes to the active working branch build but do not deploy; `main` retains its automatic-release policy. No merge is implied.

The reference is `docs/art-reset/user_selected_reference.png`; the older prototype comparison and evidence remain in `docs/art-reset/`. Its viewer border and arrow are not game art. The current work lives on `arena/905f79d4-walkincovenant`, branched from `cec25b525d44dff3b96970415fa2232a13e9d676`.

## Current implementation

- The approved field is integrated into the real shepherd act, with its own camera framing, collision, independent hired boy, flock, context actions and save flags. Leaving it removes field-only animals and their shadow registrations, including a returning animal.
- Cinematic/painterly is the shared default on Web, desktop and Android. Elah and Bethlehem use map-aligned ground and separate painted props; the player, supporting cast, armour, practice, brook and duel have painted treatments. Classic remains reversible. The later art has **not** been approved by the user; it still needs visual and device review.
- David and several other actors have generated directional images with a procedural cutout gait, not authored walk cycles. Some supporting characters share tinted rigs, the fig currently reuses the olive tree, and the field's depth contours remain approximations.
- NPC reaction panels measure the text, stay in the viewport's safe band and try to avoid both the speaker and the player. Long ambient lines advance automatically through bounded single-line pages, preserving words that were previously clipped. The camera fits the field at different aspect ratios. In the brook, measured local backings keep feedback and instructions legible without darkening the whole picture or covering the stones. These checks do not prove every object and bubble placement is visually ideal.
- The final sheep updates the objective to **3/3** and clears its arrow before opening the home dialogue, including after a completed-flock reload. Mouse clicks and emulated touches on visible HUD switches no longer advance the dialogue underneath; the unavailable book remains a no-op. Objectives retain bilingual sources while dialogue freezes story guidance: this covers shepherd counts, witness names, provision counts and Bethlehem's chapter guidance without restarting escorts or advancing missions. A chapter's guidance is a read-only description; it primes the HUD on region arrival/resume so a synchronous opening box cannot carry over the old region's task.
- Music crossfades swap the existing players' roles rather than restarting the outgoing track; cuts clear the spare player. Focus mute survives settings changes, and a muted or missing dialogue blip cannot repitch an unrelated pooled effect. This is verified through player/bus state, not by listening.
- `Web` and `Android` exclude `tests/*` and `build/*`. `Web Test Only` is used solely to make a disposable browser-test PCK. `tools/check_pack_contents.py` validates the logical PCK index; `tools/build_browser_probes.py` copies the release shell into `build/web-probes/`, exports and validates a fresh PCK before replacing the copy, and makes launchers there. **Never publish `build/web-probes/`.** The Android resource PCK was checked separately; an Android APK export and device run are still untested.

## Verified locally

- A fresh Chromium/SwiftShader context, with no seeded story state, walked and conversed through four witness verses, first sight, the line, Bethlehem's elder, Samuel, David and the anointing; returned to the shepherd field; counted one sheep; **reloaded** and restored 1/3; then completed the flock, practice, provisions, brothers, Saul's armour, brook, three-hit duel and ending. The latest run passed **33 checks** with no browser page/console errors, including the separate staged cleanup checks below. It clicked the real language switch during Bethlehem's arrival and the elder's conversation, and during the flock-home dialogue; both languages appeared without advancing the dialogue or mission. It uses keyboard/mouse events and read-only test telemetry: an automated journey, not a physical-device or human playtest.
- A **separate staged** browser interruption calls the real field exit while a return tween is live. It verified the animal was freed, sheep shadows and field pickups were removed, and the counted flag remained. Normal narrative timing reaches the exit after that short tween; do not describe the interruption as natural progression.
- The rebuilt ordinary release Web export also passed **30/30** Chromium checks in strict mode with no page, console or request errors, including emulated touch, resize, IndexedDB reload and audio-unlock telemetry. Its duel and ending checks use separate seeded saves; neither emulated touch nor audio telemetry is a physical-device or listening review.
- The browser layout suite passed **35 checks** locally. It checked live field resizing at 1280×720, 960×540, 1024×768 and 844×390 and back to 1280×720. Emulated touch dragged the floating stick and tapped the on-screen A to count the selected sheep; other sheep can independently reach the fold by herding and are distinguished from that action. In a separately seeded opening, both mouse and emulated touch changed language and sound without skipping dialogue; tapping the unavailable book did nothing, while tapping elsewhere advanced the line. In an unseeded witness conversation, the real language button translated the frozen objective both ways without changing the dialogue. The probe also observed both pages of Corin's naturally timed English chatter, with text fitting and the bubble clear of the player and speaker. It selected five stones in a staged brook fixture and sampled rendered feedback and instruction contrast in Chinese at 1280×720 and English at 844×390. Its percentile-based pixel contrast is a regression signal, not an accessibility certification. Chinese ambient chatter and field reactions were also reviewed in rendered captures. Four viewport/zoom combinations additionally checked field coverage and field-bubble bounds. None of this replaces a physical-device test.
- The native rendered `tests/visual.gd` suite passed **18 frames** under Xvfb/Mesa llvmpipe. Its harness stages some scenes: it selects and counts a real sheep via the interaction handler, uses field cleanup before the staged duel/aftermath, then takes the road to Bethlehem. The isolated prototype's native movement, depth, collision and sheep checks also passed. The old baselines were **not** replaced. The chapter suite's coarse pixel comparator can pass a semantically wrong frame, so preserve the state assertions and inspect captures rather than treating a passing diff as art approval.
- The latest headless run passed content lint, context **35/35**, shepherd stage **51/51**, shepherd resume **24/24**, painted world **53/53**, audio contract **21/21**, smoke and deep **144 checks**. Context covers plain, named, counted and chapter objective translations, including a real region swap and a resumed Bethlehem brief. Pack boundary tests passed **8/8** and seeded-boot helpers **8/8**. Lint, xref, Godot API, export, font, audio-file and art-layout checks passed.
- A fresh tracked-file copy of the current working tree, without `.godot/`, passed import, context **35/35**, shepherd resume **24/24**, Web release/probe exports and the Android resource-pack boundary. The latest rebuilt Web release PCK had **578** indexed resources, no logical `tests/` or `build/` entries; the disposable probe pack had **668** resources and four browser launchers. The earlier test PCK also built in a clean data home without export templates. The rebuilt Android-preset resource PCK contained **578** resources and no `tests/` or `build/` entries, but it is not an APK or device test. CI checks the Android boundary and waits for the rendered and browser jobs before deployment.
- Branch CI [run 43015049384](https://github.com/fongway94/WalkInCovenant/actions/runs/43015049384) passed for commit `16dbc54`, including lint, Web export, native visual, production browser and chapter browser; **deploy was skipped**. It predates the later sheep-HUD, dialogue-input and bilingual objective fixes, so check the latest branch run separately before claiming those fixes passed remotely. No dispatch, merge or deployment was performed.
- Audio remains unreviewed by ear. The audio contract verifies nine retired playbacks are freed while the game is still running after repeated handovers; it deliberately drains its mixer before quitting. Other headless tests still sometimes report audio playback resources at immediate shutdown: a verbose painted-world run retained the valley and hit WAV/playback pairs. A minimal reproduction retained one pair when quitting immediately after `stop()`, but not after a 0.5-second delay. This is consistent with queued mixer cleanup, not proof that every in-game leak is absent or that audible quality is acceptable. The latest native rendered run also reported two ObjectDB instances and one resource in use at exit.

Screenshots and logs under `build/` are temporary and snapshot-excluded. The shipped art, source artwork needed by the builders and scripts are in the working tree. `tools/art/sources/.gdignore` keeps the large source images out of Godot imports.

## Useful commands

```sh
# With Godot 4.7.2 and Web export templates installed:
export PATH="$PWD/build/godot-local:$PATH"  # local provision, if present
mkdir -p build/web
touch build/.gdignore  # do not import prior exports or screenshots as source
python3 tools/gd_lint.py
python3 tools/xref_check.py
python3 tools/api_check.py
python3 tools/check_export.py
python3 -m unittest discover -s tests -p 'test_pack_contents.py' -v
node --test tests/browser/seeded_boot.test.cjs
godot --headless --path . --import
godot --headless --path . --script tests/run_all.gd
for t in context shepherd_stage shepherd_resume painted_world audio_contract smoke deep; do
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
```

Local sandbox Chromium may require `WIC_PLAYWRIGHT=playwright-core`, `WIC_SPARTICUZ=1`, `NODE_PATH="$PWD/build/preview_deps/node_modules"` and `LD_LIBRARY_PATH="$PWD/build/preview_deps/al2023/lib:/tmp:${LD_LIBRARY_PATH:-}"`. CI installs regular Playwright and builds the test pack separately; it stores only screenshots and verdicts, not the pack. Review the latest CI and rendered results before claiming they passed. A local HTTP server is not a public deployment.
