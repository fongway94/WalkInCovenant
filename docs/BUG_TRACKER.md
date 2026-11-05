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

Full per-run detail, including every red run and the bug each one exposed, is in
`docs/ITERATION.md` §6.
