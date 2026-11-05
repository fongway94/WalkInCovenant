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
- **Doc sync done this session, before any milestone code:** `README.md` status
  block and current-state note, `docs/ROADMAP.md` phase heading + pointer to the
  queue, `docs/PROJECT_AUDIT.md` §6 scores (Biblical accuracy 8→9, Story
  immersion 6→7 with evidence), `docs/BUG_TRACKER.md` Open-section pointer to
  O-1…O-7.

## 1. Priority 1 — a real gameplay testing capability — **DONE**

Investigated first, because every other judgement in this milestone depends on
being able to see something.

- Tried and **ruled out** locally: a Godot binary from GitHub releases (302 →
  `release-assets.githubusercontent.com`, blocked), a headless Chromium from
  npm (`@sparticuz/chromium` downloads but there is no local web export to
  point it at), CI artifacts and raw logs (Azure / results-receiver hosts
  blocked), the live Pages site (blocked host).
- **Found working:** check-run annotations on `api.github.com` are readable
  with `gh api`, so CI can hand rendered PNGs back as base64.
- **Built:** `tests/visual.gd` + `tests/visual.tscn` (boots the shipped
  `Main.tscn`, drives a real `InputEventAction`, captures six named beats,
  checks colour diversity/luma, compares committed baselines), a `visual` job
  in `.github/workflows/build-web.yml` (Godot 4.7.2 on a hosted runner, Xvfb +
  llvmpipe, console/runtime error gate, base64 annotations, artifact upload),
  `tools/decode_frames.py`, `tools/visual_diff.py`, `docs/VISUAL-TESTING.md`.
- **Preserved:** all three existing suites and all nine static gates were kept
  and extended, never weakened.

**Verified capability, not assumption.** The visual job reported
`input_routed=true parsed_opens=true direct=false`: a parsed `InputEventAction`
really reaches `Node._unhandled_input` and opens a conversation; the direct
handler fallback was never needed. Console/runtime error gate passes once
Godot's benign "N resources still in use at exit" shutdown notice is excluded.

Two transport defects were found and fixed by observing CI, not by guessing:
GitHub truncates an annotation at 4096 characters (50 KB chunks were useless),
and a step may emit ~10 notices. Frames are now 3500-character base64 chunks of
a 64-colour quantised copy, spread round-robin over eight short steps.

**Six real frames decoded and inspected by eye** (`python3
tools/decode_frames.py <run-id>`): the valley with HUD/tents/NPCs, the prologue
box, Corin's conversation box, the journal page, the Bethlehem place card over a
second map, and the shepherd slope with the fold, sheep and the live objective
`天黑前，把走散的三只羊赶回圈里 0/3`. Six reviewed captures were committed as
`tests/frames/baseline_*.png`; `tools/visual_diff.py` reported diffs of
0.0004–0.0164 for frames 01–05 after the content changes, all far below the
0.18 limit, then `visual_diff: clean` after promotion. The engine's own
`Image.load_from_file` comparison ran green in CI on run `41981915709`.

**Still not possible here:** a real phone in two aspect ratios, one audio
sample, tactile feel, or browser-export testing. No claim of device, audio or
visual *quality* verification is made.

## 2. Priority 2 — correct chronology — **DONE**

- `data/regions/elah.json`: the south exit now requires `elah_met_the_line`
  instead of `elah_ended`; a new `bethlehem_call` mission sits between
  `witness_line` and `shepherd_drill` and completes on `beth_anointed`;
  the crossing beat and the HUD now point south to 1 Samuel 16.
- `Main._begin_become()` fires when the player walks **back** from Bethlehem:
  `MissionRunner.first_unmet(ctx)` lands on `shepherd_drill`. The "three days
  earlier" framing was removed from the shepherd and errand beats, because with
  1 Sam 16 in its place it is no longer a flashback.
- **Two real progression bugs were found by the updated smoke test and fixed:**
  1. `_witness_at_the_line()` paused the valley and only BECOME used to unpause
     it; with a road to walk, the world answered no input at all. It now
     unpauses before the runner advances, and `_begin_become()` re-pauses
     itself when a legacy save starts it.
  2. The crossing opens two chained boxes (mission brief, then the trigger
     beat); the test needed a quiet-drain, and the beat is now guarded against
     replaying.
  3. `_in_battle` is a fade guard, not a chapter state — the assertion that
     treated it as one was replaced with a check on the *order* of the two
     chapters (`elah_drill_done` must still be false at the anointing).
- **Legacy saves.** `GameState.SAVE_VERSION` 1→2; `_migrate()` marks a
  version-1 save that is already inside David's chapter as `legacy_spine`.
  `Main._mission_ctx()` then lets **only the runner** treat `beth_anointed` as
  met, so that player resumes exactly where they left off instead of being
  dragged backwards; the real story flag stays false and the road stays open.
  `tests/deep.gd::_check_legacy_spine()` writes a synthetic version-1 save and
  asserts all five of those behaviours.
- `tests/smoke.gd` was restructured so the Bethlehem chapter plays before
  `act_id() == "shepherd"`, and a late section re-walks the road after the
  ending. Acceptance from `docs/DEVELOPMENT_BACKLOG.md` #4 is met: smoke
  passes with the anointing on the required path, and a Bethlehem save resumes
  in Bethlehem.

## 3. Priority 3 — a playable shepherd-life opening — **DONE (small, deliberately)**

The five narration lines on the slope were replaced with **three** lines and a
job. Built, in data where possible:

- `art/props/{sheep,fold,wool_tuft}.png` and matching generators in
  `tools/artgen/props.py` + `data/props.json` (22 props, all non-blocking).
  Four standing sheep and two hurdles make the fold a place; a broken lower
  rail, thorn bush and wool tuft mark the lion's ground without a quest marker.
- A **herding task**: three strays spawned as `"flock"` pickups at different
  corners of the slope. Walking to one brings it home. `Main._start_flock()`
  derives the count from Region's `pickup:` flags, so a mid-flock save resumes
  mid-flock (`tests/deep.gd::_check_flock_resume()`). The HUD shows
  `天黑前，把走散的三只羊赶回圈里  n/3` and points at the nearest stray.
- **Optional discovery:** curio `lions_ground` with three short first-person
  lines of David's own memory. No marker, no reward, no journal entry, no moral.
  It sits beside the third stray so exploration is what finds it.
- **An NPC who answers to the act:** `hired_boy` (actor `shepherd`) at the fold,
  with `by_act.witness` and `by_act.shepherd` lines. During the shepherd act he
  lifts the rail aside so the player can get through — a small action, not a
  speech. Jesse remains a voice from the doorway (as the data already had him)
  rather than a standing NPC in a war camp: putting the Bethlehem father in the
  middle of the Israelite battle line during the witness act would be a worse
  story error than leaving him off-screen.
- **Transition:** the opening line `头发上还有油味，家里没人再提昨天的事` ties
  the slope to the anointing the player has just witnessed; Jesse's call to
  bring the bread interrupts the finished herding job; the sling drill follows;
  the errand then opens with a family exchange in which David asks `「羊呢？」`
  and his father answers `「我看着。你早去早回。」`.

**Not built, on purpose:** wandering/animation for the sheep, a second
mechanic, or a larger map. The strays are static sprites and the task is
"walk to three of them" — a small polished sequence first, as directed. This is
the main thing still limiting the RPG feel (see §5).

## 4. Priority 4 — Chinese dialogue, scene-level — **DONE for the named scenes**

Reviewed in context: David's family interactions, Samuel's arrival, David's
responses, emotional transitions and NPC reactions.

- Removed literary abstractions and aphorisms: "When a prophet comes to a small
  town, it is never for a small reason", "Everything here is small, and
  everything here is watched", "Fathers are the last to be told", "I am the
  eldest. Whatever is beginning in this house should have begun with me", "He
  does not look at you the way the town looks at you", "This is not a thing a
  bystander can carry", "You have seen the end of this story and now its
  beginning". Replaced with concrete action or plain speech (a woman drawing
  two buckets she does not carry away; a father keeping one hand on the
  doorframe; `「他没说要找哪一个。我就把他们都叫来了。」`).
- Removed the generic inspirational/foreshadowing closing line that had Samuel
  predicting "the valley, the giant, all of it" — with the corrected chronology
  the player has *come from* the valley. It is now `「回去的路在下面。想走就走吧，这里没你要做的事了。」`
- **Scripture distinction.** In `bethlehem.json` scenes the narrative KJV/CUV
  verses were attributed to `who: "samuel"` and wrapped in 「」/“”, i.e. dressed
  as invented conversation. They are now `who: ""`, prefixed `[Scripture]` /
  `【经文】`, and carry no fictional quotation marks. The verse wording itself
  was compared string-by-string against the previous file and is **verbatim
  unchanged** (EN and ZH). `tests/run_all.gd` now fails if a marked Scripture
  line has a speaker or sits inside 「」. Verses that ARE spoken by a person in
  the Bible (David's 17:34–37, Eliab's 17:28, Goliath's taunts) keep their
  rightful speaker and their own `1 Samuel` reference line — that is not the
  same case.
- `fonts/game.ttf` rebuilt from Noto Sans SC after each content change; the
  `check_font` gate is green (811 codepoints).

## 5. Priority 5 — quality review (evidence, not a score sheet of 10s)

Judgements below are tied to an inspected frame, a CI assertion or a line of
data. **The opening is better but is not yet a compelling RPG opening.**

| Question | Verdict | Evidence |
|---|---|---|
| Immediately interesting? | **No — 4/10** | A new player reads a 5-line prologue, then a briefing, before the first step. Frame `01_boot_dialogue` is a text box over a static valley. The briefing was cut from 5 lines to 3 this session (§6), but the prologue still fronts the game. |
| Action rather than only reading? | **Yes after the reading wall — 7/10** | `tests/smoke.gd` walks to three stray tiles and asserts `sheep_home == 3`, drains the lion's-ground discovery, performs 3 timed sling throws, collects provisions, dodges and throws in the duel. Corin stands one tile from the spawn, so the first button press is immediately available after the words. |
| Clear objectives? | **Yes — 8/10** | Inspected `06_flock`: HUD reads `天黑前，把走散的三只羊赶回圈里 0/3`; `_update_guidance()` points an arrow at the nearest unclaimed stray and updates the counter each frame. Inspected `04_journal`: objective, verses and seals on one page. |
| NPCs feel like characters? | **Partial — 6/10** | The hired boy answers to two acts and lifts the hurdle; the woman at the well has a concrete, unspoken detail; David asks about the sheep. But the four camp NPCs still have one line per act and no schedules, expressions or voices. `bethlehem.json` / `elah.json` `by_act`. |
| Rewards exploration? | **Partial — 5/10** | The broken hurdle gives three quiet lines with no marker and no reward, and is placed beside a stray; `elah.json` has 5 curios total. There is no other discovery in the new opening and no consequence for finding it. |
| Transitions emotionally? | **Better, still abrupt — 6/10** | The anointing now precedes BECOME; the oil-scent line and Jesse's call connect the two chapters. But the fade still cuts from Bethlehem to the elah slope with no walk home, and the frame change is not shown. |
| Feels like an RPG? | **Partial — 6/10** | Movement, pickups, a timed drill, a dodge/throw duel, XP, seals and a journal are real systems. The herding task is still "walk to three dots" with no resistance, and the sheep do not wander, so the world is a stage rather than a place that lives. |

**No automatic high scores.** The weakest observation is the reading wall; the
strongest is that six real engine frames now exist and can be compared on every
push. Audio, device and tactile judgements are **not made at all** — there is no
evidence for them.

### Highest-impact remaining weaknesses, in order

1. **The first 30 seconds are still ten lines of text** (5-line prologue +
   3-line briefing + a place card) before movement. Partly addressed this
   session (briefing 5→3); the prologue is untouched.
2. **No device, audio or tactile verification.** Unchanged from the starting
   state; it caps every presentation score. `docs/DEVICE-CHECKLIST.md` remains
   the script.
3. **The flock is static and the herding has no resistance.** Sheep do not
   wander; walking within 10 px collects one. A sheep that drifts or startles
   would cost little and change the feel most.
4. **`elah.json` still contains aphorisms** in camp NPC and ending lines
   (backlog #11). The Bethlehem/family pass removed the worst of them, not all.
5. **10 px Chinese at 320×180** looked legible in the inspected frames but is
   unverified on a real phone in two aspect ratios.

## 6. Verification record

| Run | Result |
|---|---|
| `41976218706` (`21f5824`) | baseline before this session: all green |
| `41978406540` (`07d890d`) | first real render: 5 PNGs + `frames` artifact; notices truncated at 4096 chars; final gate failed on `continue-on-error` semantics |
| `41978946511` (`8c857e5`) | 3/5 frames decoded; harness verdict published: `an interact action opens a conversation` failed because the player stood on the south exit, not beside Corin |
| `41979819655` (`45defed`) | visual ✅; smoke found a real bug — the witness beat left the world paused, so the road south answered no input |
| `41980997515` (`b0ea215`) | visual ✅ with 5 complete frames; smoke found a second real bug — two chained crossing boxes needed a quiet-drain |
| `41981486351` (`c369f31`) | visual ✅, 5 frames decoded and inspected; smoke down to one wrong assertion (`_in_battle`) |
| `41981915709` (`5867eda`) | **all green**: `run_all: ALL CHECKS PASSED`, `smoke: PASS`, `deep: PASS — 114 checks hold`, `visual: PASS — 5 rendered frames` with in-engine baseline comparison |
| `41982749491` (`56e692a`) | `visual: PASS — 6 rendered frames`; `06_flock` inspected; smoke found one stale assertion (`4 people in the valley (got 5)` — the new hired boy) |
| `41983194255` (`9e742c7`) | **all green**: `run_all: ALL CHECKS PASSED`, `smoke: PASS — the slice played start to finish`, `deep: PASS — 114 checks hold`, `visual: PASS — 6 rendered frames` |
| `41990823604` (`85c7961`) | **all green**: `run_all: ALL CHECKS PASSED`, `smoke: PASS — the slice played start to finish`, `deep: PASS — 117 checks hold`, `visual: PASS — 6 rendered frames`, lint ✅ · export-web ✅ · deploy skipped (working branch). This push added the Scripture-separation gate, the flock-resume regression, six reviewed baselines and the 3-line briefing. |

Local gates after every stage: `gd_lint`, `check_export`, `xref_check`,
`api_check`, `check_font`, `check_audio`, `check_chars`, `check_text_fit`,
`pack_art` — all clean; `pack_art: clean — 49 tiles (15 keys), 22 props`.
`python3 tools/decode_frames.py` and `tools/visual_diff.py` were both run
against real runs; nothing in this file is claimed tested unless it was run.

## 7. Decisions taken without asking (and their trade-offs)

1. **Rendered frames come from CI, not from a local Godot install.** Slower
   (one push ≈ 3–6 min per iteration) but the only path the network permits.
   No claim of device verification.
2. **The visual job is a separate workflow job**, not folded into `lint`, so a
   software-GL failure cannot hide a green content lint. `deploy` still depends
   only on `export-web`.
3. **Quantise the transported PNG to 64 colours.** The artifact keeps the
   engine's truecolour capture; only the annotation copy is quantised to stay
   under GitHub's annotation cap. The coarse 32×18 grid diff tolerates it
   (measured 0.0004–0.0164 after real content changes, limit 0.18).
4. **Legacy saves are marked, not rewritten.** `legacy_spine` lets the runner
   skip the new Bethlehem mission without inventing `beth_anointed`, so a
   version-1 save neither rewinds nor loses a chapter it never saw.
5. **Jesse is a voice, not a standing NPC in the valley.** Same map serves the
   witness's war camp and David's slope; adding the Bethlehem father to the
   battle line creates a worse inconsistency than leaving him in the doorway.
6. **The shepherd sequence is small.** Three strays, one optional discovery,
   one NPC, one transition. No wandering rig, no second mechanic, no map
   change — the directive asked for small and polished, not a feature set.
7. **The briefing was cut 5→3 lines** as the first "keep improving" step after
   the milestone review: the on-screen thumb stick, the contextual `A · 交谈`
   prompt and the waypoint arrow already teach what two of those lines said.

_(Sections 1–7 are the David's Life Before the Battlefield milestone. Section 8
is the pass that followed it.)_


---

## 8. LIVING WORLD — the pass after the milestone (2026-11-05)

The milestone left five open weaknesses on its own list: a reading wall, static
sheep, no optional reason to return to the book, silent NPCs, and no weather or
time of day. This pass took those five, not a new chapter. The directive was
still "small and polished, not a feature set", and no stable system was
rewritten.

### What changed

- **Immediate control.** `Main._opening()` no longer forces the prologue,
  briefing and place card. The player moves within the first frame; CI measures
  boot-to-control at 8–14 ms and 0 forced pages. The arrival prose is still
  there for the curious: `journal.before` → 「来路」 / "How you came here", at
  the bottom of the book, reachable by scrolling (`12_journal_before`).
- **The sheep are animals.** `scripts/world/FlockSheep.gd` is a real state
  machine (`GRAZE / ALERT / HERDED / GOING_HOME`) with three tempers, trust
  that builds when you drive from *behind* the fold, a 0.7 s startle when you
  come at them from the front, two-frame animation, bleats and per-animal
  completion. `Region.collect_pickup(id, guided)` sets one flag, updates the HUD
  once and opens the save door; `elah_flock_done` changes what the hired boy
  says. `SAVE_VERSION` went 1 → 2.
- **People speak without being asked.** `Npc` has short bilingual chatter
  (~16 s, one voice at a time, wall-clock gated), `emote()` reactions to the
  flock, and `by_flag` lines that take precedence over `by_act`. Every chatter
  line is ≤12 characters in both languages, guarded by `run_all.gd`.
- **Time passes.** The chapter opens at dusk and the errand begins in the
  morning; wheat, bushes and wool tufts sway ≤1 px and freeze while the world
  is paused. A horn and a bilingual toast mark the first call at boot.
- **Twelve rendered beats.** `tests/visual.gd` grew from six to twelve states
  (`01_boot_world` … `11_transition`, `12_journal_before`), asserts a physical
  640×480 framebuffer with a logical 320×240 4:3 view, drives real parsed input
  through `_unhandled_input`, and survives `_swap_region()` without reading a
  freed node. `tests/deep.gd` reached 134 checks.

### Verification chain (every red run is listed)

| Run | Commit | Result |
|---|---|---|
| `42010446492` | `a8666b0` | **red** — `Cannot infer type of "away0"` in `smoke.gd:643` / `visual.gd:184`. Fixed by typing five `Vector2` locals. |
| `42011308826` | `a7fc8a5` | **green** — `deep: PASS — 130 checks hold`, 11 frames. Review found a black slab over `06_flock`. |
| `42013468346` | `5ac37ad` | **red** — lint green (134 checks), visual `previously freed` `region_id` + timeout, 9 frames. Fixed with live `main.region` / `is_instance_valid`. |
| `42014467946` | `08cc8a4` | **green** — `run_all: ALL CHECKS PASSED`, `smoke: PASS`, `deep: PASS — 134 checks hold`, `visual: PASS — 12 rendered frames, control=8ms/0 pages, 4:3fb=640x480 logical=320x240, input_routed=true parsed_opens=true direct=false`. |
| `42015418307` | `b2fb9f1` | **red** — `api.github.com` class-reference outage → 76 false `xref_check` findings, runtime suites skipped; visual green, 12 frames, but `12_journal_before` lost one transport chunk. |
| `42017005546` | `0a01126` | **red** — offline class reference and 42-chunk transport both worked (all 12 frames decoded), but one new deep assertion about the bubble's Control layout failed. |
| `42018457660` | `903e7bc` | **red** — the diagnostic printed `label 104x24 at 4,3`: the 22 px bubble was shorter than the font's 24 px minimum line height, so it clipped every CJK glyph. Visual green, 12 frames. |
| `42019344693` | `2fe704a` | **green** — `run_all: ALL CHECKS PASSED`, `smoke: PASS`, `deep: PASS — 134 checks hold`, `visual: PASS — 12 rendered frames, control=10ms/0 pages, 4:3fb=640x480 logical=320x240`, lint ✅ · visual ✅ · export-web ✅ · deploy skipped. |
| `42019960134` | `2bf8dc4` | **green** — the opaque bubble; same 134 checks and 12 frames, `control=10ms`. All twelve PNGs decoded and reviewed; these are the frames promoted as baselines. |

Static gates (all nine) were clean at every push: `gd_lint` (32 files, 22
class_names), `xref_check` (32 scripts, 4 autoloads), `api_check` (32 files, 54
engine classes), `check_font` (826 codepoints), `check_text_fit`,
`check_export`, `check_audio` (16 sounds, 3 tracks, 2661.7 KB), `check_chars`
(3 variants / 3 rigs), `pack_art` (49 tiles / 15 keys / 26 props). JSON and
YAML parse, `NP = 12`. The corrected BFS reachability validator reported
`elah 1340/1340` and `bethlehem 900/900` tiles with every named point
reachable and `fold_at [24,34]` walkable; `elah/bethlehem errors: NONE`.

### Three defects found by looking, not by a diff

A coarse 32×18 grid diff (limit 0.18) catches blank and wrong scenes; it did
**not** catch any of these. Each was found in an upscaled CI PNG and fixed:

1. `06_flock` had an 84×150 near-black slab — a `PanelContainer` clamped to an
   unwrapped Chinese Label. Now a fixed 112×28 clipped `Panel` (28 rather
   than 22 because the CJK font's minimum line height is 24 px — a shorter
   bubble clipped the bottom of every glyph).
2. The first-call horn toast appeared over the flock instead of at boot, and
   two or three chatter bubbles arrived at once over the objective band. The
   beat moved to `02_valley`; a single wall-clock gate now governs all chatter.
3. `12_journal_before` showed the optional rows as the dimmest text in the
   book, then as white text under black blotches (a 1 px solid shadow at 9 px).
   Now 9 px / 0.88, no shadow, and the harness scrolls to the heading.

Two more came from the frames and from a *failing check that printed its
numbers*, which is why the diagnostic was added rather than the assertion
dropped:

4. `04_journal` and `12_journal_before` had grey ghost text behind the rows —
   the HUD and dialogue box showing through a 0.97-opaque panel. The panel is
   now fully opaque.
5. The 112×22 bubble was shorter than the bundled CJK font's 24 px minimum
   line height, so the bottom of every glyph was clipped. `deep.gd` printed
   `label 104x24 at 4,3` in run `42018457660`. The frame is now 112×28, the
   label has no shadow, and the check asserts the configured geometry.

### Reliability, not relaxation

`xref_check` already dropped `NO-CLASS` / `OWN-MEMBER` findings when *every*
class lookup failed. The `42015418307` outage was partial, so some classes
resolved and the guard never fired — `Node2D` was reported to exist nowhere and
`Player.global_position` to be a typo. `tools/godot_docs/` now commits the
parsed 4.7-stable class reference for all 54 classes this project uses, with a
`VERSION` file; `api_check.fetch_doc()` prefers it when `VERSION == REF` and
still falls back to the network for an unknown class or a future engine
upgrade. **No check was weakened.** The same outage now cannot skip the runtime
suites.

The frame transport also hit GitHub's ~50-annotation cap with twelve frames:
`12_journal_before` came back 4/5 chunks. 3800-character chunks (still under
the 4096 truncation) and a 48-colour quantised transport copy brought it to 42
frame chunks; `tools/decode_frames.py 42017005546` wrote all twelve PNGs. The
artifact keeps the engine's truecolour capture.

### Final state

`42019960134` (`2bf8dc4`) is **green**: `run_all: ALL CHECKS PASSED`,
`smoke: PASS — the slice played start to finish`, `deep: PASS — 134 checks
hold`, `visual: PASS — 12 rendered frames, control=10ms/0 pages, 4:3fb=640x480
logical=320x240, input_routed=true parsed_opens=true direct=false`; lint ✅ ·
visual ✅ · export-web ✅ · deploy skipped (working branch). All twelve PNGs
were decoded with `tools/decode_frames.py 42019960134`, inspected by eye (the
sheet and 4× zooms), and promoted with
`PYTHONPATH=/home/user/.cache/pillow_check python3 tools/visual_diff.py
--write-bases`. A plain `tools/visual_diff.py` then reported `diff 0.0000` for
all twelve and `visual_diff: clean`. Run-to-run variation between the last two
green runs was 0.0000–0.0171 on the same coarse grid, far under the 0.18 limit,
so the committed baselines are stable. `tests/visual.gd` compares every later
capture against them in-engine.

### What this pass did **not** establish

- Audio: 16 WAVs and 3 beds are checksum-checked, never heard. No sound card.
- No browser-export run, no real device, no two-aspect-ratio check, no tactile
  judgement. All twelve frames are software GL under Xvfb + llvmpipe.
- No duel or camp close-up; the twelve beats cover boot, valley, conversation,
  journal, Bethlehem, flock, sheep, quest update, Chinese 2×, 4:3 layout,
  transition and the optional book section.
- 9–10 px Chinese read in upscaled PNGs is not a legibility result for a phone.
- `tests/frames/` baselines are a wrong-scene detector, not an art-quality
  verdict. They are promoted only after the frames are inspected by eye.

_(Section 8 is updated as this pass proceeds.)_
