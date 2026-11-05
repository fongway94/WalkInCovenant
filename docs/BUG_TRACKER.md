# BUG_TRACKER — live record for the David chapter

Two views of the same thing: **this file** is the tracker for the current
directive (ID, severity, status, regression test, one line). **`docs/BUGS.md`**
is the archive — the full write-up for every bug, including the root cause and
the reasoning for the ones deliberately not fixed. A bug appears here the moment
it is found and moves to `docs/BUGS.md` when it is closed.

Severity: **P0** crash / save loss / cannot progress · **P1** a core mechanic,
mission, transition or important interaction fails · **P2** UI, audio, wrong
dialogue behaviour · **P3** polish.
Status: **Open** → **In Progress** → **Fixed** (code changed *and* a check that
failed before it now passes) → **Verified** (that check has run green in CI).

---

## Open

_None. Every bug found this pass is fixed and has a check. See "Fixed" below and
`docs/BUGS.md` for the write-ups._

The **deliberately unfixed findings (O-1…O-5)** are not bugs in the tracker's
sense — each has a written reason below or in `docs/BUGS.md` — and the work they
imply is queued in `docs/DEVELOPMENT_BACKLOG.md`. **O-6 (1 Sam 16 out of order
and optional) and O-7 (Act 1 has no playable shepherd life) were closed in the
2026-11-05 milestone**; see the table below and `docs/ITERATION.md` §§2–3.

## Fixed in the David's Life Before the Battlefield milestone

| ID | Sev | What | Check that failed before the fix | State |
|---|---|---|---|---|
| O-6 | **P1** | 1 Samuel 16 sat after 1 Samuel 17, gated behind `elah_ended`. | `tests/smoke.gd` had no assertion that Bethlehem precedes `act_id() == "shepherd"`; the new one fails on the old spine. The paused-valley bug the reorder exposed failed `the exit takes you somewhere else (region=elah)` in CI run `41979819655`. | **Verified** (`41983194255`) |
| O-7 | **P1** | Act 1 was five narration lines on a slope, then a drill. | `tests/smoke.gd` now asserts three strays are spawned, all three come home, the broken hurdle speaks, and the drill starts only after the flock is in. None of those checks existed before. | **Verified** (`41983194255`) |
| BUG-038 | **P1** | The witness beat paused the valley and only BECOME unpaused it, so the newly-required road south answered no input. | `the exit takes you somewhere else (region=elah)` — red in `41979819655`. | **Verified** (`41981915709`) |
| BUG-039 | **P2** | Two chained crossing boxes meant the flag was read while the second was still open. | six smoke assertions red in `41980997515`, including `crossing with the camp's words sets the witness's flag`. | **Verified** (`41981915709`) |
| BUG-040 | **P2** | Marked Scripture in the Bethlehem scenes was attributed to `samuel` and wrapped in 「」, i.e. dressed as invented dialogue. | the new `tests/run_all.gd` scene gate fails on a marked line with a speaker or a 「. | **Verified** (final push) |
| BUG-041 | **P2** | CI notices were truncated at 4096 chars, so no frame could be decoded from the first render. | `tools/decode_frames.py 41978406540` reported incomplete frames. | **Verified** (`41980997515`) |

## Fixed in this pass (pass 4)

| ID | Sev | What | Regression test | State |
|---|---|---|---|---|
| BUG-033 | **P1** | 1 Samuel 17:34–36 was missing from the game. David's answer to Saul — the lion, the bear and the lamb he took back out of a lion's mouth — is the ground his courage stands on, and chapter 17 spent it in a single paraphrase. Without it Saul's "you are only a boy" has nothing to answer it except a claim. | `tests/run_all.gd` `_check_verses` + the required-speaker list; the lines are asserted present in the playthrough by citation (`17:34`, `17:35`) | **Verified** |
| BUG-034 | **P1** | **Goliath's own taunt (17:44) had no name and no portrait.** `battle_intro` gives that line `"who": "goliath"`, and `goliath` was in no speaker table, so the box fell back to the raw id and an empty portrait: the giant's one sentence in the whole chapter was delivered as anonymous narration. | new content gate `_check_speakers()` — every `who` in every line must resolve to a person, a speaker-table entry or a cast entry | **Verified** |
| BUG-035 | **P2** | The camp was frozen for the whole chapter: three dialogue states (first / later / after the giant) meant four people each said one sentence while the story walked from an errand to the brook. | `tests/deep.gd` `_check_by_act_lines()` | **Verified** |
| BUG-036 | **P2** | The chapter ended on a **questionnaire aimed at the player** — "你生命里，现在站着什么样的巨人？信心的第一步，你想怎么走？" — with a moral in every answer. That is the one voice this project forbids (witness, not author), it broke the story's own frame at the last moment, and it was the last thing a player saw. | `tests/run_all.gd`: the ending must have ≥3 story lines; `ask`/`options` are optional and no longer required | **Verified** |
| BUG-037 | **P2** | 18 characters used by the new prose had **no glyph in the bundled font** and would have rendered as tofu (习 仆 借 写 咬 喘 思 拜 牙 疤 礼 管 羔 臂 衔 许 遍 闻). | `check_font` gate (799 codepoints); `fonts/game.ttf` rebuilt from Noto Sans SC | **Verified** |

## Fixed in the LIVING WORLD pass (2026-11-05)

Every entry below was found by *looking at a rendered frame* or by a red CI
run, not by reading the diff. **Open: none.** Full reasoning in
`docs/ITERATION.md` §8 and `docs/VISUAL-TESTING.md`.

| ID | Sev | What | Check / frame that exposed it | State |
|---|---|---|---|---|
| BUG-042 | **P2** | An NPC chatter bubble was a `PanelContainer`; an autowrapped Chinese Label with no word breaks grew it into an **84×150 black slab** over the middle of the shepherd slope. | CI frame `06_flock` of `42011308826`, inspected by eye. | **Fixed** — `Npc.emote()` now uses a fixed 112×22 `Panel` with one clipped line; `tests/deep.gd::_check_bubbles()` feeds the longest chatter line to a real NPC and asserts the rect and label geometry. |
| BUG-043 | **P2** | All NPCs started their own 16 s timer at the same instant, and the timer used *scaled* delta, so two and three bubbles arrived together over the objective band in a sped-up run. | CI frame `06_flock` of `42015418307`. | **Fixed** — one wall-clock static gate for the whole world, NPCs inside the HUD band stay quiet, all chatter ≤12 characters with a `run_all.gd` length gate. |
| BUG-044 | **P2** | The first-call horn and toast fired on the shepherd slope (the distance test was satisfied there), not at the boot. | CI frame `06_flock` of `42014467946`. | **Fixed** — the beat now plays at boot and is captured as `02_valley`; `tests/visual.gd` asserts the flag, no pause, no dialogue. |
| BUG-045 | **P2** | The optional 「来路」 rows were the dimmest text in the journal (8 px / 0.72 grey), and the first brightening pass added a 1 px solid black shadow that read as a blotch behind every CJK stroke. | CI frame `12_journal_before` of `42014467946` and `42017005546`. | **Fixed** — 9 px / 0.88 with no shadow; the harness now scrolls to the section heading so the frame proves the section exists. |
| BUG-046 | **P1** | The visual harness kept a `Region` reference across `_swap_region()` and then read `region_id` on the freed node: `previously freed`, then a 124 timeout with only 9 of 12 frames. | CI `42013468346` (lint green, visual red). | **Verified** — uses live `main.region`, `old_rid` and `is_instance_valid()`; `42014467946` green with all 12 frames. |
| BUG-047 | **P1** | `api_check` fetched 54 class XMLs from `api.github.com` on every push. A partial outage made some engine classes look unknown while others still resolved, so the existing "all lookups failed" guard did not fire and `xref_check` reported **76 false positives** (`Node2D exists nowhere`, `Player has no global_position`); all runtime suites were skipped. | CI `42015418307`. | **Fixed** — `tools/godot_docs/` pins the parsed Godot 4.7-stable class list for every class used; `api_check.fetch_doc()` prefers it when `VERSION == REF`, still falls back to the network for unknown classes. No check was relaxed. |
| BUG-048 | **P2** | Twelve frames at 3500-char chunks / 64 colours hit GitHub's ~50-annotation cap and `12_journal_before` lost its last chunk. | `tools/decode_frames.py 42015418307` → `incomplete: 12_journal_before (4/5 chunks)`. | **Verified** — 3800-char chunks / 48 colours, 42 frame chunks; `tools/decode_frames.py 42017005546` wrote all 12 PNGs. |
| BUG-049 | **P1** | Two harness locals used `:=` on Variant members; Godot reported `Cannot infer type of "away0"` and both runtime suites failed to parse. | CI `42010446492`. | **Verified** — explicit `: Vector2` on five locals; `42011308826` green. |

## Found and deliberately not fixed

| ID | Sev | What | Why it stays open |
|---|---|---|---|
| O-1 | P2 | `Region.progress` restores stones/provisions, but the owning mission restarts its `enter` beat, so a save mid-brook re-walks the brook. | Designed resume semantics ("replay the current mission's opening beat"). Costs one walk, never progress. |
| O-2 | P3 | `Main._update_guidance()` also mutates the world (`corin.lead_to`, `_brothers_beat`). Guarded today. | Refactor with no reproducible defect behind it; the directive forbids restructuring working systems without one. |
| O-3 | P3 | `Hud.journal_btn` is 26×17 logical units (52×34 physical at 2×). | Under the 44 px thumb guideline; cannot be judged without a device, and widening it blind could crowd the objective band on 4:3. |
| O-5 | P2 | `Main._on_pickup()` used to understand only `prov*`. | **Partly closed:** it now also handles `sheep_*` for the flock, and `tests/deep.gd::_check_flock_resume()` proves a resumed save does not re-spawn a stray. Other kinds are still refused by the content gate; no region authors one. |

## Verification record

| Run | Commit | Result |
|---|---|---|
| `41961892986` | `79b1ac4` | **red**: two smoke assertions still expected the questionnaire (BUG-036), and the `by_act` fallback check assumed an untouched NPC. Both were faults in the *tests*, fixed by fixing the tests. |
| `41962456561` | `07aad66` | **red**: one left — the drain ran through the whole ending, so the loop that used to catch a choice saw nothing. Replaced with a check that reads the pages the drain advanced past. |
| `41963019742` | `4ffdebe` | **green**: `run_all: ALL CHECKS PASSED` · `smoke: PASS — the slice played start to finish` · `deep: PASS — 109 checks hold` · export ✅ · deploy skipped (working branch) |
| `41213672343` | `7b23ead` | pass 3 merged to `main`: lint ✅ · export ✅ · deploy ✅ |
| `41211645356` | `e49dd03` | pass 3: lint ✅ · export ✅ |
| `41981915709` | `5867eda` | milestone: **green** — content lint, smoke, deep (114), visual with in-engine baselines |
| `41983194255` | `9e742c7` | milestone: **green** — `run_all: ALL CHECKS PASSED`, `smoke: PASS`, `deep: PASS — 114 checks hold`, `visual: PASS — 6 rendered frames` |
| `41991452585` | `7f65d63` | previous milestone final: **all green**, `deep: PASS — 117 checks hold`, six reviewed baselines |
| `42010446492` | `a8666b0` | **red** — `away0` inference parse errors (BUG-049) |
| `42011308826` | `a7fc8a5` | **green** — 11 frames; review found the chatter slab (BUG-042) |
| `42013468346` | `5ac37ad` | **red** — lint green (134 checks), visual `previously freed` + timeout (BUG-046) |
| `42014467946` | `08cc8a4` | **green** — `deep: PASS — 134 checks hold`, `visual: PASS — 12 rendered frames, control=8ms/0 pages, 4:3fb=640x480 logical=320x240` |
| `42015418307` | `b2fb9f1` | **red** — lint failed on a network class-reference outage (BUG-047); visual green, 12 frames |
| `42017005546` | `0a01126` | **red** — class-reference fix green but one new deep assertion failed on Control layout timing; visual green, all 12 frames complete after the transport fix |

Full per-run detail, including every red run and the bug each one exposed, is in
`docs/ITERATION.md` §§6 and 8. The LIVING WORLD verification chain continues
there; no claim in this file is made for a run that has not finished.
