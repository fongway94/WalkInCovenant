# ITERATION — David's Life Before the Battlefield

**Milestone directive (2026-11-05):** correct narrative chronology, a functional
playable shepherd-life opening, meaningful NPC/environment interaction, natural
Chinese dialogue, no known blocking progression bugs, updated automated tests,
and an honest visual/audio verification record. No new Bible chapter. No
unnecessary rewrite of stable systems.

This is the working record for the session. `docs/ROADMAP.md` is the historical
roadmap, `docs/BUGS.md` the bug archive, `docs/BUG_TRACKER.md` the live tracker,
`docs/DEVELOPMENT_BACKLOG.md` the ordered queue.

---

## 0. Starting state (verified, not assumed)

- Branch `arena/8520915e-walkincovenant`, clean at `21f5824` (merge of PR #3,
  pass 4). Identical to `main`.
- CI run `41976218706` on `main`: lint ✅ · export-web ✅ · deploy ✅.
  `run_all: ALL CHECKS PASSED`, `smoke: PASS`, `deep: PASS — 109 checks hold`.
- Live PWA: https://fongway94.github.io/WalkInCovenant/
- Local static gates all clean (9 tools). No Godot binary, no display, no
  browser, no sound card, no phone in the authoring sandbox.
- **Doc sync done this session:** `README.md` status block and current-state
  note, `docs/ROADMAP.md` phase heading + pointer to the queue,
  `docs/PROJECT_AUDIT.md` §6 scores (Biblical accuracy 8→9, Story immersion
  6→7 with evidence), `docs/BUG_TRACKER.md` Open-section pointer to O-1…O-7.

## 1. Priority 1 — a real gameplay testing capability

Investigated first, because every other judgement in this milestone depends on
being able to see something.

- Tried and **ruled out** locally: a Godot binary from GitHub releases (302 →
  `release-assets.githubusercontent.com`, blocked), a headless Chromium from
  npm (`@sparticuz/chromium` is downloadable but there is no local web export
  to point it at), CI artifacts and raw logs (Azure / results-receiver hosts
  blocked), the live Pages site (blocked host).
- **Found working:** check-run annotations on `api.github.com` are readable
  with `gh api`, so CI can hand rendered PNGs back as base64.
- **Built:** `tests/visual.gd` + `tests/visual.tscn` (boots the shipped
  `Main.tscn`, drives a real `InputEventAction`, captures six named beats,
  checks colour diversity/luma, compares committed baselines), a `visual` job
  in `.github/workflows/build-web.yml` (downloads Godot 4.7.2 on a hosted
  runner, Xvfb + llvmpipe, console/runtime error gate, base64 annotations,
  artifact upload), `tools/decode_frames.py`, `tools/visual_diff.py`,
  `docs/VISUAL-TESTING.md`.
- **Preserved:** all three existing suites and all nine static gates, unchanged.

Verification: see §6 below (CI run ids and what the frames showed).

## 2. Priority 2 — correct chronology

_Status: in progress._ Design: `docs/DAVID_CHAPTER_PLAN.md` §1. The south road
opens on `elah_met_the_line` rather than `elah_ended`; a new `elah` mission
`bethlehem_call` completes on `beth_anointed`; BECOME fires when the player
walks back from Bethlehem. Legacy saves get a `legacy_spine` migration so a
version-1 save mid-David-chapter is not sent backwards.

## 3. Priority 3 — a playable shepherd-life opening

_Status: in progress._

## 4. Priority 4 — Chinese dialogue, scene-level

_Status: in progress._

## 5. Priority 5 — quality review

_Status: pending; will be written after the implementation is verified._

## 6. Verification record

| Run | Commit | Result |
|---|---|---|
| `41976218706` | `21f5824` | baseline before this session: all green |
| `41978406540` | `07d890d` | first real render: 5 PNGs + `frames` artifact; notices truncated at 4096 chars; the final gate failed on `continue-on-error` semantics |
| `41978946511` | `8c857e5` | 3 of 5 frames decoded; harness verdict published: one failed assertion (`an interact action opens a conversation`) because the player stood on the south exit, not beside Corin |
| `41979819655` | `45defed` | visual ✅; smoke found a real bug: the witness beat left the world paused, so the road south answered no input |
| `41980997515` | `b0ea215` | visual ✅ with 5 complete frames; smoke found a second real bug: two chained crossing boxes needed a quiet-drain |
| `41981486351` | `c369f31` | visual ✅, all 5 frames decoded and inspected; smoke down to one wrong assertion (`_in_battle` is a fade guard, not chapter state) |

## 7. Decisions taken without asking (and their trade-offs)

1. **Rendered frames come from CI, not from a local Godot install.** This is
   slower (one push ≈ 3–6 min per iteration) but it is the only path the network
   permits. Documented honestly in `docs/VISUAL-TESTING.md`; no claim of device
   verification.
2. **The visual job is a separate workflow job**, not folded into `lint`, so a
   software-GL failure cannot hide a green content lint. `deploy` still depends
   only on `export-web`.

_(This file is updated as the milestone proceeds.)_
