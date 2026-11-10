# DEVELOPMENT_BACKLOG — ordered, with reasons

Ordered by what blocks release first, not by what is fun to build. Each item
names its evidence and its acceptance test so the next session does not have to
re-derive it. `docs/DAVID_CHAPTER_PLAN.md` holds the design; this is the queue.

Size: **S** ≤ half a day · **M** a day · **L** more than a day, and split first.

---

## Status at 2026-11-06 (premium-art / climax pass — supersedes the table below)

| # | State | Evidence |
|---|---|---|
| 1 Device pass | **Still open. Highest remaining risk.** | No phone, two aspect ratios, browser-export run or hardware screenshot. Nothing in this pass changes that. |
| 2 Listen to the audio | **Still open.** | 16 SFX / 3 beds remain checked as state, never heard. The duel now has a new backdrop but no new sound; no audio claim is made. |
| 3 Screenshot inspection | **Done for fourteen rendered beats, including the climax, not for a camp close-up or a device.** | `tests/visual.gd` grew from 12 to 14 frames; `13_duel` renders the shipped `GoliathFight` with its drawn 64px/32px figures and directed valley, `14_aftermath` renders the empty ridge. All 14 decoded PNGs were reviewed as a sheet and as 3× zooms, then promoted as baselines. Nine defects (BUG-052…061) came from looking at them; a red CI run and two green runs are recorded in `docs/BUG_TRACKER.md`. A camp close-up, a handset screenshot and a browser screenshot remain open. |
| 4 Premium art | **Landed, with a reviewed before/after.** | 18 drawn 32×32 portraits, distinct cast silhouettes, dedicated duel figures, directed duel backdrop, opaque dialogue box and flat HUD/caption plates. Six candidate asset sources verified against real downloaded PNGs and licences; all rejected for style/rights (`assets/LICENSES.md`, `docs/ART-COMPARISON.png`). Chosen direction is original palette-locked art, gated by the stdlib-only `tools/check_faces.py` and `data/art_hashes.json`. |
| 5 Defects found by looking / red runs | **Nine more, all with a check or a frame.** | BUG-052…061 in `docs/BUG_TRACKER.md`: frozen chatter bubble, standing giant after the win, Pillow-dependent CI gate, 12 publish steps for 14 frames, aim band behind the sprite, 7px CJK and empty portrait frame, ghosted dialogue panel, shadow-garbled HUD, striped scrim and non-deterministic caption. No check was weakened. |
| 6 Chinese editorial pass | **Still partly open.** | Rendered-context review of `09_chinese_2x`, the journal's marked Scripture, the duel hints and the six ending lines; `check_font` maps 826 codepoints. No native-speaker/author listening pass and no handset legibility judgement. |
| 7 Full chapter | **Automated completion proof exists.** | `smoke: PASS — the slice played start to finish` drives brook → flock → armour → five stones → three duel hits through `Phase.DONE` → aftermath → all six ending lines → `act_id() == "done"`, seals, relics, save file and the Bethlehem road. `deep: PASS — 141 checks hold`. This is not a human playtest. |

---

## Status at 2026-11-05 (the David's Life Before the Battlefield milestone)

| # | State | Evidence |
|---|---|---|
| 1 Device pass | **Still open. Highest remaining risk.** | No phone, two aspect ratios, browser-export run or hardware screenshot. `docs/DEVICE-CHECKLIST.md` is the untouched script. |
| 2 Listen to the audio | **Still open.** | 16 SFX / 3 beds asserted as state only; never heard. Two new sounds (horn, sheep bleat) were added this pass and are likewise unheard. |
| 3 Screenshot inspection | **Done for twelve frames, not for the duel/camp or a device.** | CI renders real frames under Xvfb + llvmpipe; `frames/01_boot_world` … `12_journal_before` were decoded and looked at, and five real defects fixed from them (bubble slab, simultaneous bubbles, horn toast over the flock, unreadable/ghosted optional rows, CJK glyph clipping). Twelve reviewed `tests/frames/baseline_*.png` are committed and `visual_diff: clean`; `tests/visual.gd` compares them in-engine on every push. The duel and a camp close-up are still uninspected; see `docs/VISUAL-TESTING.md`. |
| 4 Spine reorder | **Done.** | `smoke: PASS` with the anointing on the required path; a Bethlehem save resumes in Bethlehem; version-1 saves migrate. `docs/ITERATION.md` §2. |
| 5 Act 1 flock / lion's ground | **Done for the flock; Jesse still a voice, not a standing NPC.** | Sheep now graze, startle, build trust, bleat and must be driven from behind the fold; three tempers, per-animal completion, `elah_flock_done` flag, dusk → morning. Covered by `smoke.gd` and `deep.gd`. The lion's ground remains a line, not a scene. |
| 11 Chinese editorial pass | **Partly done, extended.** | Bethlehem/family/Samuel/David scenes rewritten and Scripture marked; camp aphorisms rewritten, Corin's narration split into two pages, chatter cut to ≤12 characters, hired boy's lines change on `by_flag`. No native-speaker/author listening pass; 9 px rendered Chinese read only in software GL. |

The queue below is kept as originally written so the reasoning and acceptance
tests survive; the table above is the current truth.

---

## Now — before any new content

| # | Item | Size | Why it is first | Done when |
|---|---|---|---|---|
| 1 | **Device pass.** One real phone, landscape, two aspect ratios, thumbs through both chapters. | M | Every visual, audio and tactile claim in this repo is geometric. It caps all ten scores and nothing else can lift them. `docs/DEVICE-CHECKLIST.md` is the script. | Screenshots and a written note of what broke, filed as bugs. |
| 2 | **Listen to the audio.** The 14 SFX and 3 beds have never been heard. | S | Ducking, crossfades and levels are asserted as *state*, not as sound. | A list of what is wrong (loud, repetitive, clipped, absent). |
| 3 | **Screenshot inspection.** Even headless: `--headless` cannot render, but CI can run a windowless Vulkan/dummy render for a still, or the export can be opened in a browser here. | M | "No frame has ever been looked at" is unacceptable in a pixel-art game. | At least: the valley, the camp, the duel, one dialogue box, the journal — reviewed as images. |
| 4 | **Spine reorder: 1 Samuel 16 becomes Act 2** (`DAVID_CHAPTER_PLAN.md` §1). | L | The chapter's emotional centre is currently optional and last. It is the single biggest story defect left. | `smoke.gd` passes with the anointing on the required path; a save taken in Bethlehem resumes in Bethlehem. |

## Next — depth in the chapter that exists

| # | Item | Size | Why | Done when |
|---|---|---|---|---|
| 5 | Act 1: flock, the lion's ground, "bring them in", Jesse at the fold. | L | The calling lands on a stranger because there is no ordinary day to interrupt. | A player who explores the slope can describe David's day; the call interrupts a task. |
| 6 | Act 4: `by_act` lines for the four camp people, where they talk past the boy from Bethlehem (17:28–30 played, not narrated). | M | Cheapest large gain in immersion; the machinery landed this pass. | Talking to all four as David differs from talking to them as the witness. |
| 7 | Two quiet beats: the walk to the water, and the seconds after the fall. | S | The chapter has no rests, so nothing lands hard. | Neither beat adds a line of exposition. |
| 8 | Second music bed for the aftermath; the valley gets an ambient overlay. | M | One song carries the whole duel and its silence. | The post-victory read is not the battle track. |

## Later — polish, in the order it will be noticed

| # | Item | Size |
|---|---|---|
| 9 | `Hud.journal_btn` and the two switches to ≥44 px physical targets (O-3), once a device says what fits. | S |
| 10 | `Main._update_guidance()` loses its side effects (O-2): guidance reads, `Main` acts. | M |
| 11 | Chinese editorial pass over `elah.json`'s aphorisms ("他错在以为，年轻就什么都不是"), with the author listening. | M |
| 12 | Camp work: mending, cooking, a queue at the water. Scenery that implies labour. | M |
| 13 | Resume mid-brook re-walks the brook (O-1) — decide whether the resume should restore the pouch instead. | S |
| 14 | **Human playtest, opening → conclusion, before any public release.** The one gate the browser job cannot pass. Record confusion, pacing and emotional closure. | M |
| 15 | Listen to the mix on speakers/headphones: BGM loop seams, SFX overlap, ambience transitions, volume balance. Technical WebAudio checks are green; perception is not. | M |
| 16 | Native-speaker / author Simplified Chinese pass, including the 石子 / 石头 register split and the aphorisms. Scripture stays verbatim. | M |
| 17 | Real-device pass: tactile thumb reach, OS rotation, notch/safe area, legibility on an actual handset. Browser emulation is not this. | M |
| 18 | Hide or fade the touch A/RUN circles for keyboard-only desktop play — only after a device says which input mix to prefer, and with 14 baselines regenerated. | S |
| 19 | **PARTIAL (one scene, 2026-11-10).** 13 hand-authored opt-in props and 4 character sheets (`pilgrim`, `shepherd`, idle/walk × 4 facings) exist for BOTH directions: `art/props_storybook/` + `art/characters_storybook/` (C) and `art/props_cinematic/` + `art/characters_cinematic/` (user-selected B). Ink outlines, clothing folds, a shared contact shadow and an animated B rim light are present; frame counts are identical. **Still required:** hand-pixel-edited 16×24 / 16×32 cycles for every other actor, hand-tiled terrain with seam testing, and a manual art-director pass. The current files are program-authored primitives, not professional illustration. See `docs/ART-RESET.md` §12.4 and §12.7. | L |
| 20 | **MEASURED, PARTIAL (one scene).** C's four CI passes recovered world value spread **10.6 → 17.7** (`42784090190`). B v2's real CI `42798442187` measures **20.5** (first B 16.1; classic 20.4; B concept 22.6) and world luma **68.0** (concept 86.6). **Still open:** classic 20.4 is inflated by its HUD scrim; B is still darker and far less edge-dense than the painterly concept. Raise it further only with real layered geometry, not stronger overlays. See §12.7.1. | M |
| 21 | Give Bethlehem, Saul's court and the valley distinct rendered environments and location-specific atmospheric palettes. Samuel's anointing and Saul's court currently have **no world at all** — they are dialogue over the same two maps. Direction B exists for the shepherd field only. | L |
| 22 | **PARTIAL (one scene).** `TerrainLayer._draw_depth()` (C) draws far/middle/near value planes; `_draw_cinematic_depth()` (B) adds camera-relative golden-hour light, a dry-stone wall, a winding sunlit path and diagonal cast bands. `ContactShadowLayer` grounds every figure and adds B's long cast; `GoldenRimLayer` adds B's animated rim. **Still required:** real geometry/parallax, building volume, natural landmarks, per-location light, and restyling the journal, menus and transitions. | L |
| 23 | Only AFTER 19–22: replace the default atlas, regenerate all 16 baselines, and re-run the browser + human playtest gates. Keep every checkpoint reversible. **Only `baseline_16_shepherd_cinematic.png` was regenerated**, from reviewed real CI `42798442187`; C's final frame is preserved as `comparison/16_storybook_final.png`. The default atlas has NOT been replaced; no PR, merge or deploy. | M |

## Standing rules for every item

- A bug is closed by a check that failed before the fix, not by a diff.
- No test is deleted or weakened to make CI green. The regression suite fails if
  it runs fewer than `MIN_CHECKS` checks, and prints the count.
- Content is data. If a beat needs a script, it belongs in a campaign script or
  in `Main`, and it says why in a comment.
- Scripture stays verbatim, in the chosen translation, marked as Scripture, and
  never mixed into invented dialogue's quotation marks.
- Nothing is claimed as tested that was not run.
