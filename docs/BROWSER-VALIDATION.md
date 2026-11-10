# BROWSER VALIDATION — the exported game, opened in Chromium

> **Status:** release candidate evidence, **not** a declaration of completion.
> This file records what a real browser actually did with the Godot 4.7 Web
> export, what it proved, and what it did not.

## 0. Why this lives in CI

The authoring sandbox can execute a provisioned Chromium
(`/tmp/wic_chromium_probe/chromium`, Chromium 153 locally; Playwright's own
Chromium 158 on the runner) and can drive it with `playwright-core`, but it
cannot reach the hosts that hold the built game:

| Host | From the sandbox |
|---|---|
| `registry.npmjs.org` | ✅ 200 — Playwright installs |
| `cdn.playwright.dev` | ❌ `http=000` — default browser download blocked |
| `fongway94.github.io` | ❌ `http=000` from bash (only `fetch_page` can read it) |
| `productionresultssa*.blob.core.windows.net` | ❌ `EOF` — `gh run download --name web` fails |

So the browser test runs in the `browser` job of `.github/workflows/build-web.yml`,
where the `web` artifact from `export-web` is already on disk. Evidence comes
back through GitHub check-run annotations (`WICBROWSER|`, `WICBROWSERLOG|`,
`WICBROWSERTEXT|`), reassembled by `tools/decode_browser_frames.py <run-id>`.
GitHub keeps only 50 annotations per check run, so the job emits one small
contact sheet, seven 320 px / 16-colour key frames and a compact JSON log. **The
committed PNGs in `docs/browser-evidence/` are those lossy transport copies**;
full-resolution screenshots remain in the run's `browser-evidence` artifact.

Harness: `tests/browser/validate.cjs` (CommonJS, Playwright, no game debug
hook). Serve: `python3 -m http.server 8080 --directory build/web`. Browser:
`chromium.launch({ headless: true, --use-angle=swiftshader })`.

---

## 1. Phase 1 — real execution

Evidence run `42754753831` (`b2951a4`) and final re-verification
`42756324054` (`dae8827`, after the BUG-062 fix), Chromium **158.0.8127.18**,
from the actual `build/web` produced by `export-web`. Both runs are green; the
committed PNGs and `log.json` are from the final run.

| Check | Result |
|---|---|
| Canvas exists / WebGL2 context created / draw calls observed | ✅ 3 contexts, 96+ draws at boot |
| Resource requests, console errors, page errors | ✅ 0 failed requests, 0 console errors, 0 page errors |
| Real keyboard (Arrow/W/E/Space/Escape/Tab) reaches the page | ✅ |
| Real mouse click (audio unlock, HUD sound toggle) | ✅ |
| Real touch emulation (`hasTouch`, `isMobile`) | ✅ `touchstart` + `pointerdown` captured |
| WebAudio unlock after gesture | ✅ 1 context, state `running`, **5 `AudioBufferSourceNode.start()` calls** |
| Mute writes through to the save | ✅ `sound true → false` |
| Save file readable from IndexedDB | ✅ `/userfs` → `FILE_DATA` → `/userfs/godot/app_userdata/WalkInCovenant/save.json` |
| Save survives a full page reload | ✅ `progress` preserved |
| Seeded save resumed at the line (`act=ready`) | ✅ player `[16,10]` |
| **Goliath duel won in the browser** | ✅ `goliath_down=true` after 40 real `Space` presses |
| **Chapter ending reached in the browser** | ✅ `talked:elah:corin=true`, `elah_ended=true` after 15 presses |
| Hard failures | **0 of 30 checks** |

The duel screenshot (`goliath_02_duel.png`) shows the drawn Goliath and David,
the spear, the bilingual objective, the stone counter and the A button — the
setpiece really rendered in WebGL, not just in Godot's headless software GL.

### How the late-chapter states were reached

The harness does **not** add a cheat to the game. It boots once so Godot creates
its own Emscripten IDBFS database, rewrites `save.json` inside Godot's existing
`FILE_DATA` record (preserving its `Date` timestamp and `Int8Array` contents —
see the two red runs below), then reloads. The second boot goes through
`GameState.load_game()` and `Main._resume_story()` exactly as a player's refresh
would. A HUD sound click forces `GameState.save_game()` so the harness can prove
the **engine** loaded the state, not just that it wrote a file.

Two earlier attempts are preserved in the run history because they were real
defects in the *test*, not in the game:

- `42749614328`: seeding before boot created the IDBFS DB with the wrong shape;
  the game ignored the save.
- `42751307541`: `timestamp: Date.now()` and `Uint8Array` contents produced
  `TypeError: e2.timestamp.getTime is not a function` twice; Emscripten expects
  a `Date` and an `Int8Array`.

---

## 2. Phase 2 — layouts (browser emulation, **not** physical devices)

Live resize of the *same running game*, then a separate touch context:

| Viewport | Canvas | Draws | Rotate overlay |
|---|---|---|---|
| desktop 1280×720 | 1280×720 | 96 | off |
| wide 1920×1080 | 1920×1080 | 135 | off |
| 4:3 1024×768 | 1024×768 | 178 | off |
| mobile landscape 844×390 | 844×390 | 255 | off |
| small landscape 640×360 | 640×360 | 362 | off |
| touch landscape 844×390 @2× | 1688×780 backing, 844×390 CSS | 82 | off |
| **portrait 390×844 @2×** | 780×1688 backing, 390×844 CSS | 193 | **on** |

Canvas fills the viewport at every size; WebGL keeps drawing after each resize.
The portrait overlay shows the rotate glyph, 「请横屏游戏」 and the English
fallback line, and is driven by `@media (orientation:portrait)` plus touch
detection. No letterboxing appears (the project uses `canvas_items` / `expand`,
asserted by `run_all.gd`). HUD, objective, dialogue bubble and touch A/RUN
buttons remain on screen; no clipped panels were observed in the captured
frames.

**Verified cosmetic weakness (Low):** the A and RUN circles are drawn on
desktop keyboard play too (`TouchControls._draw_viz()` draws them whenever not
blocked). They are intentional on a phone — a player must see the button before
touching anything — but they add clutter on a desktop. Not changed: hiding them
would alter all 14 committed in-engine baselines, and no device has told us
which input mix to prefer.

**Not claimed:** real-device testing, tactile feel, thumb reach, OS rotation,
notch/safe-area behaviour, or legibility on an actual handset. Chromium device
emulation is not a phone.

---

## 3. Phase 3 — audio, technically

| Signal | Observation |
|---|---|
| `AudioContext` created after the first gesture | 1, state `running` |
| `AudioContext.resume()` calls | 0 (the context was already running under headless autoplay policy) |
| `AudioBufferSourceNode.start()` | **5** — SFX buffers really started |
| `HTMLMediaElement.play()` | 0 (the game uses WebAudio, not `<audio>`) |
| Mute | HUD toggle flips `settings.sound`/`music`, `AudioDirector.apply_settings()` runs, the change is written to `save.json` |
| BGM / ambient transitions / looping / overlap / volume balance | **not audible here** |

`tools/check_audio.py` still verifies 16 sounds / 3 tracks / 2661.7 KB and
levels. **Perceptual audio quality is unverified**: no one listened, no sound
card, no loudness or loop-seam judgement. This is a technical playback check,
not a mix review.

---

## 4. Phase 4 — connected experience

Scene-by-scene, from the 14 in-engine frames, the browser frames, and the data:

| Scene | What the player does | Evidence | Review |
|---|---|---|---|
| First five minutes / boot | Walks immediately; no forced pages. Place card, HUD objective, one NPC a tile away. | `01_boot_desktop.png`, `smoke.gd` `boot_forced_pages=0` | Control is immediate; the opening does not explain itself to death. No change. |
| Shepherding | Drives three strays back to the fold before dusk. | `06_flock.png`, `07_sheep_near.png` | One mechanic, no quiz. No change. |
| Samuel's arrival / anointing | Walks south to Bethlehem, 1 Sam 16 before 1 Sam 17. | `05_bethlehem.png`, mission `bethlehem_call` | Chronology is explicit in data. No change. |
| Saul's court | Hears the king, walks in the armour, takes it off. | mission `saul_armour`, `11_transition.png` | The armour is measured in steps, not a menu. No change. |
| Valley exploration | Talks to the camp, gathers four words, crosses the line as witness. | `02_valley.png`, `08_quest_update.png` | Objective line always names the next action. No change. |
| Brook / five stones | Chooses five smooth stones by hand. | `13_duel.png` in-engine | Counter visible. No change. |
| Goliath confrontation | Dodges the spear, times three throws. | **`goliath_02_duel.png`**, browser win | Real browser input reached the setpiece and won. No change. |
| Aftermath / conclusion | Corin hears it; the ending lines play; free roam. | `goliath_06_corin_talk.png`, `14_aftermath.png` | **One verified defect found and fixed — see BUG-062.** |

**BUG-062 (P1, found → fixed → verified).** The browser's post-ending
screenshot showed the HUD still saying 「跟着柯林走。他带你去找少年兵。」 —
the witness escort chain — *after* `elah_ended` had been written. A finished
chapter must not point at one more NPC. `Main._update_guidance()` now
short-circuits on `Act.DONE` / `elah_ended` to the `done` objective, with no
arrow and no prompt. A regression check
(`tests/deep.gd::_check_ending_objective`) was added; it fails against the old
code, `deep: PASS — 143 checks hold` in `42756324054`, and that run's
`goliath_05_ending.png` now reads 「本章完成 · 山谷安静了」. No new mechanic
was introduced.

No other pacing, exposition or control weakness was verified in the captured
frames, so no speculative changes were made.

---

## 5. Phase 5 — Simplified Chinese, editorial

What was actually done:

- `tools/check_font.py`: 826 codepoints mapped — no tofu in any screenshot.
- `tools/check_text_fit.py`: every line fits the dialogue box at 5 rows.
- `tools/run_all.gd`: all dialogue, verses, objectives and ending are bilingual.
- Scanned 204 `zh` dialogue strings for terminal punctuation, traditional
  characters, stray Latin and doubled spaces. The five lines without terminal
  punctuation are **split Scripture quotations** (e.g. 撒母耳记上 17:28,
  17:40, 17:45) and were left verbatim. Term counts: 歌利亚 1 / 歌利亞 0,
  扫罗 5 / 掃羅 0, 大卫 6 / 大衛 0, 耶和华 15 / 耶和華 0 — simplified is
  consistent.
- Read Chinese in the browser frames: HUD, objective, chatter bubble, duel
  objective, portrait overlay, Corin's ending dialogue. Glyphs are complete and
  not clipped at 320 px transport size.

**Not done / not claimed:** a native-speaker or author review. Character voice,
comedic timing, the naturalness of aphorisms such as
「他错在以为，年轻就什么都不是」, and the 石子 / 石头 register split (10 vs 5
uses — the thrown stone is called 石头 once by a soldier) need a human reader.
Scripture quotations remain marked as Scripture and are not to be "improved"
with invented dialogue punctuation.

---

## 6. Phase 6 — release candidate summary

### Automated checks (local, pre-push)

| Gate | Result |
|---|---|
| `gd_lint` | clean — 32 files, 22 class_names |
| `xref_check` | clean — 32 scripts, 4 autoloads |
| `api_check` | clean — 54 engine classes |
| `check_font` | clean — 826 codepoints |
| `check_text_fit` | clean |
| `check_export` | clean |
| `check_audio` | clean — 16 sounds, 3 tracks, 2661.7 KB |
| `check_chars` / `check_faces` | clean — 18 portraits, 2 duel figures, determinism verified |
| `pack_art` | clean — 49 tiles, 26 props |
| `visual_diff` | clean — all 14 baselines within 0.18 (max 0.0248) |

CI (`42754753831`) additionally had `lint`, `visual`, `export-web` and
`browser` green; `deploy` skipped by design. The BUG-062 fix and its new deep
check were re-verified in full CI `42756324054` (`dae8827`): `lint`, `visual`,
`export-web`, `browser` all green, `deploy` skipped; `run_all: ALL CHECKS
PASSED`, `smoke: PASS`, `deep: PASS — 143 checks hold`, browser 30/30 checks,
and the corrected post-ending HUD screenshot. The run-by-run trail is in
`docs/BUG_TRACKER.md`.

### Release conditions

| # | Condition | State |
|---|---|---|
| 1 | Real browser execution verified | ✅ Chromium 158, WebGL2, 30/30 checks |
| 2 | Critical gameplay progression works | ✅ duel won + ending reached in browser |
| 3 | Supported screen layouts usable | ✅ 5 live resizes + portrait guidance |
| 4 | No Critical/High defects remain | ✅ no Critical/High **code** defect open |
| 5 | Audio behaviour checked technically | ✅ WebAudio running, 5 buffer starts, mute persisted |
| 6 | Chinese text remains readable | ✅ font + fit + screenshots |
| 7 | Automated tests pass | ✅ static gates, 14 baselines, CI |
| 8 | Unresolved human playtesting limitations disclosed | ✅ below |

### Remaining issues, classified

| Severity | Issue |
|---|---|
| **Critical** | none open |
| **High** | **Human playtest not performed.** No person has played opening → conclusion for enjoyment, confusion or emotional closure. This is the one gate automated tests cannot pass. |
| **Medium** | Perceptual audio quality unverified (balance, loop seams, BGM/SFX overlap, ambience transitions). |
| **Medium** | Native-speaker / author Simplified Chinese review not performed (character voice, aphorisms, 石子/石头 register). |
| **Medium** | Real-device tactile, rotation and safe-area pass not performed; browser emulation only. |
| **Low** | Touch A/RUN circles drawn during desktop keyboard play; cosmetic, deliberately unchanged to protect 14 baselines. |
| **Low** | Post-duel valley walk back to Corin is not automated end-to-end; the ending was played from a seeded post-victory save adjacent to Corin. All transitions after that point are real browser input. |
| **Low** | `docs/browser-evidence/` holds 320 px / 16-colour transport thumbnails; full-resolution shots are in the CI artifact only. |
| **Low** | On 2026-11-10 the user explicitly authorised a working-branch live preview; `arena/46955931-walkincovenant` now publishes to the one Pages URL on push. It is a preview, not a release; the next `main` push republishes `main`. |

### Verdict

**Release candidate, not release.** All eight technical conditions are met,
but the project is **not** marked complete: a human being still has to play it,
listen to it, read the Chinese as a native speaker, and hold it on a real phone.
No PR has been opened and no merge to `main` has been performed for this
milestone. A working-branch **preview deploy** was later explicitly authorised
by the user; that is not a release deployment of `main`.

## 2026-11-10 — working-branch preview is live

The user authorised a live branch preview. After one Node20 deploy-action
timeout, run `42809032972` (`ab27e54`) published this branch successfully:
deployment `7681093165` = `success`, Pages `build_type` = `workflow`. The URL
https://fongway94.github.io/WalkInCovenant/ returns the Godot loader and
`index.manifest.json`. This is a preview for the user's playtest, not a release
or a merge to `main`; the release-candidate caveats above still apply.

**Final B v3 browser evidence.** Run `42814917855` failed because an IDBFS
reload race let the engine flush its old new-game state over the seeded duel
save; the duel context resumed as `witness` and 148 presses could not win.
`d6f067c` closes the boot page before rewriting `save.json` from a same-origin
non-game page, then opens a fresh game page and retries up to three times.
Final run `42818980822` reports **seeded fight loaded on attempt 1**,
`DUEL presses=41 won=True ending=True corin=True`, `chromium=158.0.8127.18
checks=30 failed=0 consoleErrors=0 pageErrors=0`. `visual_diff.py` is clean
for 17/17 frames and deployment `7682580911` succeeded. This remains a working
branch **Release candidate, not release**; the live URL is a preview for human
playtest, not a `main` release.
